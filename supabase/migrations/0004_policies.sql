-- 0004 — Row level security
--
-- Run after 0003.
--
-- Every table reads its own workspace_id column and asks one of two questions:
--   is_workspace_member(workspace_id)  -> can read
--   can_edit_workspace(workspace_id)   -> can write (not viewers)
--
-- No policy walks task -> group -> board any more; the column is on the row.
--
-- Soft-deleted rows are excluded in the SELECT policy rather than in each
-- query, so nothing has to remember `where deleted_at is null`. The recycle
-- bin reads through deleted_items(), which is SECURITY DEFINER.

alter table public.profiles            enable row level security;
alter table public.workspaces          enable row level security;
alter table public.workspace_members   enable row level security;
alter table public.workspace_invites   enable row level security;
alter table public.boards              enable row level security;
alter table public.board_status_labels enable row level security;
alter table public.board_columns       enable row level security;
alter table public.board_views         enable row level security;
alter table public.task_groups         enable row level security;
alter table public.tasks               enable row level security;
alter table public.task_assignees      enable row level security;
alter table public.task_column_values  enable row level security;
alter table public.task_comment_reactions enable row level security;
alter table public.task_comment_mentions  enable row level security;
alter table public.task_comments       enable row level security;
alter table public.task_activity       enable row level security;
alter table public.notifications       enable row level security;
alter table public.join_attempts       enable row level security;

-- ---------------------------------------------------------------------------
-- Profiles
--
-- Readable by anyone signed in: teammate names have to render, and the client
-- resolves assignees by id. Writable only by their owner. No insert policy —
-- the handle_new_user trigger creates them.
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Workspaces
-- ---------------------------------------------------------------------------
-- Members see their workspaces. So does anyone holding an open invitation to
-- one — otherwise they cannot see the name of the place they are being asked
-- to join.
--
-- Without the second arm, `workspace_invites` embedding `workspaces(name)`
-- returned null for the invited person: the invitation row was visible, the
-- workspace it named was not, and the client dropped the invitation for having
-- nothing to display. The invitation existed and was pending the whole time,
-- which made it look like invitations were expiring.
--
-- This exposes only name and colour, to someone who was explicitly invited, and
-- only while the invitation is unanswered. Boards and tasks stay behind
-- is_workspace_member.
drop policy if exists workspaces_select on public.workspaces;
create policy workspaces_select on public.workspaces
  for select to authenticated using (
    public.is_workspace_member(id)
    or exists (
      select 1 from public.workspace_invites i
      where i.workspace_id = workspaces.id
        and i.accepted_at is null
        and i.declined_at is null
        and (
          i.invitee_id = auth.uid()
          or lower(i.email) = lower(auth.jwt()->>'email')
        )
    )
  );

drop policy if exists workspaces_insert on public.workspaces;
create policy workspaces_insert on public.workspaces
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists workspaces_update on public.workspaces;
create policy workspaces_update on public.workspaces
  for update to authenticated
  using (public.can_manage_workspace(id))
  with check (public.can_manage_workspace(id));

-- Deleting takes the whole team's work with it, so it stays with the owner
-- alone — not admins.
drop policy if exists workspaces_delete on public.workspaces;
create policy workspaces_delete on public.workspaces
  for delete to authenticated using (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Members
-- ---------------------------------------------------------------------------
drop policy if exists members_select on public.workspace_members;
create policy members_select on public.workspace_members
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists members_insert on public.workspace_members;
create policy members_insert on public.workspace_members
  for insert to authenticated with check (
    -- The creator enrolling in their own new workspace, or a manager adding
    -- someone. join_workspace_with_code() and accept_pending_invites() are
    -- SECURITY DEFINER and bypass this.
    user_id = auth.uid()
    or public.can_manage_workspace(workspace_id)
  );

drop policy if exists members_update on public.workspace_members;
create policy members_update on public.workspace_members
  for update to authenticated
  using (public.can_manage_workspace(workspace_id))
  with check (public.can_manage_workspace(workspace_id));

drop policy if exists members_delete on public.workspace_members;
create policy members_delete on public.workspace_members
  for delete to authenticated using (
    user_id = auth.uid()  -- leaving a workspace
    or public.can_manage_workspace(workspace_id)
  );

-- ---------------------------------------------------------------------------
-- Invites
--
-- Members see their workspace's invitations; the invited person sees their own
-- by email, before they are a member of anything.
-- ---------------------------------------------------------------------------
drop policy if exists invites_select on public.workspace_invites;
create policy invites_select on public.workspace_invites
  for select to authenticated using (
    public.is_workspace_member(workspace_id)
    or invitee_id = auth.uid()
    -- The email arm still matters: someone invited before signing up has a
    -- null invitee_id until the profiles trigger links it.
    or lower(email) = lower(auth.jwt()->>'email')
  );

drop policy if exists invites_insert on public.workspace_invites;
create policy invites_insert on public.workspace_invites
  for insert to authenticated with check (
    public.can_manage_workspace(workspace_id) and invited_by = auth.uid()
  );

-- The invited person needs update to decline: they cannot delete, because the
-- delete policy requires membership they do not have yet.
drop policy if exists invites_update on public.workspace_invites;
create policy invites_update on public.workspace_invites
  for update to authenticated using (
    invitee_id = auth.uid()
    or lower(email) = lower(auth.jwt()->>'email')
    or public.can_manage_workspace(workspace_id)
  );

drop policy if exists invites_delete on public.workspace_invites;
create policy invites_delete on public.workspace_invites
  for delete to authenticated using (public.can_manage_workspace(workspace_id));

-- ---------------------------------------------------------------------------
-- Boards
-- ---------------------------------------------------------------------------
drop policy if exists boards_select on public.boards;
create policy boards_select on public.boards
  for select to authenticated
  using (public.is_workspace_member(workspace_id) and deleted_at is null);

drop policy if exists boards_insert on public.boards;
create policy boards_insert on public.boards
  for insert to authenticated with check (public.can_edit_workspace(workspace_id));

-- No `deleted_at is null` in USING: soft-deleting is itself an update, and
-- restore() has to be able to see the row it is bringing back.
drop policy if exists boards_update on public.boards;
create policy boards_update on public.boards
  for update to authenticated
  using (public.can_edit_workspace(workspace_id))
  with check (public.can_edit_workspace(workspace_id));

drop policy if exists boards_delete on public.boards;
create policy boards_delete on public.boards
  for delete to authenticated using (public.can_manage_workspace(workspace_id));

-- Status labels follow their board.
drop policy if exists status_labels_select on public.board_status_labels;
create policy status_labels_select on public.board_status_labels
  for select to authenticated using (
    exists (
      select 1 from public.boards b
      where b.id = board_id and public.is_workspace_member(b.workspace_id)
    )
  );

drop policy if exists status_labels_write on public.board_status_labels;
create policy status_labels_write on public.board_status_labels
  for all to authenticated
  using (
    exists (
      select 1 from public.boards b
      where b.id = board_id and public.can_edit_workspace(b.workspace_id)
    )
  )
  with check (
    exists (
      select 1 from public.boards b
      where b.id = board_id and public.can_edit_workspace(b.workspace_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Board columns and views
-- ---------------------------------------------------------------------------
drop policy if exists board_columns_select on public.board_columns;
create policy board_columns_select on public.board_columns
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists board_columns_write on public.board_columns;
create policy board_columns_write on public.board_columns
  for all to authenticated
  using (public.can_edit_workspace(workspace_id))
  with check (public.can_edit_workspace(workspace_id));

-- Personal views are private to their creator.
drop policy if exists board_views_select on public.board_views;
create policy board_views_select on public.board_views
  for select to authenticated using (
    public.is_workspace_member(workspace_id)
    and (is_shared or created_by = auth.uid())
  );

drop policy if exists board_views_insert on public.board_views;
create policy board_views_insert on public.board_views
  for insert to authenticated
  with check (public.can_edit_workspace(workspace_id) and created_by = auth.uid());

-- A shared view belongs to the team; a personal one only to its creator.
drop policy if exists board_views_update on public.board_views;
create policy board_views_update on public.board_views
  for update to authenticated
  using (
    created_by = auth.uid()
    or (is_shared and public.can_edit_workspace(workspace_id))
  )
  with check (public.can_edit_workspace(workspace_id));

drop policy if exists board_views_delete on public.board_views;
create policy board_views_delete on public.board_views
  for delete to authenticated using (
    created_by = auth.uid() or public.can_manage_workspace(workspace_id)
  );

-- ---------------------------------------------------------------------------
-- Groups and tasks
-- ---------------------------------------------------------------------------
drop policy if exists groups_select on public.task_groups;
create policy groups_select on public.task_groups
  for select to authenticated
  using (public.is_workspace_member(workspace_id) and deleted_at is null);

drop policy if exists groups_insert on public.task_groups;
create policy groups_insert on public.task_groups
  for insert to authenticated with check (public.can_edit_workspace(workspace_id));

drop policy if exists groups_update on public.task_groups;
create policy groups_update on public.task_groups
  for update to authenticated
  using (public.can_edit_workspace(workspace_id))
  with check (public.can_edit_workspace(workspace_id));

drop policy if exists groups_delete on public.task_groups;
create policy groups_delete on public.task_groups
  for delete to authenticated using (public.can_edit_workspace(workspace_id));

drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks
  for select to authenticated
  using (public.is_workspace_member(workspace_id) and deleted_at is null);

drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks
  for insert to authenticated with check (public.can_edit_workspace(workspace_id));

drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks
  for update to authenticated
  using (public.can_edit_workspace(workspace_id))
  with check (public.can_edit_workspace(workspace_id));

drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks
  for delete to authenticated using (public.can_edit_workspace(workspace_id));

drop policy if exists task_assignees_select on public.task_assignees;
create policy task_assignees_select on public.task_assignees
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists task_assignees_write on public.task_assignees;
create policy task_assignees_write on public.task_assignees
  for all to authenticated
  using (public.can_edit_workspace(workspace_id))
  with check (public.can_edit_workspace(workspace_id));

drop policy if exists column_values_select on public.task_column_values;
create policy column_values_select on public.task_column_values
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists column_values_write on public.task_column_values;
create policy column_values_write on public.task_column_values
  for all to authenticated
  using (public.can_edit_workspace(workspace_id))
  with check (public.can_edit_workspace(workspace_id));

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------
drop policy if exists comments_select on public.task_comments;
create policy comments_select on public.task_comments
  for select to authenticated
  using (public.is_workspace_member(workspace_id) and deleted_at is null);

drop policy if exists comments_insert on public.task_comments;
create policy comments_insert on public.task_comments
  for insert to authenticated
  with check (author_id = auth.uid() and public.can_edit_workspace(workspace_id));

-- Editing your own words only, however senior you are.
--
-- Managers are included because removing a message is a soft delete, which is
-- an UPDATE — without them here, moderation would be impossible. The author
-- check on the text itself is enforced in the client, since a single policy
-- cannot say "the author may change body, a manager may only set deleted_at".
drop policy if exists comments_update on public.task_comments;
create policy comments_update on public.task_comments
  for update to authenticated
  using (author_id = auth.uid() or public.can_manage_workspace(workspace_id))
  with check (author_id = auth.uid() or public.can_manage_workspace(workspace_id));

drop policy if exists comments_delete on public.task_comments;
create policy comments_delete on public.task_comments
  for delete to authenticated
  using (author_id = auth.uid() or public.can_manage_workspace(workspace_id));

-- Reactions: yours alone, on a message you can see.
drop policy if exists comment_reactions_select on public.task_comment_reactions;
create policy comment_reactions_select on public.task_comment_reactions
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists comment_reactions_write on public.task_comment_reactions;
create policy comment_reactions_write on public.task_comment_reactions
  for all to authenticated
  using (user_id = auth.uid() and public.is_workspace_member(workspace_id))
  with check (user_id = auth.uid() and public.is_workspace_member(workspace_id));

-- Mentions are a record of what happened, written by a trigger. No insert or
-- update policy: a client that could write these could ping anyone at will.
drop policy if exists comment_mentions_select on public.task_comment_mentions;
create policy comment_mentions_select on public.task_comment_mentions
  for select to authenticated using (public.is_workspace_member(workspace_id));

-- ---------------------------------------------------------------------------
-- Activity — append-only
--
-- Deliberately no update or delete policy: an audit trail that can be rewritten
-- is not one. Inserts go through log_activity(), which stamps the actor.
-- ---------------------------------------------------------------------------
drop policy if exists activity_select on public.task_activity;
create policy activity_select on public.task_activity
  for select to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists activity_insert on public.task_activity;
create policy activity_insert on public.task_activity
  for insert to authenticated
  with check (actor_id = auth.uid() and public.can_edit_workspace(workspace_id));

-- ---------------------------------------------------------------------------
-- Join attempts
--
-- Deliberately no policy at all beyond reading your own. The rows are written
-- by join_workspace_with_code(), which is SECURITY DEFINER — a client that
-- could insert or delete here would simply clear its own failures and defeat
-- the limit.
-- ---------------------------------------------------------------------------
drop policy if exists join_attempts_select on public.join_attempts;
create policy join_attempts_select on public.join_attempts
  for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Notifications
--
-- Yours and nobody else's. Keyed on user_id rather than workspace membership:
-- an invitation notification arrives before you are a member of anything, so a
-- membership check would hide exactly the notification that matters most.
--
-- No insert policy. Notifications are written for *other* people, which no
-- client should be able to do — notify_user() is SECURITY DEFINER and every
-- caller is a trigger.
-- ---------------------------------------------------------------------------
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select to authenticated using (user_id = auth.uid());

-- Marking read. WITH CHECK repeats the condition so a row cannot be reassigned
-- to someone else on the way out.
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications
  for delete to authenticated using (user_id = auth.uid());
