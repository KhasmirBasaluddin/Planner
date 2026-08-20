-- Verify that migrations 0011 through 0014 actually landed.
--
-- Paste into the Supabase SQL editor and run. Read-only — it changes nothing.
--
-- Worth running even when the migrations reported success. The DB half of 0013
-- can apply while the storage half does not: creating a bucket and policies on
-- storage.objects needs privileges the table work does not, so a partial
-- result looks like a clean run right up until the first attachment upload.
--
-- Every row should read PASS.
--
-- `detail`, not `check`: CHECK is a reserved word in Postgres and cannot be a
-- bare column alias.

with checks as (

  -- === 0011 — joining settles the invitation ===

  select '0011' as migration,
         'settle_invites_on_join() exists' as detail,
         exists (
           select 1 from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'settle_invites_on_join'
         ) as ok
  union all
  select '0011', 'trigger on workspace_members',
         exists (
           select 1 from pg_trigger
           where tgname = 'workspace_members_settle_invites'
             and not tgisinternal
         )

  -- === 0012 — name change cooldown ===

  union all
  select '0012', 'profiles.name_changed_at column',
         exists (
           select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'profiles'
             and column_name = 'name_changed_at'
         )
  union all
  select '0012', 'cooldown trigger on profiles',
         exists (
           select 1 from pg_trigger
           where tgname = 'profiles_name_cooldown' and not tgisinternal
         )
  union all
  select '0012', 'my_name_change_status() exists',
         exists (
           select 1 from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'my_name_change_status'
         )

  -- === 0013 — notes, attachments, storage ===

  union all
  select '0013', 'task_note_kind enum',
         exists (select 1 from pg_type where typname = 'task_note_kind')
  union all
  select '0013', 'task_notes table',
         to_regclass('public.task_notes') is not null
  union all
  select '0013', 'task_note_attachments table',
         to_regclass('public.task_note_attachments') is not null
  union all
  select '0013', 'RLS on task_notes',
         coalesce(
           (select relrowsecurity from pg_class
            where oid = to_regclass('public.task_notes')), false)
  union all
  select '0013', 'verdicts restricted to admins (insert policy)',
         exists (
           select 1 from pg_policies
           where schemaname = 'public' and tablename = 'task_notes'
             and policyname = 'task_notes_insert'
             and with_check like '%can_manage_workspace%'
         )
  union all
  -- The half most likely to be missing.
  select '0013', 'task-attachments STORAGE BUCKET',
         exists (select 1 from storage.buckets where id = 'task-attachments')
  union all
  select '0013', 'bucket is private',
         coalesce(
           (select not public from storage.buckets
            where id = 'task-attachments'), false)
  union all
  select '0013', 'storage read policy',
         exists (
           select 1 from pg_policies
           where schemaname = 'storage' and tablename = 'objects'
             and policyname = 'task_attachments_read'
         )
  union all
  select '0013', 'storage write policy',
         exists (
           select 1 from pg_policies
           where schemaname = 'storage' and tablename = 'objects'
             and policyname = 'task_attachments_write'
         )
  union all
  select '0013', 'notes are published to realtime',
         exists (
           select 1 from pg_publication_tables
           where pubname = 'supabase_realtime'
             and schemaname = 'public' and tablename = 'task_notes'
         )
  union all
  select '0013', 'attachments are published to realtime',
         exists (
           select 1 from pg_publication_tables
           where pubname = 'supabase_realtime'
             and schemaname = 'public' and tablename = 'task_note_attachments'
         )

  -- === 0014 — status actor, note count, delete rules ===

  union all
  select '0014', 'tasks.status_by column',
         exists (
           select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'tasks'
             and column_name = 'status_by'
         )
  union all
  select '0014', 'tasks.status_at column',
         exists (
           select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'tasks'
             and column_name = 'status_at'
         )
  union all
  select '0014', 'tasks.note_count column',
         exists (
           select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'tasks'
             and column_name = 'note_count'
         )
  union all
  select '0014', 'status actor trigger',
         exists (
           select 1 from pg_trigger
           where tgname = 'tasks_5_touch_status_actor' and not tgisinternal
         )
  union all
  select '0014', 'note count trigger',
         exists (
           select 1 from pg_trigger
           where tgname = 'task_notes_count' and not tgisinternal
         )
  union all
  -- The whole point of the delete change: a member must not be able to
  -- destroy a task outright.
  select '0014', 'hard delete needs admin (tasks)',
         exists (
           select 1 from pg_policies
           where schemaname = 'public' and tablename = 'tasks'
             and policyname = 'tasks_delete'
             and qual like '%can_manage_workspace%'
         )
  union all
  select '0014', 'hard delete needs admin (boards)',
         exists (
           select 1 from pg_policies
           where schemaname = 'public' and tablename = 'boards'
             and policyname = 'boards_delete'
             and qual like '%can_manage_workspace%'
         )
  union all
  select '0014', 'hard delete needs admin (groups)',
         exists (
           select 1 from pg_policies
           where schemaname = 'public' and tablename = 'task_groups'
             and policyname = 'groups_delete'
             and qual like '%can_manage_workspace%'
         )
  union all
  -- Without this the client never sees the new columns, however well the
  -- table changes applied.
  select '0014', 'board_tree returns note_count',
         (select prosrc from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'board_tree'
          limit 1) like '%note_count%'
  union all
  select '0014', 'board_tree returns status_by',
         (select prosrc from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'board_tree'
          limit 1) like '%status_by%'
  union all
  select '0014', 'restore() pulls back the parent board',
         (select prosrc from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'restore'
          limit 1) like '%parent.board_id%'
)

select
  migration,
  case when ok then 'PASS' else 'FAIL  <<<<' end as result,
  detail
from checks
order by migration, ok, detail;
