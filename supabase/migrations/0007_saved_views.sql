-- ---------------------------------------------------------------------------
-- Saved filter views
--
-- The filter panel stores its favorites in board_views, which has held a name,
-- a jsonb config, and a created_by since 0002. No new table is needed — this
-- migration only relaxes who may save a *private* one.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- Why the insert policy changes.
--
-- board_views_insert required can_edit_workspace(), which is owner/admin/member
-- and deliberately excludes viewers. That is right for a *shared* view, which
-- everyone on the board then sees. It is wrong for a private favorite: saving
-- "my overdue tasks" for your own use changes nothing anyone else can observe,
-- and a viewer who can read the board has every reason to want one.
--
-- So the rule now splits on is_shared: any member of the workspace may create a
-- view that is theirs alone, while publishing one to the team still takes edit
-- rights. created_by = auth.uid() is kept in both branches, so a view cannot be
-- inserted under someone else's name either way.
drop policy if exists board_views_insert on public.board_views;
create policy board_views_insert on public.board_views
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and (
      -- A private favorite: membership is enough.
      (not is_shared and public.is_workspace_member(workspace_id))
      -- A shared one is published to the whole board, so it needs edit rights.
      or (is_shared and public.can_edit_workspace(workspace_id))
    )
  );

-- The update policy needs the same treatment for the same reason: without it a
-- viewer could create a private favorite and then not be able to rename it, or
-- to change which filters it holds.
--
-- The with-check half is what stops a viewer flipping is_shared on afterwards
-- to publish a view they could not have published directly.
drop policy if exists board_views_update on public.board_views;
create policy board_views_update on public.board_views
  for update to authenticated
  using (
    created_by = auth.uid()
    or (is_shared and public.can_edit_workspace(workspace_id))
  )
  with check (
    (not is_shared and public.is_workspace_member(workspace_id))
    or (is_shared and public.can_edit_workspace(workspace_id))
  );

-- At most one default view per board per person.
--
-- Enforced here rather than in the client: two clients racing to set a default
-- would both succeed, and the board would then pick whichever row came back
-- first. A partial unique index makes the second write fail instead.
--
-- Expression indexes must be immutable, so this reads the flag out of the jsonb
-- with the ->> operator, which is. `config ->> 'is_default' = 'true'` is a text
-- comparison on purpose — jsonb true and the string "true" both serialise to
-- the same text here, and casting to boolean would not be immutable.
drop index if exists board_views_one_default_idx;
create unique index board_views_one_default_idx
  on public.board_views(board_id, created_by)
  where (config ->> 'is_default') = 'true';

-- Views are per-person and change rarely; the board query reads them by board.
create index if not exists board_views_owner_idx
  on public.board_views(board_id, created_by);
