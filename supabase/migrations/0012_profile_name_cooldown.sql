-- 0012 — Changing your display name, at most once a week
--
-- Run after 0011. Safe to re-run.
--
-- A name is how teammates recognise each other across every board, comment and
-- mention in the workspace. Someone changing it hourly makes the history
-- unreadable — a comment from March is suddenly attributed to a name nobody
-- recognises — so a change is allowed and then rate limited.
--
-- Seven days, enforced here rather than in the client. The client also hides
-- the button while the cooldown runs, but that is a courtesy: the check that
-- decides is this one, because anyone can call the API directly.

-- ---------------------------------------------------------------------------
-- When the name last changed
--
-- Null means never changed since signup, which does not count against the
-- cooldown: the first change is always allowed.
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists name_changed_at timestamptz;

-- ---------------------------------------------------------------------------
-- The cooldown itself
--
-- A trigger, not a policy: RLS can only say yes or no to the whole row, and
-- this has to allow an update that leaves the name alone (avatar_url, or the
-- name being set to what it already is) while refusing one that changes it too
-- soon. It also stamps name_changed_at itself, so the column cannot be
-- back-dated by the client to buy another change.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_name_cooldown()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cooldown constant interval := interval '7 days';
  next_allowed timestamptz;
begin
  -- Untouched, or set to the same thing: nothing to rate limit, and the stamp
  -- must not move — otherwise saving the form without editing the name would
  -- silently start a new seven days.
  if new.full_name is not distinct from old.full_name then
    new.name_changed_at := old.name_changed_at;
    return new;
  end if;

  -- Trimmed and length-checked here too, so the rule holds for a direct API
  -- call and not only for clients that remember to validate.
  new.full_name := btrim(new.full_name);
  if char_length(new.full_name) = 0 then
    raise exception 'Your name cannot be empty.'
      using errcode = 'check_violation';
  end if;

  if old.name_changed_at is not null then
    next_allowed := old.name_changed_at + cooldown;
    if now() < next_allowed then
      raise exception 'You can change your name again on %.',
        to_char(next_allowed at time zone 'UTC', 'FMDay, FMDD FMMonth YYYY')
        using errcode = 'check_violation';
    end if;
  end if;

  new.name_changed_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_name_cooldown on public.profiles;
create trigger profiles_name_cooldown
  before update of full_name on public.profiles
  for each row execute function public.enforce_name_cooldown();

-- ---------------------------------------------------------------------------
-- What the client needs to render the form
--
-- Returns when the next change is allowed, so the UI can disable the field and
-- say why rather than letting someone type a new name and only then be told no.
-- ---------------------------------------------------------------------------

create or replace function public.my_name_change_status()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'name_changed_at', p.name_changed_at,
    'next_allowed_at', case
      when p.name_changed_at is null then null
      else p.name_changed_at + interval '7 days'
    end,
    'can_change_now', (
      p.name_changed_at is null
      or now() >= p.name_changed_at + interval '7 days'
    )
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

grant execute on function public.my_name_change_status() to authenticated;

-- The column needs no separate grant juggling to be safe: the trigger assigns
-- new.name_changed_at on every path before the row is written, so whatever a
-- client sends for it is overwritten. There is no value it can pass that
-- lifts its own cooldown.
