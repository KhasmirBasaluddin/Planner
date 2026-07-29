-- 0006 — Seed
--
-- Run last.
--
-- 0001 dropped public.profiles, but auth.users survived, so every existing
-- account currently has no profile row. Without one they cannot be assigned a
-- task, appear in the members list, or author a note — every one of those is a
-- foreign key into profiles.
--
-- The handle_new_user trigger only fires on *new* signups, so existing accounts
-- are backfilled here.

insert into public.profiles (id, email, full_name)
select
  u.id,
  u.email,
  left(
    coalesce(
      nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
      split_part(u.email, '@', 1)
    ),
    60
  )
from auth.users u
where u.email is not null
on conflict (id) do nothing;

-- PostgREST caches the schema. Without this the new tables and relationships
-- are invisible to the API until the next restart, which surfaces as
-- "Could not find the table 'public.tasks' in the schema cache".
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verification
--
-- Every row should read "ok". Anything else names what is missing.
--
-- The counts are not all the same number, and that is correct:
--   18 tables and 18 with RLS — every table is protected
--   15 published to realtime — task_activity is deliberately excluded, being
--      append-only history nobody watches live
--   profiles must equal auth.users, or someone cannot be assigned work
-- ---------------------------------------------------------------------------
with expected as (
  select unnest(array[
    'profiles', 'workspaces', 'workspace_members', 'workspace_invites',
    'boards', 'board_status_labels', 'board_columns', 'board_views',
    'task_groups', 'tasks', 'task_assignees', 'task_column_values',
    'task_comments', 'task_comment_reactions', 'task_comment_mentions',
    'task_activity',
    'notifications', 'join_attempts'
  ]) as tablename
),
actual as (
  select tablename, rowsecurity
  from pg_tables where schemaname = 'public'
)
select 'tables' as check,
       count(*)::text || ' / 18' as result,
       case when count(*) = 18 then 'ok'
            else 'MISSING: ' || string_agg(e.tablename, ', ')
                 filter (where a.tablename is null)
       end as status
from expected e left join actual a using (tablename)
where a.tablename is not null

union all
select 'rls enabled',
       count(*)::text || ' / 18',
       case when count(*) = 18 then 'ok'
            else 'UNPROTECTED: ' || coalesce(string_agg(e.tablename, ', ')
                 filter (where not coalesce(a.rowsecurity, false)), '?')
       end
from expected e left join actual a using (tablename)
where coalesce(a.rowsecurity, false)

union all
select 'profiles match accounts',
       (select count(*) from public.profiles)::text || ' / ' ||
       (select count(*) from auth.users where email is not null)::text,
       case when (select count(*) from public.profiles)
               = (select count(*) from auth.users where email is not null)
            then 'ok' else 'BACKFILL INCOMPLETE' end

union all
select 'realtime published',
       count(*)::text || ' / 15',
       case when count(*) = 15 then 'ok'
            else 'expected 15 — see 0005' end
from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'

union all
select 'policies',
       count(*)::text || ' / 50',
       case when count(*) = 50 then 'ok' else 'expected 50 — re-run 0004' end
from pg_policies where schemaname = 'public'

union all
select 'triggers',
       count(*)::text || ' / 36',
       case when count(*) = 36 then 'ok' else 'expected 36 — re-run 0003' end
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal
  and (n.nspname = 'public' or t.tgname = 'on_auth_user_created');
