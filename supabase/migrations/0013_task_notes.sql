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
