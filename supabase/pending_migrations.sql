-- Planner: migrations 0008 through 0015
-- Paste into the Supabase SQL editor and run, in this order.
-- All are safe to re-run.
--
-- 0013 creates a storage bucket for note attachments; 0015 removes it again.
-- Both touch storage.objects and need an owner role — the SQL editor
-- qualifies. On a database that has already run 0013, running 0015 alone is
-- enough.


-- ============================================================
-- 0008_chat_reads.sql
-- ============================================================
-- ---------------------------------------------------------------------------
-- 0008 — Chat read receipts
--
-- One row per person per task: when they last had the task's chat open.
-- The chat shows "Seen by …" under the newest message by comparing these
-- stamps against the message's created_at. A single stamp rather than
-- per-message rows, because "have they seen the latest?" is the only question
-- the UI asks — and it keeps the table from growing with every message.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

create table if not exists public.task_chat_reads (
  task_id      uuid not null references public.tasks(id)      on delete cascade,
  user_id      uuid not null references public.profiles(id)   on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (task_id, user_id)
);

alter table public.task_chat_reads enable row level security;

-- Anyone who can read the task can see who has read its chat.
drop policy if exists task_chat_reads_select on public.task_chat_reads;
create policy task_chat_reads_select on public.task_chat_reads
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

-- Writes go through mark_chat_read() below, which stamps auth.uid() itself —
-- these policies hold the same line for anyone hitting the table directly:
-- you may only record your own reading, and only where you belong.
drop policy if exists task_chat_reads_insert on public.task_chat_reads;
create policy task_chat_reads_insert on public.task_chat_reads
  for insert to authenticated
  with check (
    user_id = auth.uid() and public.is_workspace_member(workspace_id)
  );

drop policy if exists task_chat_reads_update on public.task_chat_reads;
create policy task_chat_reads_update on public.task_chat_reads
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid() and public.is_workspace_member(workspace_id)
  );

-- The one write path the app uses. SECURITY DEFINER so the workspace_id is
-- taken from the task row rather than trusted from the client; membership is
-- still checked, so reading a chat you cannot see records nothing.
create or replace function public.mark_chat_read(p_task uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.task_chat_reads (task_id, user_id, workspace_id)
  select t.id, auth.uid(), t.workspace_id
  from public.tasks t
  where t.id = p_task
    and t.deleted_at is null
    and public.is_workspace_member(t.workspace_id)
  on conflict (task_id, user_id) do update set last_read_at = now();
$$;

grant execute on function public.mark_chat_read(uuid) to authenticated;

-- Receipts are live: "Seen" appears the moment a teammate opens the chat.
do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.task_chat_reads';
  exception
    when duplicate_object then null;  -- already published
  end;
end
$$;

alter table public.task_chat_reads replica identity full;


-- ============================================================
-- 0009_single_board_tree.sql
-- ============================================================
-- ---------------------------------------------------------------------------
-- 0009 — Per-board tree, for workspaces with real traffic
--
-- board_tree(workspace) returns every board in the workspace with every group,
-- task and assignee inside it. That is the right shape on arrival, and the
-- wrong shape for a refresh: a teammate moving one task made every other
-- client re-fetch the entire workspace, so the cost of a single edit grew
-- with both the number of people watching and the amount of data they were
-- not looking at.
--
-- This adds the same query scoped to one board. The client refreshes only the
-- board a change actually touched and splices it into the list it already
-- holds, so the payload stops growing with the workspace.
--
-- board_tree() stays exactly as it was — the first load still wants the whole
-- workspace in one round trip.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

create or replace function public.board_tree_one(target_board uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  -- Returns the single board object, or null when the board is gone or the
  -- caller cannot see it. The client treats null as "drop it from the list",
  -- which is also what a delete should look like.
  select jsonb_build_object(
    'id',       b.id,
    'name',     b.name,
    'color',    b.color,
    'position', b.position,
    'pinned',   b.pinned,
    'statuses', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'color', s.color,
        'position', s.position, 'is_done', s.is_done, 'is_default', s.is_default
      ) order by s.position), '[]'::jsonb)
      from public.board_status_labels s where s.board_id = b.id
    ),
    'groups', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'board_id', g.board_id, 'name', g.name,
        'color', g.color, 'position', g.position, 'collapsed', g.collapsed,
        'tasks', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'id', t.id, 'group_id', t.group_id, 'board_id', t.board_id,
            'title', t.title, 'status_id', t.status_id,
            'priority', t.priority, 'due_date', t.due_date,
            'start_date', t.start_date, 'end_date', t.end_date,
            'progress', t.progress, 'progress_at', t.progress_at,
            'position', t.position,
            'comment_count', t.comment_count,
            'assignee_ids', (
              select coalesce(jsonb_agg(a.user_id), '[]'::jsonb)
              from public.task_assignees a where a.task_id = t.id
            )
          ) order by t.position), '[]'::jsonb)
          from public.tasks t
          where t.group_id = g.id and t.deleted_at is null
        )
      ) order by g.position), '[]'::jsonb)
      from public.task_groups g
      where g.board_id = b.id and g.deleted_at is null
    )
  )
  from public.boards b
  where b.id = target_board
    and b.deleted_at is null
    and public.is_workspace_member(b.workspace_id);
$$;

grant execute on function public.board_tree_one(uuid) to authenticated;

-- The refresh path filters tasks by group and groups by board on every call,
-- so both need an index that does not walk the whole table. Partial on
-- deleted_at because every one of these queries excludes soft-deleted rows.
create index if not exists tasks_group_live_idx
  on public.tasks(group_id, position)
  where deleted_at is null;

create index if not exists task_groups_board_live_idx
  on public.task_groups(board_id, position)
  where deleted_at is null;


-- ============================================================
-- 0010_reaction_task_id.sql
-- ============================================================
-- ---------------------------------------------------------------------------
-- 0010 — Scope reaction events to their task
--
-- task_comment_reactions carries comment_id, not task_id, so an open chat had
-- to subscribe to *every* reaction in the database and reload on each one.
-- At a handful of users that is invisible. At a hundred it means every thumbs
-- up anyone gives, anywhere, re-fetches every open conversation.
--
-- Denormalising task_id onto the row makes the subscription filterable
-- server-side, the same way task_comments already is. The trigger fills it in,
-- so nothing client-side has to be trusted to set it correctly.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

alter table public.task_comment_reactions
  add column if not exists task_id uuid references public.tasks(id) on delete cascade;

-- Backfill anything already there.
update public.task_comment_reactions r
set task_id = c.task_id
from public.task_comments c
where r.comment_id = c.id
  and r.task_id is distinct from c.task_id;

-- Filled from the comment rather than taken from the client: a reaction that
-- claimed the wrong task would deliver itself to the wrong subscribers.
create or replace function public.set_reaction_task_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select c.task_id into new.task_id
  from public.task_comments c
  where c.id = new.comment_id;
  return new;
end;
$$;

drop trigger if exists task_comment_reactions_task_id on public.task_comment_reactions;
create trigger task_comment_reactions_task_id
  before insert or update of comment_id on public.task_comment_reactions
  for each row execute function public.set_reaction_task_id();

-- The chat loads reactions for a set of comment ids; this serves that as well
-- as the realtime filter.
create index if not exists task_comment_reactions_task_idx
  on public.task_comment_reactions(task_id);


-- ============================================================
-- 0011_settle_invite_on_join.sql
-- ============================================================
-- 0011 — Joining settles the invitation
--
-- Run after 0010. Safe to re-run.
--
-- Someone could be invited and, instead of answering, join with the workspace
-- code. That inserted the membership and left the invitation exactly as it
-- was: still pending, still unanswered. So the admin's members dialog listed
-- them under "Pending invitations" while they were sitting in the members list
-- directly above it, and the invitee's own notification still read "X invited
-- you to …" for a workspace they were already working in.
--
-- Membership is the thing the invitation was asking about, so membership is
-- what settles it — regardless of which route was taken to get there. A
-- trigger on workspace_members covers every one of them: the code, the
-- invitation, and any future path, without each having to remember to tidy up
-- after itself.

-- ---------------------------------------------------------------------------
-- Settle on join
-- ---------------------------------------------------------------------------

create or replace function public.settle_invites_on_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Marked accepted rather than deleted: the row is the record that the
  -- invitation existed and how it ended, which the admin's list relies on.
  --
  -- The accepted_at update fires settle_invite_notification, so the stale
  -- "you have been invited" in the bell is rewritten to "You joined …" by the
  -- trigger that already owns that wording.
  update public.workspace_invites
  set accepted_at = now()
  where workspace_id = new.workspace_id
    and accepted_at is null
    and declined_at is null
    and (
      invitee_id = new.user_id
      or lower(email) = lower((
        select email from public.profiles where id = new.user_id
      ))
    );

  return new;
end;
$$;

drop trigger if exists workspace_members_settle_invites on public.workspace_members;
create trigger workspace_members_settle_invites
  after insert on public.workspace_members
  for each row execute function public.settle_invites_on_join();

-- ---------------------------------------------------------------------------
-- Backfill
--
-- Invitations already stranded by a join that happened before the trigger
-- existed. Without this the fix only helps future joins, and every workspace
-- carrying one of these keeps showing it.
-- ---------------------------------------------------------------------------

update public.workspace_invites i
set accepted_at = now()
where i.accepted_at is null
  and i.declined_at is null
  and exists (
    select 1
    from public.workspace_members m
    left join public.profiles p on p.id = m.user_id
    where m.workspace_id = i.workspace_id
      and (
        m.user_id = i.invitee_id
        or lower(p.email) = lower(i.email)
      )
  );


-- ============================================================
-- 0012_profile_name_cooldown.sql
-- ============================================================
-- 0012 — Changing your display name, at most once a week
--
-- Run after 0011. Safe to re-run.
--
-- A name is how teammates recognise each other across every board, comment and
-- mention in the workspace. Someone changing it hourly makes the history
-- unreadable — a comment from March is suddenly attributed to a name nobody
-- recognises — so a change is allowed and then rate limited.
--
-- Seven days, enforced here rather than in the client. The client also hides
-- the button while the cooldown runs, but that is a courtesy: the check that
-- decides is this one, because anyone can call the API directly.

-- ---------------------------------------------------------------------------
-- When the name last changed
--
-- Null means never changed since signup, which does not count against the
-- cooldown: the first change is always allowed.
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists name_changed_at timestamptz;

-- ---------------------------------------------------------------------------
-- The cooldown itself
--
-- A trigger, not a policy: RLS can only say yes or no to the whole row, and
-- this has to allow an update that leaves the name alone (avatar_url, or the
-- name being set to what it already is) while refusing one that changes it too
-- soon. It also stamps name_changed_at itself, so the column cannot be
-- back-dated by the client to buy another change.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_name_cooldown()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cooldown constant interval := interval '7 days';
  next_allowed timestamptz;
begin
  -- Untouched, or set to the same thing: nothing to rate limit, and the stamp
  -- must not move — otherwise saving the form without editing the name would
  -- silently start a new seven days.
  if new.full_name is not distinct from old.full_name then
    new.name_changed_at := old.name_changed_at;
    return new;
  end if;

  -- Trimmed and length-checked here too, so the rule holds for a direct API
  -- call and not only for clients that remember to validate.
  new.full_name := btrim(new.full_name);
  if char_length(new.full_name) = 0 then
    raise exception 'Your name cannot be empty.'
      using errcode = 'check_violation';
  end if;

  if old.name_changed_at is not null then
    next_allowed := old.name_changed_at + cooldown;
    if now() < next_allowed then
      raise exception 'You can change your name again on %.',
        to_char(next_allowed at time zone 'UTC', 'FMDay, FMDD FMMonth YYYY')
        using errcode = 'check_violation';
    end if;
  end if;

  new.name_changed_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_name_cooldown on public.profiles;
create trigger profiles_name_cooldown
  before update of full_name on public.profiles
  for each row execute function public.enforce_name_cooldown();

-- ---------------------------------------------------------------------------
-- What the client needs to render the form
--
-- Returns when the next change is allowed, so the UI can disable the field and
-- say why rather than letting someone type a new name and only then be told no.
-- ---------------------------------------------------------------------------

create or replace function public.my_name_change_status()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'name_changed_at', p.name_changed_at,
    'next_allowed_at', case
      when p.name_changed_at is null then null
      else p.name_changed_at + interval '7 days'
    end,
    'can_change_now', (
      p.name_changed_at is null
      or now() >= p.name_changed_at + interval '7 days'
    )
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

grant execute on function public.my_name_change_status() to authenticated;

-- The column needs no separate grant juggling to be safe: the trigger assigns
-- new.name_changed_at on every path before the row is written, so whatever a
-- client sends for it is overwritten. There is no value it can pass that
-- lifts its own cooldown.


-- ============================================================
-- 0013_task_notes.sql
-- ============================================================
-- 0013 — Work notes and attachments
--
-- Run after 0012. Safe to re-run.
--
-- The chat answers "what are we discussing?". This answers "what was actually
-- done, and what proves it?" — the record a supervisor reads when deciding
-- whether finished work is finished.
--
-- They are deliberately separate. A conversation is chronological and
-- disposable; a work note is evidence attached to a moment in the task's life,
-- and it carries the status the task was in when it was written. Mixing them
-- meant the proof of completion was buried between "ok" and "thanks".
--
-- The loop this supports:
--
--   1. the assignee marks the task done and writes a note saying what they did,
--      with photos or files attached
--   2. the supervisor reads it and either accepts, or sends it back to a
--      working status with a note saying what is wrong
--   3. the assignee fixes it and submits again, with another note
--
-- Every round leaves a row, so the whole back-and-forth stays readable
-- afterwards rather than being reconstructed from who said what in chat.

-- ---------------------------------------------------------------------------
-- What a note is for
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'task_note_kind' and n.nspname = 'public'
  ) then
    create type public.task_note_kind as enum (
      'update',     -- progress, written at any point
      'submission', -- "this is done, here is what I did"
      'rejection',  -- sent back: "this is not right yet, because…"
      'approval'    -- accepted by whoever was reviewing it
    );
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------------

create table if not exists public.task_notes (
  id           uuid                    primary key default uuid_generate_v4(),
  task_id      uuid                    not null references public.tasks(id)      on delete cascade,
  workspace_id uuid                    not null references public.workspaces(id) on delete cascade,
  author_id    uuid                    not null references public.profiles(id)   on delete cascade,
  kind         public.task_note_kind   not null default 'update',
  body         text                    not null default '',

  -- The status the task was in when this was written, and the one it moved to.
  -- Kept as text rather than a reference: a label can be renamed or deleted
  -- later, and the note has to keep saying what actually happened at the time.
  status_from  text,
  status_to    text,

  edited_at    timestamptz,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),

  -- A note with neither words nor a file says nothing. The check allows an
  -- empty body only because attachments are inserted immediately afterwards,
  -- in the same transaction as the note they belong to.
  constraint task_notes_body_length check (char_length(body) <= 5000)
);

create index if not exists task_notes_task_idx
  on public.task_notes(task_id, created_at desc);
create index if not exists task_notes_workspace_idx
  on public.task_notes(workspace_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Attachments
--
-- The file itself lives in Supabase Storage, not in Postgres. This row is only
-- the pointer plus what the UI needs to render a list without fetching
-- anything: name, size, and content type.
--
-- That is the answer to "is this heavy?" — it is not. A note with five photos
-- costs five short rows here; the bytes sit in object storage and are fetched
-- only when someone actually opens one.
-- ---------------------------------------------------------------------------

create table if not exists public.task_note_attachments (
  id           uuid        primary key default uuid_generate_v4(),
  note_id      uuid        not null references public.task_notes(id)  on delete cascade,
  task_id      uuid        not null references public.tasks(id)       on delete cascade,
  workspace_id uuid        not null references public.workspaces(id)  on delete cascade,

  -- Path within the `task-attachments` bucket. Deliberately not a public URL:
  -- the bucket is private, and the client signs a short-lived URL when someone
  -- opens the file.
  storage_path text        not null,
  file_name    text        not null,
  content_type text        not null default 'application/octet-stream',
  byte_size    bigint      not null default 0,
  created_at   timestamptz not null default now(),

  constraint task_note_attachments_name_length
    check (char_length(file_name) between 1 and 255),
  -- 25 MB. Large enough for photos of finished work, small enough that a
  -- mistaken upload of a video cannot fill the bucket.
  constraint task_note_attachments_size
    check (byte_size >= 0 and byte_size <= 26214400)
);

create index if not exists task_note_attachments_note_idx
  on public.task_note_attachments(note_id);
create index if not exists task_note_attachments_task_idx
  on public.task_note_attachments(task_id);

-- ---------------------------------------------------------------------------
-- Denormalised workspace_id
--
-- Same reasoning as everywhere else in this schema: realtime filters on
-- workspace_id server-side, and RLS reads it without another join.
-- ---------------------------------------------------------------------------

create or replace function public.derive_note_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.workspace_id is null then
    select t.workspace_id into new.workspace_id
    from public.tasks t where t.id = new.task_id;
  end if;
  return new;
end;
$$;

drop trigger if exists task_notes_derive_workspace on public.task_notes;
create trigger task_notes_derive_workspace
  before insert on public.task_notes
  for each row execute function public.derive_note_workspace();

drop trigger if exists task_note_attachments_derive_workspace
  on public.task_note_attachments;
create trigger task_note_attachments_derive_workspace
  before insert on public.task_note_attachments
  for each row execute function public.derive_note_workspace();

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Readable by the workspace, writable by its author. Editors and above can
-- write notes; viewers read them like everything else.
-- ---------------------------------------------------------------------------

alter table public.task_notes            enable row level security;
alter table public.task_note_attachments enable row level security;

drop policy if exists task_notes_select on public.task_notes;
create policy task_notes_select on public.task_notes
  for select to authenticated
  using (public.is_workspace_member(workspace_id) and deleted_at is null);

-- Anyone who can edit writes an update or a submission — that is the assignee
-- reporting on their own work. Verdicts are different: approving or sending
-- back is a supervisor's call, so those two kinds require the same right that
-- manages the team. Without this a member could approve their own submission.
drop policy if exists task_notes_insert on public.task_notes;
create policy task_notes_insert on public.task_notes
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.can_edit_workspace(workspace_id)
    and (
      kind in ('update', 'submission')
      or public.can_manage_workspace(workspace_id)
    )
  );

-- Only the author edits their own note. A supervisor who disagrees writes
-- their own rather than rewriting someone else's account of what they did.
drop policy if exists task_notes_update on public.task_notes;
create policy task_notes_update on public.task_notes
  for update to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

drop policy if exists task_notes_delete on public.task_notes;
create policy task_notes_delete on public.task_notes
  for delete to authenticated
  using (author_id = auth.uid() or public.can_manage_workspace(workspace_id));

drop policy if exists task_note_attachments_select on public.task_note_attachments;
create policy task_note_attachments_select on public.task_note_attachments
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

drop policy if exists task_note_attachments_insert on public.task_note_attachments;
create policy task_note_attachments_insert on public.task_note_attachments
  for insert to authenticated
  with check (
    public.can_edit_workspace(workspace_id)
    and exists (
      select 1 from public.task_notes n
      where n.id = note_id and n.author_id = auth.uid()
    )
  );

drop policy if exists task_note_attachments_delete on public.task_note_attachments;
create policy task_note_attachments_delete on public.task_note_attachments
  for delete to authenticated
  using (
    public.can_manage_workspace(workspace_id)
    or exists (
      select 1 from public.task_notes n
      where n.id = note_id and n.author_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Storage
--
-- One private bucket. Paths are `<workspace_id>/<task_id>/<uuid>-<name>`, so
-- the first path segment is the workspace and the policies below can check
-- membership from the object name alone without a lookup table.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('task-attachments', 'task-attachments', false, 26214400)
on conflict (id) do update set
  public = false,
  file_size_limit = 26214400;

drop policy if exists task_attachments_read on storage.objects;
create policy task_attachments_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'task-attachments'
    and public.is_workspace_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists task_attachments_write on storage.objects;
create policy task_attachments_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'task-attachments'
    and public.can_edit_workspace((storage.foldername(name))[1]::uuid)
  );

drop policy if exists task_attachments_delete on storage.objects;
create policy task_attachments_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'task-attachments'
    and public.can_edit_workspace((storage.foldername(name))[1]::uuid)
  );

-- ---------------------------------------------------------------------------
-- Telling people a note was written
--
-- Reuses the existing note_added notification kind. Everyone assigned to the
-- task hears about it, except whoever wrote it.
-- ---------------------------------------------------------------------------

create or replace function public.notify_on_task_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  task_title text;
  recipient  uuid;
  headline   text;
begin
  select t.title into task_title from public.tasks t where t.id = new.task_id;

  headline := case new.kind
    when 'submission' then public.actor_name(new.author_id)
                           || ' submitted work on "' || coalesce(task_title, 'a task') || '"'
    when 'rejection'  then public.actor_name(new.author_id)
                           || ' sent back "' || coalesce(task_title, 'a task') || '"'
    when 'approval'   then public.actor_name(new.author_id)
                           || ' approved "' || coalesce(task_title, 'a task') || '"'
    else public.actor_name(new.author_id)
         || ' added a note to "' || coalesce(task_title, 'a task') || '"'
  end;

  for recipient in
    select a.user_id from public.task_assignees a where a.task_id = new.task_id
    union
    select t.created_by from public.tasks t where t.id = new.task_id
  loop
    if recipient is not null and recipient <> new.author_id then
      perform public.notify_user(
        recipient   => recipient,
        n_kind      => 'note_added',
        n_title     => headline,
        n_body      => left(new.body, 140),
        n_workspace => new.workspace_id,
        n_task      => new.task_id,
        n_actor     => new.author_id
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists task_notes_notify on public.task_notes;
create trigger task_notes_notify
  after insert on public.task_notes
  for each row execute function public.notify_on_task_note();

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['task_notes', 'task_note_attachments']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null;
    end;
  end loop;
end
$$;

alter table public.task_notes            replica identity full;
alter table public.task_note_attachments replica identity full;


-- ============================================================
-- 0014_status_actor_and_delete_rules.sql
-- ============================================================
-- 0014 — Who moved it, how many notes, and who may destroy it
--
-- Run after 0013. Safe to re-run.
--
-- Three things the board could not answer:
--
--   * "who marked this done?" — a task can have several assignees, so the
--     avatars on the row say who is *responsible*, not who actually finished
--     it. Reading the activity log to find out is a click and a scroll.
--   * "does this task have any notes?" — the badge needs a count, and counting
--     rows per task at render time is what comment_count already avoids.
--   * "can a member destroy a task outright?" — until now, yes.

-- ---------------------------------------------------------------------------
-- Who last moved the status, and when
--
-- Denormalised onto the task rather than read from task_activity. The board
-- renders hundreds of rows and each would otherwise need its own lookup for
-- one line of text; this is the same trade already made for comment_count.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists status_by uuid references public.profiles(id) on delete set null;

alter table public.tasks
  add column if not exists status_at timestamptz;

create or replace function public.touch_status_actor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status_id is distinct from old.status_id then
    -- auth.uid() is null when a trigger or a scheduled sweep moves the task
    -- rather than a person. Leaving it null is correct: "nobody in particular"
    -- is the honest answer, and the UI then shows the status with no byline.
    new.status_by := auth.uid();
    new.status_at := now();
  end if;
  return new;
end;
$$;

-- Numbered 5 so it runs after the existing status and progress triggers, and
-- therefore sees the status the row is actually settling on.
drop trigger if exists tasks_5_touch_status_actor on public.tasks;
create trigger tasks_5_touch_status_actor
  before update of status_id on public.tasks
  for each row execute function public.touch_status_actor();

-- ---------------------------------------------------------------------------
-- Note count
--
-- Maintained the same way comment_count is: a trigger on the notes table,
-- rather than a count(*) the board pays for on every render.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists note_count int not null default 0;

create or replace function public.sync_note_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.task_id, old.task_id);
begin
  update public.tasks t
  set note_count = (
    select count(*) from public.task_notes n
    where n.task_id = target and n.deleted_at is null
  )
  where t.id = target;
  return coalesce(new, old);
end;
$$;

-- Covers the soft delete too: deleted_at moving is an update, and a note in
-- the bin should not be counted on the badge.
drop trigger if exists task_notes_count on public.task_notes;
create trigger task_notes_count
  after insert or delete or update of deleted_at on public.task_notes
  for each row execute function public.sync_note_count();

-- Backfill, so a database that already has notes shows the right number.
update public.tasks t
set note_count = (
  select count(*) from public.task_notes n
  where n.task_id = t.id and n.deleted_at is null
)
where exists (select 1 from public.task_notes n where n.task_id = t.id);

-- ---------------------------------------------------------------------------
-- Deleting is soft; destroying is not for members
--
-- soft_delete() already required only edit rights, which is right: a member
-- should be able to clear a task off the board, and the row survives for 30
-- days where an admin can restore it.
--
-- The DELETE policy was the hole. It allowed any editor to remove the row
-- outright through the API, skipping soft_delete entirely — no recovery, no
-- record. Permanent removal now needs the same right that manages the team.
-- ---------------------------------------------------------------------------

drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks
  for delete to authenticated using (public.can_manage_workspace(workspace_id));

-- The same reasoning for the containers. A member emptying a board or a group
-- permanently is a bigger loss than a single task.
drop policy if exists boards_delete on public.boards;
create policy boards_delete on public.boards
  for delete to authenticated using (public.can_manage_workspace(workspace_id));

drop policy if exists groups_delete on public.task_groups;
create policy groups_delete on public.task_groups
  for delete to authenticated using (public.can_manage_workspace(workspace_id));

-- ---------------------------------------------------------------------------
-- Restoring
--
-- restore() asks for edit rights, matching soft_delete(). That stays: the
-- point of the recycle bin is that an ordinary mistake can be undone by the
-- person who made it, without waiting for an admin.
--
-- What needs fixing is that restoring a task into a board or group that is
-- itself deleted puts the row somewhere invisible — restored, but nowhere.
-- ---------------------------------------------------------------------------

create or replace function public.restore(entity text, target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws     uuid;
  parent record;
begin
  if entity not in ('boards', 'task_groups', 'tasks', 'task_comments') then
    raise exception 'Cannot restore %.', entity;
  end if;

  execute format('select workspace_id from public.%I where id = $1', entity)
    into ws using target_id;

  if ws is null then
    raise exception 'Row % not found in %.', target_id, entity;
  end if;
  if not public.can_edit_workspace(ws) then
    raise exception 'You do not have permission to restore this.';
  end if;

  -- Bring the container back with it. Deleting a board soft-deletes its groups
  -- and tasks, so restoring one task out of that set used to leave it attached
  -- to a group nobody can see.
  if entity = 'tasks' then
    select g.id as group_id, b.id as board_id
      into parent
    from public.tasks t
    join public.task_groups g on g.id = t.group_id
    join public.boards b      on b.id = g.board_id
    where t.id = target_id;

    if parent.board_id is not null then
      update public.boards set deleted_at = null where id = parent.board_id;
      update public.task_groups set deleted_at = null where id = parent.group_id;
    end if;
  elsif entity = 'task_groups' then
    update public.boards b set deleted_at = null
    where b.id = (select group_board.board_id
                  from public.task_groups group_board
                  where group_board.id = target_id);
  end if;

  execute format('update public.%I set deleted_at = null where id = $1', entity)
    using target_id;
end;
$$;

grant execute on function public.restore(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- board_tree carries the new columns
--
-- The client reads the whole board through this one RPC, so a column that is
-- not listed here does not exist as far as the app is concerned. Republished
-- verbatim from 0003 with note_count, status_by and status_at added.
-- ---------------------------------------------------------------------------

create or replace function public.board_tree(target_workspace uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  -- Pinned boards first, then by position. Sorted on the source columns, not
  -- on the JSON: `board->>'position'` compares text, so 10 sorts before 2.
  select coalesce(
    jsonb_agg(board order by pinned desc, position), '[]'::jsonb
  )
  from (
    select b.pinned, b.position, jsonb_build_object(
      'id',       b.id,
      'name',     b.name,
      'color',    b.color,
      'position', b.position,
      'pinned',   b.pinned,
      'statuses', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', s.id, 'name', s.name, 'color', s.color,
          'position', s.position, 'is_done', s.is_done, 'is_default', s.is_default
        ) order by s.position), '[]'::jsonb)
        from public.board_status_labels s where s.board_id = b.id
      ),
      'groups', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', g.id, 'board_id', g.board_id, 'name', g.name,
          'color', g.color, 'position', g.position, 'collapsed', g.collapsed,
          'tasks', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'id', t.id, 'group_id', t.group_id, 'board_id', t.board_id,
              'title', t.title, 'status_id', t.status_id,
              'priority', t.priority, 'due_date', t.due_date,
              'start_date', t.start_date, 'end_date', t.end_date,
              'progress', t.progress, 'progress_at', t.progress_at,
              'position', t.position,
              'comment_count', t.comment_count,
              'note_count', t.note_count,
              -- Who last moved the status, and when. The profile is embedded
              -- rather than left as an id: the board renders this as an avatar
              -- beside the status, and a second round trip per row to resolve
              -- names would undo the point of fetching the tree in one call.
              'status_at', t.status_at,
              'status_by', case
                when sp.id is null then null
                else jsonb_build_object(
                  'id', sp.id, 'email', sp.email,
                  'full_name', sp.full_name, 'avatar_url', sp.avatar_url
                )
              end,
              'assignee_ids', (
                select coalesce(jsonb_agg(a.user_id), '[]'::jsonb)
                from public.task_assignees a where a.task_id = t.id
              )
            ) order by t.position), '[]'::jsonb)
            from public.tasks t
            left join public.profiles sp on sp.id = t.status_by
            where t.group_id = g.id and t.deleted_at is null
          )
        ) order by g.position), '[]'::jsonb)
        from public.task_groups g
        where g.board_id = b.id and g.deleted_at is null
      )
    ) as board
    from public.boards b
    where b.workspace_id = target_workspace
      and b.deleted_at is null
      and public.is_workspace_member(target_workspace)
  ) boards;
$$;

grant execute on function public.board_tree(uuid) to authenticated;


-- ============================================================
-- 0015_drop_note_attachments.sql
-- ============================================================
-- 0015 — Work notes are text only
--
-- Run after 0014. Safe to re-run.
--
-- 0013 gave notes file attachments, backed by a private storage bucket with a
-- 25 MB per-file cap. That is the right design on a paid plan and the wrong
-- one on the free tier, which allows 1 GB in total: forty files at the cap
-- would fill it, and the failure mode is uploads breaking for everyone with no
-- obvious cause.
--
-- So attachments come out entirely rather than being left half-disabled. A
-- note is what was done, in words — which is the part that actually gets read
-- when someone reviews finished work.
--
-- The notes themselves, the submit / send-back / approve loop, and everything
-- 0014 added are untouched.

-- ---------------------------------------------------------------------------
-- The rows
--
-- Dropped before the bucket: the table references nothing in storage, but
-- doing it in this order means a re-run cannot leave rows pointing at objects
-- that are already gone.
-- ---------------------------------------------------------------------------

drop table if exists public.task_note_attachments cascade;

-- ---------------------------------------------------------------------------
-- The files
--
-- Deleting the objects first, then the bucket. A bucket with contents cannot
-- be dropped, and on a database where somebody managed to upload before this
-- ran, those bytes are exactly what needs reclaiming.
-- ---------------------------------------------------------------------------

delete from storage.objects where bucket_id = 'task-attachments';
delete from storage.buckets where id = 'task-attachments';

drop policy if exists task_attachments_read   on storage.objects;
drop policy if exists task_attachments_write  on storage.objects;
drop policy if exists task_attachments_delete on storage.objects;

-- ---------------------------------------------------------------------------
-- Realtime
--
-- Removing a table from the publication is not automatic when it is dropped
-- in every Postgres version, and a stale entry makes the publication noisy to
-- read later. Guarded because the table may already be gone.
-- ---------------------------------------------------------------------------

do $$
begin
  alter publication supabase_realtime drop table public.task_note_attachments;
exception
  when undefined_object or undefined_table then null;
end
$$;

-- ---------------------------------------------------------------------------
-- The note trigger no longer has a second table to worry about
--
-- sync_note_count() only ever read task_notes, so it needs no change. This is
-- a note for whoever reads this file later wondering whether it was missed.
-- ---------------------------------------------------------------------------
