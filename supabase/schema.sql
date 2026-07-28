-- Planner — Supabase schema
--
-- Run this once in your project's SQL Editor (Supabase dashboard → SQL Editor
-- → New query → paste → Run). It is idempotent, so it is safe to re-run.
--
-- Model:
--   workspace          a team container; everything belongs to one
--   workspace_member   who is in a workspace, and their role
--   board → group → task
--   task_note          team-visible notes on a task, attributed to an author
--
-- Access is enforced by row level security: a user can only touch rows in a
-- workspace they are a member of. The client never filters by user id itself.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Profiles: public user data, mirrored from auth.users
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text        not null,
  full_name   text        not null default '',
  avatar_url  text        not null default '',
  created_at  timestamptz not null default now()
);

-- Keep profiles in sync with auth.users automatically.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Workspaces and membership
-- ---------------------------------------------------------------------------
create table if not exists public.workspaces (
  id         uuid primary key default uuid_generate_v4(),
  name       text        not null,
  color      bigint      not null default 4280514815,
  owner_id   uuid        not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Short shareable code, e.g. PLNR-7K2M, so someone can join a workspace without
-- the owner having to know their email address first.
alter table public.workspaces
  add column if not exists join_code text;

-- Generates a code from an unambiguous alphabet: no O/0, I/1 or similar pairs,
-- because these get read aloud and typed by hand.
create or replace function public.generate_join_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result   text := '';
  i        int;
begin
  for i in 1..4 loop
    result := result || substr(
      alphabet, floor(random() * length(alphabet))::int + 1, 1
    );
  end loop;
  return 'PLNR-' || result;
end;
$$;

-- Assigns a unique code on insert, retrying on the (unlikely) collision.
create or replace function public.assign_join_code()
returns trigger
language plpgsql
as $$
declare
  candidate text;
  attempts  int := 0;
begin
  if new.join_code is not null then
    return new;
  end if;
  loop
    candidate := public.generate_join_code();
    exit when not exists (
      select 1 from public.workspaces where join_code = candidate
    );
    attempts := attempts + 1;
    if attempts > 20 then
      -- Fall back to a longer code rather than looping forever.
      candidate := candidate || substr(md5(random()::text), 1, 4);
      exit;
    end if;
  end loop;
  new.join_code := candidate;
  return new;
end;
$$;

drop trigger if exists on_workspace_join_code on public.workspaces;
create trigger on_workspace_join_code
  before insert on public.workspaces
  for each row execute function public.assign_join_code();

-- Backfill codes for workspaces created before this existed.
update public.workspaces
set join_code = public.generate_join_code()
where join_code is null;

create unique index if not exists workspaces_join_code_idx
  on public.workspaces(join_code);

-- `create type` has no IF NOT EXISTS, so guard it to keep this file re-runnable.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'workspace_role') then
    create type workspace_role as enum ('owner', 'admin', 'member', 'viewer');
  end if;
end
$$;

create table if not exists public.workspace_members (
  workspace_id uuid           not null references public.workspaces(id) on delete cascade,
  user_id      uuid           not null references auth.users(id) on delete cascade,
  role         workspace_role not null default 'member',
  created_at   timestamptz    not null default now(),
  primary key (workspace_id, user_id)
);

create index if not exists workspace_members_user_idx
  on public.workspace_members(user_id);

-- PostgREST can only embed a related table (`profiles(...)` in a select) when a
-- foreign key connects the two. user_id references auth.users, which lives in
-- another schema and is invisible to PostgREST, so member queries failed with
-- "Could not find a relationship between 'workspace_members' and 'profiles'".
-- A second FK to profiles gives it the path. Both point at the same id, so this
-- adds a constraint rather than duplicating data.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'workspace_members_profile_fkey'
  ) then
    alter table public.workspace_members
      add constraint workspace_members_profile_fkey
      foreign key (user_id) references public.profiles(id) on delete cascade;
  end if;
end
$$;

-- Pending invitations, addressed by email so you can invite people who have
-- not signed up yet.
create table if not exists public.workspace_invites (
  id           uuid           primary key default uuid_generate_v4(),
  workspace_id uuid           not null references public.workspaces(id) on delete cascade,
  email        text           not null,
  role         workspace_role not null default 'member',
  invited_by   uuid           not null references auth.users(id) on delete cascade,
  accepted_at  timestamptz,
  created_at   timestamptz    not null default now(),
  unique (workspace_id, email)
);

-- Set when the invited person turns the invitation down. Declining cannot
-- delete the row: the delete policy requires workspace membership, which the
-- invited person does not have yet. Marking it instead lets them act on their
-- own invitation through the update policy.
alter table public.workspace_invites
  add column if not exists declined_at timestamptz;

create index if not exists workspace_invites_email_idx
  on public.workspace_invites(lower(email));

-- ---------------------------------------------------------------------------
-- Boards, groups, tasks
-- ---------------------------------------------------------------------------
create table if not exists public.boards (
  id           uuid        primary key default uuid_generate_v4(),
  workspace_id uuid        not null references public.workspaces(id) on delete cascade,
  name         text        not null,
  color        bigint      not null,
  position     int         not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists boards_workspace_idx on public.boards(workspace_id);

create table if not exists public.task_groups (
  id         uuid        primary key default uuid_generate_v4(),
  board_id   uuid        not null references public.boards(id) on delete cascade,
  name       text        not null,
  color      bigint      not null,
  position   int         not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists task_groups_board_idx on public.task_groups(board_id);

create table if not exists public.tasks (
  id          uuid        primary key default uuid_generate_v4(),
  group_id    uuid        not null references public.task_groups(id) on delete cascade,
  title       text        not null,
  owner       text        not null default '',
  assignee_id uuid        references auth.users(id) on delete set null,
  status      text        not null default 'notStarted',
  priority    text        not null default 'medium',
  -- Real dates, not display strings: sorting and overdue checks depend on it.
  due_date    date,
  start_date  date,
  end_date    date,
  progress    real        not null default 0,
  position    int         not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists tasks_group_idx on public.tasks(group_id);
create index if not exists tasks_assignee_idx on public.tasks(assignee_id);

-- ---------------------------------------------------------------------------
-- Custom columns
--
-- Boards define their own columns beyond the built-ins, monday-style. The
-- column declares its type and settings (e.g. the labels of a status column);
-- values live per task in task_column_values.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'column_kind') then
    create type column_kind as enum (
      'text', 'number', 'status', 'people', 'date', 'timeline',
      'checkbox', 'rating', 'dropdown', 'link', 'formula'
    );
  end if;
end
$$;

create table if not exists public.board_columns (
  id         uuid        primary key default uuid_generate_v4(),
  board_id   uuid        not null references public.boards(id) on delete cascade,
  name       text        not null,
  kind       column_kind not null default 'text',
  -- Per-kind config: status labels + colors, number format, formula body, …
  settings   jsonb       not null default '{}'::jsonb,
  position   int         not null default 0,
  width      int         not null default 160,
  created_at timestamptz not null default now()
);

create index if not exists board_columns_board_idx
  on public.board_columns(board_id, position);

create table if not exists public.task_column_values (
  task_id    uuid        not null references public.tasks(id) on delete cascade,
  column_id  uuid        not null references public.board_columns(id) on delete cascade,
  -- Shape depends on the column kind; jsonb keeps one row shape for all types.
  value      jsonb       not null default 'null'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid        references auth.users(id) on delete set null,
  primary key (task_id, column_id)
);

create index if not exists task_column_values_column_idx
  on public.task_column_values(column_id);

-- ---------------------------------------------------------------------------
-- Saved views: Table / Kanban / Timeline / Gantt / Calendar per board, each
-- with its own filters, sort and grouping.
-- ---------------------------------------------------------------------------
create table if not exists public.board_views (
  id         uuid        primary key default uuid_generate_v4(),
  board_id   uuid        not null references public.boards(id) on delete cascade,
  name       text        not null,
  kind       text        not null default 'table',
  config     jsonb       not null default '{}'::jsonb,
  position   int         not null default 0,
  created_by uuid        references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists board_views_board_idx
  on public.board_views(board_id, position);

-- Activity feed: who changed what, the backbone of monday-style updates.
create table if not exists public.task_activity (
  id         uuid        primary key default uuid_generate_v4(),
  task_id    uuid        not null references public.tasks(id) on delete cascade,
  user_id    uuid        references auth.users(id) on delete set null,
  kind       text        not null,
  detail     text        not null default '',
  created_at timestamptz not null default now()
);

create index if not exists task_activity_task_idx
  on public.task_activity(task_id, created_at desc);

-- Threaded comments on a task.
create table if not exists public.task_comments (
  id         uuid        primary key default uuid_generate_v4(),
  task_id    uuid        not null references public.tasks(id) on delete cascade,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  body       text        not null,
  created_at timestamptz not null default now()
);

create index if not exists task_comments_task_idx
  on public.task_comments(task_id, created_at);

-- ---------------------------------------------------------------------------
-- Task notes
--
-- A first-class row per note rather than a JSON blob on the task, so every note
-- carries its author and timestamps and teammates can see who wrote what.
-- ---------------------------------------------------------------------------
create table if not exists public.task_notes (
  id         uuid        primary key default uuid_generate_v4(),
  task_id    uuid        not null references public.tasks(id) on delete cascade,
  -- Quill Delta JSON.
  body       text        not null default '',
  color      bigint      not null default 4294962352,
  pinned     boolean     not null default false,
  position   int         not null default 0,
  author_id  uuid        references auth.users(id) on delete set null,
  edited_by  uuid        references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_notes_task_idx
  on public.task_notes(task_id, position);

-- Same reason as workspace_members: the note query embeds the author's and
-- editor's profile, which PostgREST can only resolve through a foreign key into
-- public.profiles. The constraint names are the ones the client's select
-- references explicitly, since two columns point at the same table.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'task_notes_author_id_fkey'
  ) then
    alter table public.task_notes
      add constraint task_notes_author_id_fkey
      foreign key (author_id) references public.profiles(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'task_notes_edited_by_fkey'
  ) then
    alter table public.task_notes
      add constraint task_notes_edited_by_fkey
      foreign key (edited_by) references public.profiles(id) on delete set null;
  end if;
end
$$;

-- Reactions let a team acknowledge a note without adding noise.
create table if not exists public.task_note_reactions (
  note_id    uuid        not null references public.task_notes(id) on delete cascade,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  emoji      text        not null,
  created_at timestamptz not null default now(),
  primary key (note_id, user_id, emoji)
);

-- ---------------------------------------------------------------------------
-- Membership helper
--
-- SECURITY DEFINER so the function itself can read workspace_members without
-- re-triggering that table's RLS policy. Without this, a policy on
-- workspace_members that queries workspace_members recurses infinitely.
-- ---------------------------------------------------------------------------
create or replace function public.is_workspace_member(target_workspace uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace
      and user_id = auth.uid()
  );
$$;

create or replace function public.can_edit_workspace(target_workspace uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace
      and user_id = auth.uid()
      and role in ('owner', 'admin', 'member')
  );
$$;

-- Workspace that owns a board / group / task, for nested policies.
create or replace function public.board_workspace(target_board uuid)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select workspace_id from public.boards where id = target_board;
$$;

create or replace function public.group_workspace(target_group uuid)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select b.workspace_id
  from public.task_groups g
  join public.boards b on b.id = g.board_id
  where g.id = target_group;
$$;

create or replace function public.task_workspace(target_task uuid)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select b.workspace_id
  from public.tasks t
  join public.task_groups g on g.id = t.group_id
  join public.boards b on b.id = g.board_id
  where t.id = target_task;
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.workspaces        enable row level security;
alter table public.workspace_members enable row level security;
alter table public.workspace_invites enable row level security;
alter table public.boards            enable row level security;
alter table public.task_groups       enable row level security;
alter table public.tasks             enable row level security;
alter table public.task_activity     enable row level security;
alter table public.task_comments     enable row level security;
alter table public.task_notes        enable row level security;
alter table public.task_note_reactions enable row level security;
alter table public.board_columns     enable row level security;
alter table public.task_column_values enable row level security;
alter table public.board_views       enable row level security;

-- Profiles: readable by anyone signed in (needed to show teammate names),
-- writable only by the owner.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Workspaces
drop policy if exists workspaces_select on public.workspaces;
create policy workspaces_select on public.workspaces
  for select to authenticated using (public.is_workspace_member(id));

drop policy if exists workspaces_insert on public.workspaces;
create policy workspaces_insert on public.workspaces
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists workspaces_update on public.workspaces;
create policy workspaces_update on public.workspaces
  for update to authenticated using (owner_id = auth.uid());

drop policy if exists workspaces_delete on public.workspaces;
create policy workspaces_delete on public.workspaces
  for delete to authenticated using (owner_id = auth.uid());

-- Members: visible to fellow members; only the workspace owner manages them.
drop policy if exists members_select on public.workspace_members;
create policy members_select on public.workspace_members
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists members_insert on public.workspace_members;
create policy members_insert on public.workspace_members
  for insert to authenticated with check (
    -- The creator joining their own new workspace, or an owner adding someone.
    user_id = auth.uid()
    or exists (
      select 1 from public.workspaces w
      where w.id = workspace_id and w.owner_id = auth.uid()
    )
  );

drop policy if exists members_delete on public.workspace_members;
create policy members_delete on public.workspace_members
  for delete to authenticated using (
    user_id = auth.uid()  -- leave a workspace
    or exists (
      select 1 from public.workspaces w
      where w.id = workspace_id and w.owner_id = auth.uid()
    )
  );

-- Invites: members see them; owners/admins create them; the invited person can
-- see and accept their own by email.
drop policy if exists invites_select on public.workspace_invites;
create policy invites_select on public.workspace_invites
  for select to authenticated using (
    public.is_workspace_member(workspace_id)
    or lower(email) = lower(auth.jwt()->>'email')
  );

drop policy if exists invites_insert on public.workspace_invites;
create policy invites_insert on public.workspace_invites
  for insert to authenticated with check (
    public.can_edit_workspace(workspace_id) and invited_by = auth.uid()
  );

drop policy if exists invites_update on public.workspace_invites;
create policy invites_update on public.workspace_invites
  for update to authenticated using (
    lower(email) = lower(auth.jwt()->>'email')
    or public.can_edit_workspace(workspace_id)
  );

drop policy if exists invites_delete on public.workspace_invites;
create policy invites_delete on public.workspace_invites
  for delete to authenticated using (public.can_edit_workspace(workspace_id));

-- Boards
drop policy if exists boards_select on public.boards;
create policy boards_select on public.boards
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists boards_write on public.boards;
create policy boards_write on public.boards
  for all to authenticated
  using (public.can_edit_workspace(workspace_id))
  with check (public.can_edit_workspace(workspace_id));

-- Groups
drop policy if exists groups_select on public.task_groups;
create policy groups_select on public.task_groups
  for select to authenticated
  using (public.is_workspace_member(public.board_workspace(board_id)));

drop policy if exists groups_write on public.task_groups;
create policy groups_write on public.task_groups
  for all to authenticated
  using (public.can_edit_workspace(public.board_workspace(board_id)))
  with check (public.can_edit_workspace(public.board_workspace(board_id)));

-- Tasks
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks
  for select to authenticated
  using (public.is_workspace_member(public.group_workspace(group_id)));

drop policy if exists tasks_write on public.tasks;
create policy tasks_write on public.tasks
  for all to authenticated
  using (public.can_edit_workspace(public.group_workspace(group_id)))
  with check (public.can_edit_workspace(public.group_workspace(group_id)));

-- Activity
drop policy if exists activity_select on public.task_activity;
create policy activity_select on public.task_activity
  for select to authenticated
  using (public.is_workspace_member(public.task_workspace(task_id)));

drop policy if exists activity_insert on public.task_activity;
create policy activity_insert on public.task_activity
  for insert to authenticated
  with check (public.can_edit_workspace(public.task_workspace(task_id)));

-- Comments
drop policy if exists comments_select on public.task_comments;
create policy comments_select on public.task_comments
  for select to authenticated
  using (public.is_workspace_member(public.task_workspace(task_id)));

drop policy if exists comments_insert on public.task_comments;
create policy comments_insert on public.task_comments
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.can_edit_workspace(public.task_workspace(task_id))
  );

drop policy if exists comments_delete on public.task_comments;
create policy comments_delete on public.task_comments
  for delete to authenticated using (user_id = auth.uid());

-- Board columns and saved views follow their board's access.
drop policy if exists board_columns_select on public.board_columns;
create policy board_columns_select on public.board_columns
  for select to authenticated
  using (public.is_workspace_member(public.board_workspace(board_id)));

drop policy if exists board_columns_write on public.board_columns;
create policy board_columns_write on public.board_columns
  for all to authenticated
  using (public.can_edit_workspace(public.board_workspace(board_id)))
  with check (public.can_edit_workspace(public.board_workspace(board_id)));

drop policy if exists board_views_select on public.board_views;
create policy board_views_select on public.board_views
  for select to authenticated
  using (public.is_workspace_member(public.board_workspace(board_id)));

drop policy if exists board_views_write on public.board_views;
create policy board_views_write on public.board_views
  for all to authenticated
  using (public.can_edit_workspace(public.board_workspace(board_id)))
  with check (public.can_edit_workspace(public.board_workspace(board_id)));

drop policy if exists column_values_select on public.task_column_values;
create policy column_values_select on public.task_column_values
  for select to authenticated
  using (public.is_workspace_member(public.task_workspace(task_id)));

drop policy if exists column_values_write on public.task_column_values;
create policy column_values_write on public.task_column_values
  for all to authenticated
  using (public.can_edit_workspace(public.task_workspace(task_id)))
  with check (public.can_edit_workspace(public.task_workspace(task_id)));

-- Task notes: every workspace member sees the whole thread.
drop policy if exists task_notes_select on public.task_notes;
create policy task_notes_select on public.task_notes
  for select to authenticated
  using (public.is_workspace_member(public.task_workspace(task_id)));

drop policy if exists task_notes_insert on public.task_notes;
create policy task_notes_insert on public.task_notes
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.can_edit_workspace(public.task_workspace(task_id))
  );

-- Any editor can amend a shared note; the trigger records who last touched it.
drop policy if exists task_notes_update on public.task_notes;
create policy task_notes_update on public.task_notes
  for update to authenticated
  using (public.can_edit_workspace(public.task_workspace(task_id)))
  with check (public.can_edit_workspace(public.task_workspace(task_id)));

-- Deleting is limited to the author or a workspace owner/admin.
drop policy if exists task_notes_delete on public.task_notes;
create policy task_notes_delete on public.task_notes
  for delete to authenticated
  using (
    author_id = auth.uid()
    or exists (
      select 1 from public.workspace_members m
      where m.workspace_id = public.task_workspace(task_id)
        and m.user_id = auth.uid()
        and m.role in ('owner', 'admin')
    )
  );

-- Reactions
drop policy if exists note_reactions_select on public.task_note_reactions;
create policy note_reactions_select on public.task_note_reactions
  for select to authenticated
  using (
    exists (
      select 1 from public.task_notes n
      where n.id = note_id
        and public.is_workspace_member(public.task_workspace(n.task_id))
    )
  );

drop policy if exists note_reactions_write on public.task_note_reactions;
create policy note_reactions_write on public.task_note_reactions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Creating a workspace should also enrol the creator as its owner.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.workspace_members (workspace_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_workspace_created on public.workspaces;
create trigger on_workspace_created
  after insert on public.workspaces
  for each row execute function public.handle_new_workspace();

-- Repair: enrol owners of any workspace created before the trigger existed.
-- Without a membership row the owner cannot read or write their own workspace,
-- which surfaces as "0 members" and a permission error.
insert into public.workspace_members (workspace_id, user_id, role)
select w.id, w.owner_id, 'owner'
from public.workspaces w
where not exists (
  select 1 from public.workspace_members m
  where m.workspace_id = w.id and m.user_id = w.owner_id
)
on conflict do nothing;

-- Claims any invitations matching the caller's email, turning them into
-- memberships. Called by the client right after sign-in.
create or replace function public.accept_pending_invites()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed int;
begin
  with pending as (
    select id, workspace_id, role
    from public.workspace_invites
    where lower(email) = lower(auth.jwt()->>'email')
      and accepted_at is null
      and declined_at is null
  ), inserted as (
    insert into public.workspace_members (workspace_id, user_id, role)
    select workspace_id, auth.uid(), role from pending
    on conflict (workspace_id, user_id) do nothing
    returning workspace_id
  )
  update public.workspace_invites
  set accepted_at = now()
  where id in (select id from pending);

  get diagnostics claimed = row_count;
  return claimed;
end;
$$;

-- Redeems a join code, adding the caller to that workspace as a member.
--
-- SECURITY DEFINER by necessity: someone who is not yet a member cannot select
-- the workspace to look its code up, so the lookup has to bypass RLS. It only
-- ever adds the *calling* user, and only with the 'member' role, so it cannot
-- be used to grant anyone else access or to escalate a role.
create or replace function public.join_workspace_with_code(code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  target        public.workspaces%rowtype;
  normalized    text;
  already       boolean;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'not_signed_in');
  end if;

  -- Accept sloppy input: lower case, stray spaces, and a missing prefix.
  normalized := upper(regexp_replace(coalesce(code, ''), '\s', '', 'g'));
  if normalized <> '' and position('PLNR-' in normalized) = 0 then
    normalized := 'PLNR-' || normalized;
  end if;

  select * into target
  from public.workspaces
  where join_code = normalized;

  if not found then
    return json_build_object('ok', false, 'error', 'not_found');
  end if;

  select exists (
    select 1 from public.workspace_members
    where workspace_id = target.id and user_id = auth.uid()
  ) into already;

  if already then
    return json_build_object(
      'ok', false, 'error', 'already_member', 'name', target.name
    );
  end if;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (target.id, auth.uid(), 'member')
  on conflict do nothing;

  return json_build_object('ok', true, 'name', target.name);
end;
$$;

-- Rotates the code, for when one has been shared too widely. Restricted to
-- owners and admins by the membership check inside.
create or replace function public.regenerate_join_code(target_workspace uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  fresh text;
begin
  if not exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace
      and user_id = auth.uid()
      and role in ('owner', 'admin')
  ) then
    raise exception 'Only owners and admins can change the join code.';
  end if;

  loop
    fresh := public.generate_join_code();
    exit when not exists (
      select 1 from public.workspaces where join_code = fresh
    );
  end loop;

  update public.workspaces set join_code = fresh where id = target_workspace;
  return fresh;
end;
$$;

-- Keep tasks.updated_at honest.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists tasks_touch_updated_at on public.tasks;
create trigger tasks_touch_updated_at
  before update on public.tasks
  for each row execute function public.touch_updated_at();

-- Notes also record who last edited them, so the UI can show "edited by X".
create or replace function public.touch_note_updated()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  new.edited_by = auth.uid();
  return new;
end;
$$;

drop trigger if exists task_notes_touch_updated_at on public.task_notes;
create trigger task_notes_touch_updated_at
  before update on public.task_notes
  for each row execute function public.touch_note_updated();

-- ---------------------------------------------------------------------------
-- Realtime
--
-- Publishing these tables lets the app subscribe to changes so a teammate's
-- edit appears without a refresh.
-- ---------------------------------------------------------------------------
-- Create the publication if this project does not have it yet, then add each
-- table individually. Adding them in one statement means a single
-- already-published table aborts the rest, which previously left realtime
-- silently half-configured.
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach t in array array[
    'tasks', 'task_notes', 'task_groups', 'boards',
    'task_comments', 'task_note_reactions', 'workspace_invites'
  ]
  loop
    begin
      execute format(
        'alter publication supabase_realtime add table public.%I', t
      );
    exception
      when duplicate_object then null;  -- already published
    end;
  end loop;
end
$$;

-- Realtime only delivers the changed row's contents when the table records a
-- full "before" image; without this an UPDATE arrives with just the primary
-- key, which is not enough to refresh a row in place.
alter table public.tasks               replica identity full;
alter table public.task_notes          replica identity full;
alter table public.task_groups         replica identity full;
alter table public.boards              replica identity full;
alter table public.task_comments       replica identity full;
alter table public.task_note_reactions replica identity full;
alter table public.workspace_invites   replica identity full;
