-- Fix: PGRST200 "Could not find a relationship between 'workspace_members'
-- and 'profiles' in the schema cache"
--
-- Symptom: the members list is always empty and the invite dialog shows the
-- error above.
--
-- Cause: the app asks PostgREST to embed the related profile —
-- `select('role, profiles(...)')`. PostgREST can only do that when a foreign
-- key connects the two tables. `workspace_members.user_id` references
-- `auth.users`, which lives in a different schema that PostgREST does not
-- expose, so there is no path to `public.profiles`.
--
-- Adding a second foreign key to profiles gives it that path. Both columns
-- point at the same id, so this is a constraint rather than duplicated data.
--
-- Run this in the Supabase SQL Editor. Safe to run more than once.
-- (schema.sql now contains the same fix; this exists so you do not have to
-- re-run the whole file.)

-- Any membership rows whose user has no profile row would block the constraint,
-- so backfill those first from auth.users.
insert into public.profiles (id, email, full_name)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1))
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'workspace_members_profile_fkey'
  ) then
    alter table public.workspace_members
      add constraint workspace_members_profile_fkey
      foreign key (user_id) references public.profiles(id) on delete cascade;
  end if;

  -- Task notes embed the author's and editor's profile for the same reason.
  if not exists (
    select 1 from pg_constraint where conname = 'task_notes_author_id_fkey'
  ) then
    alter table public.task_notes
      add constraint task_notes_author_id_fkey
      foreign key (author_id) references public.profiles(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'task_notes_edited_by_fkey'
  ) then
    alter table public.task_notes
      add constraint task_notes_edited_by_fkey
      foreign key (edited_by) references public.profiles(id) on delete set null;
  end if;
end
$$;

-- PostgREST caches the schema; without this the new relationship is not visible
-- until the next restart.
notify pgrst, 'reload schema';

-- Confirm: three rows, one per constraint.
select conname as constraint_name, conrelid::regclass::text as on_table
from pg_constraint
where conname in (
  'workspace_members_profile_fkey',
  'task_notes_author_id_fkey',
  'task_notes_edited_by_fkey'
);
