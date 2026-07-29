-- 0001 — Reset
--
-- DESTRUCTIVE. Drops every Planner table and everything in them: workspaces,
-- boards, groups, tasks, notes, invitations.
--
-- auth.users is left alone, so accounts and passwords survive. Profiles are
-- rebuilt from auth.users by 0006, and the handle_new_user trigger keeps them
-- in sync from then on.
--
-- Run this only when starting fresh. If the data matters, stop here.

-- Views first: they depend on the tables below.
drop view if exists public.board_task_counts cascade;

-- Child tables before parents. CASCADE also removes the policies, triggers and
-- indexes attached to each.
drop table if exists public.join_attempts      cascade;
drop table if exists public.notifications      cascade;
drop table if exists public.task_comment_reactions cascade;
drop table if exists public.task_comment_mentions  cascade;
-- Superseded by task_comments; dropped so a reset clears the old shape too.
drop table if exists public.task_note_reactions    cascade;
drop table if exists public.task_notes             cascade;
drop table if exists public.task_comments      cascade;
drop table if exists public.task_activity      cascade;
drop table if exists public.task_column_values cascade;
drop table if exists public.task_assignees     cascade;
drop table if exists public.tasks              cascade;
drop table if exists public.task_groups        cascade;
drop table if exists public.board_status_labels cascade;
drop table if exists public.board_views        cascade;
drop table if exists public.board_columns      cascade;
drop table if exists public.boards             cascade;
drop table if exists public.workspace_invites  cascade;
drop table if exists public.workspace_members  cascade;
drop table if exists public.workspaces         cascade;
drop table if exists public.profiles           cascade;

-- Functions from the previous schema. Signatures must match to drop cleanly.
-- Every function this project has ever defined, swept rather than listed.
--
-- An earlier version named each one explicitly, which meant a function from a
-- superseded draft survived the reset — `link_invite_to_user` outlived the
-- rewrite that replaced it and sat in the schema doing nothing. A name-by-name
-- list can only drop what its author remembered.
--
-- Two things are deliberately spared:
--
--   * hook_allow_vintazk_email, because it is selected by hand in the dashboard
--     under Authentication -> Hooks. Dropping it silently breaks signups until
--     someone re-picks it. 0003 replaces it in place instead.
--   * anything owned by an extension — uuid-ossp, pgcrypto, pg_cron and friends
--     install into public on Supabase, and dropping their functions would
--     break the extension itself.
do $$
declare
  fn record;
begin
  for fn in
    select
      p.oid::regprocedure as signature,
      case when p.prokind = 'a' then 'aggregate' else 'function' end as kind
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname <> 'hook_allow_vintazk_email'
      -- pg_depend 'e' marks a member of an extension.
      and not exists (
        select 1 from pg_depend d
        where d.objid = p.oid and d.deptype = 'e'
      )
  loop
    execute format('drop %s if exists %s cascade', fn.kind, fn.signature);
  end loop;
end
$$;

-- Enum types, swept for the same reason as the functions above. Dropped last,
-- because the tables and functions using them are already gone.
--
-- Only enums: composite types backing a table are removed with the table, and
-- extension-owned types must stay.
do $$
declare
  t record;
begin
  for t in
    select ty.oid::regtype as name
    from pg_type ty
    join pg_namespace n on n.oid = ty.typnamespace
    where n.nspname = 'public'
      and ty.typtype = 'e'
      and not exists (
        select 1 from pg_depend d
        where d.objid = ty.oid and d.deptype = 'e'
      )
  loop
    execute format('drop type if exists %s cascade', t.name);
  end loop;
end
$$;
