-- 0002 — Core tables
--
-- Shape and rationale are in ../DESIGN.md. In short:
--   workspace -> board -> group -> task, each a foreign key into the one above
--   every table carries workspace_id so RLS reads it without a join
--   every user reference points at public.profiles, never auth.users directly
--
-- Run after 0001.

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Enums
--
-- An enum where the set is fixed and the app has matching code paths; a table
-- where a team should be able to add their own (see board_status_labels).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'workspace_role' and n.nspname = 'public'
  ) then
    create type public.workspace_role as enum ('owner', 'admin', 'member', 'viewer');
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'task_priority' and n.nspname = 'public'
  ) then
    create type public.task_priority as enum ('urgent', 'high', 'medium', 'low');
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'column_kind' and n.nspname = 'public'
  ) then
    create type public.column_kind as enum (
      'text', 'long_text', 'number', 'status', 'people', 'date', 'timeline',
      'checkbox', 'rating', 'dropdown', 'link', 'email', 'phone', 'formula'
    );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'view_kind' and n.nspname = 'public'
  ) then
    create type public.view_kind as enum (
      'table', 'kanban', 'calendar', 'timeline', 'gantt', 'chart'
    );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'activity_kind' and n.nspname = 'public'
  ) then
    create type public.activity_kind as enum (
      'created', 'renamed', 'status_changed', 'priority_changed', 'assigned',
      'unassigned', 'due_date_changed', 'moved', 'progress_changed',
      'note_added', 'comment_added', 'deleted', 'restored'
    );
  end if;
end
$$;

-- What a notification is telling you. Distinct from activity_kind: activity is
-- the audit trail of what happened to a task, notifications are what a specific
-- person needs to know about.
do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'notification_kind' and n.nspname = 'public'
  ) then
    create type public.notification_kind as enum (
      'workspace_invite',      -- you were invited to a workspace
      'invite_accepted',       -- someone you invited joined
      'member_joined',         -- someone joined via the code
      'role_changed',          -- your role changed
      'removed_from_workspace',
      'task_assigned',         -- a task was assigned to you
      'task_unassigned',
      'task_due_soon',         -- a task of yours is due within 24h
      'task_overdue',
      'task_status_changed',   -- a task you are on moved
      'note_added',            -- someone posted on a task you are on
      'comment_added',
      'mentioned'              -- @you in a note or comment
    );
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Profiles — public user data, mirrored from auth.users
--
-- Everything that references a person points here rather than at auth.users:
-- PostgREST cannot embed across into the auth schema, so `profiles(...)` in a
-- select only resolves when the foreign key targets this table.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text        not null,
  full_name  text        not null default '',
  avatar_url text        not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_full_name_length check (char_length(full_name) <= 60)
);

-- ---------------------------------------------------------------------------
-- Workspaces
-- ---------------------------------------------------------------------------
create table if not exists public.workspaces (
  id         uuid primary key default uuid_generate_v4(),
  name       text        not null,
  color      bigint      not null default 4280514815,
  owner_id   uuid        not null references public.profiles(id) on delete cascade,
  -- Short shareable code (PLNR-7K2M) so someone can join without the owner
  -- knowing their email first. Assigned by trigger; never null in practice.
  join_code  text        unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint workspaces_name_length check (char_length(trim(name)) between 1 and 60)
);

create index if not exists workspaces_owner_idx on public.workspaces(owner_id);

create table if not exists public.workspace_members (
  workspace_id uuid                  not null references public.workspaces(id) on delete cascade,
  user_id      uuid                  not null references public.profiles(id)   on delete cascade,
  role         public.workspace_role not null default 'member',
  created_at   timestamptz           not null default now(),

  primary key (workspace_id, user_id)
);

-- The PK covers workspace-first lookups; this covers "which workspaces am I
-- in", which is the query behind every sign-in.
create index if not exists workspace_members_user_idx on public.workspace_members(user_id);

-- Invitations, addressed two ways.
--
-- `invitee_id` is the real relationship and is set whenever the person already
-- has an account — the invite dialog searches profiles, so this is the normal
-- case. It cannot be the only route, though: inviting someone who has not
-- signed up yet means there is no profile row to point at. `email` covers that,
-- and accept_pending_invites() claims it once they sign up.
--
-- Exactly one of the two identifies the invitee, and the check below requires
-- at least one to be present.
create table if not exists public.workspace_invites (
  id           uuid                  primary key default uuid_generate_v4(),
  workspace_id uuid                  not null references public.workspaces(id) on delete cascade,
  invitee_id   uuid                  references public.profiles(id) on delete cascade,
  email        text,
  role         public.workspace_role not null default 'member',
  invited_by   uuid                  references public.profiles(id) on delete set null,
  accepted_at  timestamptz,
  -- Declining cannot delete the row: the delete policy requires membership,
  -- which the invited person does not have yet. Marking it lets them act on
  -- their own invitation through the update policy instead.
  declined_at  timestamptz,
  created_at   timestamptz           not null default now(),

  constraint workspace_invites_has_target
    check (invitee_id is not null or email is not null),
  constraint workspace_invites_company_email
    check (
      email is null
      or lower(split_part(trim(email), '@', 2)) = 'vintazk.com'
    )
);

-- Two partial unique indexes rather than one constraint over both columns: a
-- plain UNIQUE treats NULLs as distinct, so it would let the same person be
-- invited to the same workspace repeatedly.
create unique index if not exists workspace_invites_user_idx
  on public.workspace_invites(workspace_id, invitee_id)
  where invitee_id is not null;

create unique index if not exists workspace_invites_email_unique_idx
  on public.workspace_invites(workspace_id, lower(email))
  where invitee_id is null and email is not null;

create index if not exists workspace_invites_email_idx
  on public.workspace_invites(lower(email))
  where email is not null;

create index if not exists workspace_invites_invitee_idx
  on public.workspace_invites(invitee_id)
  where invitee_id is not null;

-- Failed attempts to redeem a join code.
--
-- Without this the code's length is the only thing standing between a guesser
-- and a workspace, and a script does not mind guessing slowly.
-- join_workspace_with_code() refuses after ten failures in an hour, and a
-- success clears the row.
create table if not exists public.join_attempts (
  id           bigserial   primary key,
  user_id      uuid        not null references public.profiles(id) on delete cascade,
  succeeded    boolean     not null default false,
  attempted_at timestamptz not null default now()
);

-- The limiter counts recent failures per person, which is exactly this.
create index if not exists join_attempts_recent_idx
  on public.join_attempts(user_id, attempted_at desc)
  where succeeded = false;

-- ---------------------------------------------------------------------------
-- Boards
-- ---------------------------------------------------------------------------
create table if not exists public.boards (
  id           uuid        primary key default uuid_generate_v4(),
  workspace_id uuid        not null references public.workspaces(id) on delete cascade,
  name         text        not null,
  description  text        not null default '',
  color        bigint      not null default 4280514815,
  position     numeric     not null default 0,
  -- Pinned boards sort above the rest in the sidebar. Per workspace, not per
  -- person: a small team's "the board we all live in" is the same board for
  -- everyone, and a per-user table would cost a join on every sidebar render
  -- to express something nobody asked to differ.
  pinned       boolean     not null default false,
  -- Soft delete. RLS hides non-null rows from normal reads; restore_board()
  -- clears it and purge_deleted() hard-deletes after 30 days.
  deleted_at   timestamptz,
  created_by   uuid        references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint boards_name_length check (char_length(trim(name)) between 1 and 80)
);

-- Partial: the deleted rows are a small minority and never appear in the
-- listing this index serves.
-- Pinned first, then by position — the order the sidebar draws them in.
create index if not exists boards_workspace_idx
  on public.boards(workspace_id, pinned desc, position)
  where deleted_at is null;

create index if not exists boards_deleted_idx
  on public.boards(deleted_at)
  where deleted_at is not null;

-- Status labels a board defines for its tasks.
--
-- A table rather than an enum because each board names its own — this is what
-- makes "Working" renameable to "In progress" without rewriting every task.
create table if not exists public.board_status_labels (
  id         uuid        primary key default uuid_generate_v4(),
  board_id   uuid        not null references public.boards(id) on delete cascade,
  name       text        not null,
  color      bigint      not null default 4288387995,
  position   numeric     not null default 0,
  -- Which labels count as complete. Progress rollups test this flag rather
  -- than comparing against the string 'Done'.
  is_done    boolean     not null default false,
  -- The label new tasks get. A partial unique index below allows exactly one
  -- per board.
  is_default boolean     not null default false,
  created_at timestamptz not null default now(),

  unique (board_id, name),
  constraint board_status_labels_name_length
    check (char_length(trim(name)) between 1 and 40)
);

create index if not exists board_status_labels_board_idx
  on public.board_status_labels(board_id, position);

create unique index if not exists board_status_labels_one_default_idx
  on public.board_status_labels(board_id)
  where is_default;

-- Columns a board defines beyond the built-ins, monday-style. The column
-- declares its type and settings; values live per task in task_column_values.
create table if not exists public.board_columns (
  id           uuid              primary key default uuid_generate_v4(),
  board_id     uuid              not null references public.boards(id) on delete cascade,
  workspace_id uuid              not null references public.workspaces(id) on delete cascade,
  name         text              not null,
  kind         public.column_kind not null default 'text',
  -- Per-kind config: dropdown choices, number format, formula body, …
  settings     jsonb             not null default '{}'::jsonb,
  position     numeric           not null default 0,
  width        int               not null default 160,
  created_at   timestamptz       not null default now(),
  updated_at   timestamptz       not null default now(),

  unique (board_id, name),
  constraint board_columns_width_range check (width between 60 and 900)
);

create index if not exists board_columns_board_idx on public.board_columns(board_id, position);

-- Saved views: Table / Kanban / Calendar / Timeline per board, each with its
-- own filters, sort and grouping in `config`.
create table if not exists public.board_views (
  id           uuid            primary key default uuid_generate_v4(),
  board_id     uuid            not null references public.boards(id) on delete cascade,
  workspace_id uuid            not null references public.workspaces(id) on delete cascade,
  name         text            not null,
  kind         public.view_kind not null default 'table',
  config       jsonb           not null default '{}'::jsonb,
  position     numeric         not null default 0,
  -- Personal views are visible only to their creator; shared ones to the
  -- whole workspace. Enforced by the select policy.
  is_shared    boolean         not null default true,
  created_by   uuid            references public.profiles(id) on delete set null,
  created_at   timestamptz     not null default now(),
  updated_at   timestamptz     not null default now(),

  constraint board_views_name_length check (char_length(trim(name)) between 1 and 60)
);

create index if not exists board_views_board_idx on public.board_views(board_id, position);

-- ---------------------------------------------------------------------------
-- Groups and tasks
-- ---------------------------------------------------------------------------
create table if not exists public.task_groups (
  id           uuid        primary key default uuid_generate_v4(),
  board_id     uuid        not null references public.boards(id) on delete cascade,
  workspace_id uuid        not null references public.workspaces(id) on delete cascade,
  name         text        not null,
  color        bigint      not null default 4280514815,
  position     numeric     not null default 0,
  collapsed    boolean     not null default false,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint task_groups_name_length check (char_length(trim(name)) between 1 and 80)
);

create index if not exists task_groups_board_idx
  on public.task_groups(board_id, position)
  where deleted_at is null;

create table if not exists public.tasks (
  id           uuid        primary key default uuid_generate_v4(),
  group_id     uuid        not null references public.task_groups(id) on delete cascade,
  board_id     uuid        not null references public.boards(id) on delete cascade,
  workspace_id uuid        not null references public.workspaces(id) on delete cascade,
  title        text        not null,

  -- Foreign key, not free text: the database rejects a status that does not
  -- belong to this board. A trigger enforces that it belongs to *this* board
  -- specifically, which a plain FK cannot express.
  status_id    uuid        references public.board_status_labels(id) on delete set null,
  priority     public.task_priority not null default 'medium',

  -- Real dates, not display strings: sorting and overdue checks depend on it.
  due_date     date,
  start_date   date,
  end_date     date,
  progress     real        not null default 0,
  -- When the bar last moved, which is not the same as updated_at.
  --
  -- The stale sweep asks "has this task progressed in three days", and
  -- updated_at answers a different question — renaming a task or changing its
  -- due date would reset it, so a genuinely stalled task could look active
  -- forever. Maintained by trigger, and only when progress actually changes.
  progress_at  timestamptz not null default now(),
  position     numeric     not null default 0,

  -- Maintained by trigger so the badge costs no query. Denormalized count,
  -- not denormalized data — it cannot drift into disagreeing with itself.
  comment_count int        not null default 0,

  deleted_at   timestamptz,
  created_by   uuid        references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint tasks_title_length check (char_length(trim(title)) between 1 and 200),
  constraint tasks_progress_range check (progress between 0 and 1),
  constraint tasks_comment_count_positive check (comment_count >= 0),
  -- A timeline that ends before it starts is a data entry error, not a state
  -- worth storing.
  constraint tasks_timeline_order check (
    start_date is null or end_date is null or start_date <= end_date
  )
);

create index if not exists tasks_group_idx
  on public.tasks(group_id, position)
  where deleted_at is null;

create index if not exists tasks_board_idx
  on public.tasks(board_id)
  where deleted_at is null;

create index if not exists tasks_workspace_idx
  on public.tasks(workspace_id)
  where deleted_at is null;

-- Serves the calendar and "what is overdue" queries.
create index if not exists tasks_due_date_idx
  on public.tasks(workspace_id, due_date)
  where deleted_at is null and due_date is not null;

create index if not exists tasks_status_idx on public.tasks(status_id);

-- Serves the stale sweep, which scans for tasks whose progress has not moved.
create index if not exists tasks_stale_idx
  on public.tasks(workspace_id, progress_at)
  where deleted_at is null;

-- Many people per task. `tasks.assignee_id` allowed exactly one, and
-- `tasks.owner` stored a copy of their display name that went stale the moment
-- they renamed themselves. Both are gone; this is the relationship.
create table if not exists public.task_assignees (
  task_id      uuid        not null references public.tasks(id)      on delete cascade,
  user_id      uuid        not null references public.profiles(id)   on delete cascade,
  workspace_id uuid        not null references public.workspaces(id) on delete cascade,
  assigned_by  uuid        references public.profiles(id) on delete set null,
  assigned_at  timestamptz not null default now(),

  primary key (task_id, user_id)
);

create index if not exists task_assignees_user_idx on public.task_assignees(user_id, workspace_id);

-- Values for the board's custom columns. jsonb keeps one row shape across all
-- column kinds; the shape of `value` is the column's business.
create table if not exists public.task_column_values (
  task_id      uuid        not null references public.tasks(id)          on delete cascade,
  column_id    uuid        not null references public.board_columns(id)  on delete cascade,
  workspace_id uuid        not null references public.workspaces(id)     on delete cascade,
  value        jsonb       not null default 'null'::jsonb,
  updated_by   uuid        references public.profiles(id) on delete set null,
  updated_at   timestamptz not null default now(),

  primary key (task_id, column_id)
);

create index if not exists task_column_values_column_idx on public.task_column_values(column_id);

-- ---------------------------------------------------------------------------
-- Task chat
--
-- One conversation per task, replacing the sticky-note model that came before.
-- Notes were a wall of coloured cards with positions and pinning; in practice
-- teams wrote messages to each other on them, so this is the shape the use
-- already had.
-- ---------------------------------------------------------------------------
create table if not exists public.task_comments (
  id           uuid        primary key default uuid_generate_v4(),
  task_id      uuid        not null references public.tasks(id)       on delete cascade,
  workspace_id uuid        not null references public.workspaces(id)  on delete cascade,
  -- One level of threading. A reply to a reply attaches to the same parent, so
  -- a thread stays two deep and readable rather than marching off the right
  -- edge of the panel.
  parent_id    uuid        references public.task_comments(id) on delete cascade,
  author_id    uuid        not null references public.profiles(id)    on delete cascade,
  body         text        not null,
  -- Set when the author changes the text, so the UI can mark it edited. Null
  -- means never touched, which is not the same as "edited zero seconds after
  -- posting" — comparing timestamps could not tell those apart.
  edited_at    timestamptz,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint task_comments_body_length check (char_length(trim(body)) between 1 and 5000)
);

create index if not exists task_comments_task_idx
  on public.task_comments(task_id, created_at)
  where deleted_at is null;

-- Replies are fetched per parent when a thread is expanded.
create index if not exists task_comments_parent_idx
  on public.task_comments(parent_id, created_at)
  where parent_id is not null and deleted_at is null;

-- Acknowledging a message without adding one.
create table if not exists public.task_comment_reactions (
  comment_id   uuid        not null references public.task_comments(id) on delete cascade,
  user_id      uuid        not null references public.profiles(id)      on delete cascade,
  workspace_id uuid        not null references public.workspaces(id)    on delete cascade,
  emoji        text        not null,
  created_at   timestamptz not null default now(),

  primary key (comment_id, user_id, emoji),
  constraint task_comment_reactions_emoji_length
    check (char_length(emoji) between 1 and 16)
);

-- Who was named in a message, so the mention survives an edit that removes it
-- and the notification can be traced back.
create table if not exists public.task_comment_mentions (
  comment_id   uuid        not null references public.task_comments(id) on delete cascade,
  user_id      uuid        not null references public.profiles(id)      on delete cascade,
  workspace_id uuid        not null references public.workspaces(id)    on delete cascade,
  created_at   timestamptz not null default now(),

  primary key (comment_id, user_id)
);

create index if not exists task_comment_mentions_user_idx
  on public.task_comment_mentions(user_id, created_at desc);

-- Who changed what. Append-only: no update or delete policy exists for it.
create table if not exists public.task_activity (
  id           uuid                 primary key default uuid_generate_v4(),
  task_id      uuid                 not null references public.tasks(id)      on delete cascade,
  workspace_id uuid                 not null references public.workspaces(id) on delete cascade,
  actor_id     uuid                 references public.profiles(id) on delete set null,
  kind         public.activity_kind not null,
  -- Structured rather than a sentence, so the client renders it in its own
  -- wording: {"from": "Working", "to": "Done"}.
  detail       jsonb                not null default '{}'::jsonb,
  created_at   timestamptz          not null default now()
);

create index if not exists task_activity_task_idx on public.task_activity(task_id, created_at desc);
create index if not exists task_activity_workspace_idx on public.task_activity(workspace_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Notifications
--
-- One row per person per thing they need to know about. A task assigned to
-- three people produces three rows, because each is read and dismissed
-- independently.
--
-- `workspace_id` is nullable: an invitation notification arrives *before* the
-- recipient is a member, so it cannot be gated on membership the way every
-- other table is. The RLS policy keys on user_id alone, which is stricter.
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id           uuid                    primary key default uuid_generate_v4(),
  user_id      uuid                    not null references public.profiles(id) on delete cascade,
  workspace_id uuid                    references public.workspaces(id) on delete cascade,
  kind         public.notification_kind not null,
  title        text                    not null,
  body         text                    not null default '',

  -- What it points at, so tapping it can open the right screen. Nullable and
  -- ON DELETE CASCADE: a notification about a deleted task should disappear
  -- with it rather than lead nowhere.
  task_id      uuid                    references public.tasks(id)  on delete cascade,
  board_id     uuid                    references public.boards(id) on delete cascade,
  invite_id    uuid                    references public.workspace_invites(id) on delete cascade,

  -- Who caused it. Null for anything the system raised on its own, like a due
  -- date passing.
  actor_id     uuid                    references public.profiles(id) on delete set null,
  read_at      timestamptz,
  created_at   timestamptz             not null default now()
);

-- The unread badge is the hottest query in the app; this serves it directly.
create index if not exists notifications_unread_idx
  on public.notifications(user_id, created_at desc)
  where read_at is null;

create index if not exists notifications_user_idx
  on public.notifications(user_id, created_at desc);

-- Due-date reminders come from a scheduled sweep, so the same task must not
-- notify the same person twice in a day.
--
-- The obvious index — unique on (user_id, task_id, kind, created_at::date) —
-- is rejected: casting timestamptz to date reads the session timezone, so
-- Postgres considers it non-immutable and will not index it. Storing a
-- generated date column would work but bloats every row for a rule that
-- applies to two of thirteen notification kinds.
--
-- sweep_due_tasks() checks for a recent identical reminder instead. This index
-- is what makes that check a lookup rather than a scan.
create index if not exists notifications_due_recent_idx
  on public.notifications(task_id, user_id, kind, created_at desc)
  where kind in ('task_due_soon', 'task_overdue');
