-- Empty every table's rows, keeping the schema itself.
--
-- Structure survives: tables, columns, constraints, indexes, triggers,
-- functions, policies, and the realtime publication are all untouched. Only
-- rows go. This is not 0001_reset.sql — that one drops the schema and makes you
-- run every migration again.
--
-- WHAT THIS DELETES, permanently and with no undo:
--   every workspace, and everyone's membership in them
--   every board, group, task, assignment, and column value
--   every chat message, reaction, and mention
--   every notification, invite, and activity record
--
-- WHAT SURVIVES:
--   auth.users — nobody is logged out, no password changes
--   public.profiles — see the note below
--
-- Run it in the Supabase SQL editor. Take a backup first if there is anything
-- here you would miss.

-- ---------------------------------------------------------------------------
-- First, repair join_attempts if it is missing.
--
-- It was added to 0002_core.sql after that migration had already been run, so a
-- database set up before then does not have it. That is not only this script's
-- problem: join_workspace_with_code() reads and writes this table, so joining a
-- workspace by code fails until the table exists.
--
-- Safe either way — every statement here is a no-op when the table is present.
-- ---------------------------------------------------------------------------
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

alter table public.join_attempts enable row level security;

drop policy if exists join_attempts_select on public.join_attempts;
create policy join_attempts_select on public.join_attempts
  for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Now clear the data.
-- ---------------------------------------------------------------------------
begin;

-- profiles is deliberately absent from this list.
--
-- Rows in it are written by handle_new_user(), a trigger that fires once when
-- an account is created in auth.users. Nothing re-creates them. Truncating it
-- would leave every existing account able to sign in but with no profile row,
-- so their name and avatar would vanish, foreign keys pointing at them would
-- have nothing to resolve, and the only repair would be deleting the auth
-- users and signing up again.
--
-- To clear profiles too, delete the accounts from Authentication → Users in
-- the dashboard; the cascade from auth.users removes the profile with them.
--
-- One statement, so the foreign keys between these tables are all satisfied at
-- the same instant. `cascade` follows references into anything not named here,
-- and `restart identity` resets the bigserial counters on join_attempts and
-- task_activity so ids start from 1 again rather than continuing.
truncate table
  public.workspaces,
  public.workspace_members,
  public.workspace_invites,
  public.join_attempts,
  public.boards,
  public.board_status_labels,
  public.board_columns,
  public.board_views,
  public.task_groups,
  public.tasks,
  public.task_assignees,
  public.task_column_values,
  public.task_comments,
  public.task_comment_reactions,
  public.task_comment_mentions,
  public.task_activity,
  public.notifications
restart identity cascade;

commit;

-- ---------------------------------------------------------------------------
-- Verify: every count is 0, and profiles still holds your accounts.
--
-- Read from the catalog rather than naming each table in a union. The union
-- version failed outright on a database missing one table — reporting nothing
-- at all about the seventeen that were fine — which is how the missing
-- join_attempts stayed hidden until it broke this script.
-- ---------------------------------------------------------------------------
select
  c.relname                                   as table_name,
  (xpath(
    '/row/c/text()',
    query_to_xml(
      format('select count(*) as c from public.%I', c.relname),
      false, true, ''
    )
  ))[1]::text::bigint                         as rows,
  case when c.relname = 'profiles' then 'kept on purpose' else '' end as note
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
order by c.relname;
