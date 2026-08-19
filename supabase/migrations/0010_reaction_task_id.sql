-- ---------------------------------------------------------------------------
-- 0010 — Scope reaction events to their task
--
-- task_comment_reactions carries comment_id, not task_id, so an open chat had
-- to subscribe to *every* reaction in the database and reload on each one.
-- At a handful of users that is invisible. At a hundred it means every thumbs
-- up anyone gives, anywhere, re-fetches every open conversation.
--
-- Denormalising task_id onto the row makes the subscription filterable
-- server-side, the same way task_comments already is. The trigger fills it in,
-- so nothing client-side has to be trusted to set it correctly.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

alter table public.task_comment_reactions
  add column if not exists task_id uuid references public.tasks(id) on delete cascade;

-- Backfill anything already there.
update public.task_comment_reactions r
set task_id = c.task_id
from public.task_comments c
where r.comment_id = c.id
  and r.task_id is distinct from c.task_id;

-- Filled from the comment rather than taken from the client: a reaction that
-- claimed the wrong task would deliver itself to the wrong subscribers.
create or replace function public.set_reaction_task_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select c.task_id into new.task_id
  from public.task_comments c
  where c.id = new.comment_id;
  return new;
end;
$$;

drop trigger if exists task_comment_reactions_task_id on public.task_comment_reactions;
create trigger task_comment_reactions_task_id
  before insert or update of comment_id on public.task_comment_reactions
  for each row execute function public.set_reaction_task_id();

-- The chat loads reactions for a set of comment ids; this serves that as well
-- as the realtime filter.
create index if not exists task_comment_reactions_task_idx
  on public.task_comment_reactions(task_id);
