-- 0005 — Realtime
--
-- Run after 0004.
--
-- Publishing a table lets the app subscribe to its changes, so a teammate's
-- edit appears without a refresh. RLS still applies: a subscriber only receives
-- rows they could have read anyway.

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  -- Added one at a time. In a single ALTER, one already-published table aborts
  -- the whole statement, which previously left realtime silently
  -- half-configured.
  foreach t in array array[
    -- Board content
    'boards', 'task_groups', 'tasks', 'task_assignees',
    'board_status_labels', 'board_columns', 'task_column_values', 'board_views',
    -- Discussion
    'task_comments', 'task_comment_reactions', 'task_comment_mentions',
    -- Team: membership changes and invitations are live, so a role change,
    -- removal, or someone joining by code shows up for everyone immediately.
    'workspaces', 'workspace_members', 'workspace_invites',
    -- Notifications arrive live, so the bell fills in without a poll.
    'notifications'
  ]
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null;  -- already published
    end;
  end loop;
end
$$;

-- Realtime only sends the changed row's full contents when the table records a
-- complete "before" image. Without this an UPDATE arrives carrying just the
-- primary key — not enough to refresh a row in place, and not enough for the
-- client to tell whether an update it can no longer see was a soft delete or a
-- permission change.
alter table public.boards              replica identity full;
alter table public.task_groups         replica identity full;
alter table public.tasks               replica identity full;
alter table public.task_assignees      replica identity full;
alter table public.board_status_labels replica identity full;
alter table public.board_columns       replica identity full;
alter table public.task_column_values  replica identity full;
alter table public.board_views         replica identity full;
alter table public.task_comments          replica identity full;
alter table public.task_comment_reactions replica identity full;
alter table public.task_comment_mentions  replica identity full;
alter table public.workspaces          replica identity full;
alter table public.workspace_members   replica identity full;
alter table public.workspace_invites   replica identity full;
alter table public.notifications       replica identity full;
