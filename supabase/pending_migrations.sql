-- Planner: migrations 0008, 0009, 0010
-- Paste into the Supabase SQL editor and run. All are safe to re-run.


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
