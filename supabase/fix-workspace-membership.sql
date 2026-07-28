-- Fix: "You do not have permission to do that in this workspace" / "0 members"
--
-- Symptom: you are signed in and your workspace appears in the sidebar, but it
-- shows 0 members and every action is refused.
--
-- Cause: the workspace row exists without a matching workspace_members row for
-- its owner. Row level security grants access through membership, not
-- ownership, so an owner with no membership row can see the workspace name but
-- cannot read or write anything inside it.
--
-- This happens to workspaces created before the on_workspace_created trigger
-- existed — i.e. if you ran an earlier version of schema.sql.
--
-- Run this in the Supabase SQL Editor. It is safe to run more than once.
--
-- (schema.sql now contains the same repair, so running the full file works
-- too — this exists so you do not have to.)

insert into public.workspace_members (workspace_id, user_id, role)
select w.id, w.owner_id, 'owner'
from public.workspaces w
where not exists (
  select 1 from public.workspace_members m
  where m.workspace_id = w.id
    and m.user_id = w.owner_id
)
on conflict do nothing;

-- Confirm the repair: every workspace should now list at least its owner.
select
  w.name                          as workspace,
  p.email                         as owner,
  count(m.user_id)                as members,
  bool_or(m.user_id = w.owner_id) as owner_is_member
from public.workspaces w
left join public.workspace_members m on m.workspace_id = w.id
left join public.profiles p on p.id = w.owner_id
group by w.id, w.name, p.email, w.owner_id
order by w.name;
