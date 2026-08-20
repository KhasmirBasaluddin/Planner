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
