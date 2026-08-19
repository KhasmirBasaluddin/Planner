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
