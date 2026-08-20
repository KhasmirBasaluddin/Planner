-- 0011 — Joining settles the invitation
--
-- Run after 0010. Safe to re-run.
--
-- Someone could be invited and, instead of answering, join with the workspace
-- code. That inserted the membership and left the invitation exactly as it
-- was: still pending, still unanswered. So the admin's members dialog listed
-- them under "Pending invitations" while they were sitting in the members list
-- directly above it, and the invitee's own notification still read "X invited
-- you to …" for a workspace they were already working in.
--
-- Membership is the thing the invitation was asking about, so membership is
-- what settles it — regardless of which route was taken to get there. A
-- trigger on workspace_members covers every one of them: the code, the
-- invitation, and any future path, without each having to remember to tidy up
-- after itself.

-- ---------------------------------------------------------------------------
-- Settle on join
-- ---------------------------------------------------------------------------

create or replace function public.settle_invites_on_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Marked accepted rather than deleted: the row is the record that the
  -- invitation existed and how it ended, which the admin's list relies on.
  --
  -- The accepted_at update fires settle_invite_notification, so the stale
  -- "you have been invited" in the bell is rewritten to "You joined …" by the
  -- trigger that already owns that wording.
  update public.workspace_invites
  set accepted_at = now()
  where workspace_id = new.workspace_id
    and accepted_at is null
    and declined_at is null
    and (
      invitee_id = new.user_id
      or lower(email) = lower((
        select email from public.profiles where id = new.user_id
      ))
    );

  return new;
end;
$$;

drop trigger if exists workspace_members_settle_invites on public.workspace_members;
create trigger workspace_members_settle_invites
  after insert on public.workspace_members
  for each row execute function public.settle_invites_on_join();

-- ---------------------------------------------------------------------------
-- Backfill
--
-- Invitations already stranded by a join that happened before the trigger
-- existed. Without this the fix only helps future joins, and every workspace
-- carrying one of these keeps showing it.
-- ---------------------------------------------------------------------------

update public.workspace_invites i
set accepted_at = now()
where i.accepted_at is null
  and i.declined_at is null
  and exists (
    select 1
    from public.workspace_members m
    left join public.profiles p on p.id = m.user_id
    where m.workspace_id = i.workspace_id
      and (
        m.user_id = i.invitee_id
        or lower(p.email) = lower(i.email)
      )
  );
