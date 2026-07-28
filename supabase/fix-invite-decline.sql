-- Fix: 42703 "column workspace_invites.declined_at does not exist"
--
-- Adds the column the decline flow needs, and lets realtime carry invite
-- changes so the notification bell updates without restarting the app.
--
-- Why a column rather than deleting the row: the delete policy on
-- workspace_invites requires membership of that workspace, which the invited
-- person does not have yet — so they cannot delete their own invitation. The
-- update policy does let them act on a row addressed to their email, so
-- declining marks a timestamp instead. It also leaves the inviter able to see
-- that the invitation was turned down, rather than the row silently vanishing.
--
-- Run this in the Supabase SQL Editor. Safe to run more than once.

alter table public.workspace_invites
  add column if not exists declined_at timestamptz;

-- A declined invitation must not be silently re-claimed the next time the
-- person signs in.
create or replace function public.accept_pending_invites()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed int;
begin
  with pending as (
    select id, workspace_id, role
    from public.workspace_invites
    where lower(email) = lower(auth.jwt()->>'email')
      and accepted_at is null
      and declined_at is null
  ), inserted as (
    insert into public.workspace_members (workspace_id, user_id, role)
    select workspace_id, auth.uid(), role from pending
    on conflict (workspace_id, user_id) do nothing
    returning workspace_id
  )
  update public.workspace_invites
  set accepted_at = now()
  where id in (select id from pending);

  get diagnostics claimed = row_count;
  return claimed;
end;
$$;

-- Publish invites so the bell updates live rather than only on restart.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  begin
    alter publication supabase_realtime add table public.workspace_invites;
  exception
    when duplicate_object then null;  -- already published
  end;
end
$$;

alter table public.workspace_invites replica identity full;

notify pgrst, 'reload schema';

-- Confirm: one row, showing the new column.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'workspace_invites'
  and column_name = 'declined_at';
