-- 0003 — Functions, triggers and RPCs
--
-- Run after 0002.
--
-- Three groups:
--   1. access helpers used by every policy in 0004
--   2. triggers that keep denormalized columns honest
--   3. RPCs the client calls directly

-- ===========================================================================
-- 1. Access helpers
--
-- SECURITY DEFINER so the function reads workspace_members without
-- re-triggering that table's own policy. Without it, a policy on
-- workspace_members that queries workspace_members recurses forever.
--
-- STABLE so Postgres evaluates once per statement rather than once per row.
-- ===========================================================================
create or replace function public.is_workspace_member(target_workspace uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace and user_id = auth.uid()
  );
$$;

-- Owner, admin and member can write. Viewer is read-only.
create or replace function public.can_edit_workspace(target_workspace uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace
      and user_id = auth.uid()
      and role in ('owner', 'admin', 'member')
  );
$$;

-- Managing people and rotating the join code.
create or replace function public.can_manage_workspace(target_workspace uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace
      and user_id = auth.uid()
      and role in ('owner', 'admin')
  );
$$;

-- ===========================================================================
-- 2. Triggers
-- ===========================================================================

-- Keep profiles in sync with auth.users.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    left(
      coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
      60
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Supabase Auth "Before User Created" hook. Enable it under
-- Authentication -> Hooks. Rejects non-company signups before an auth.users
-- row exists.
create or replace function public.hook_allow_vintazk_email(event jsonb)
returns jsonb
language plpgsql
as $$
declare
  email     text := lower(trim(event->'user'->>'email'));
  full_name text := trim(coalesce(event->'user'->'user_metadata'->>'full_name', ''));
begin
  if email !~ '^[^@]+@vintazk\.com$' then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Only @vintazk.com email addresses are allowed.'
    ));
  end if;

  if char_length(full_name) > 60 then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 400,
      'message', 'Full name must be 60 characters or fewer.'
    ));
  end if;

  return '{}'::jsonb;
end;
$$;

grant execute on function public.hook_allow_vintazk_email(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_allow_vintazk_email(jsonb) from authenticated, anon, public;

-- --- updated_at -----------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch      before update on public.profiles
  for each row execute function public.touch_updated_at();
drop trigger if exists workspaces_touch on public.workspaces;
create trigger workspaces_touch    before update on public.workspaces
  for each row execute function public.touch_updated_at();
drop trigger if exists boards_touch on public.boards;
create trigger boards_touch        before update on public.boards
  for each row execute function public.touch_updated_at();
drop trigger if exists board_columns_touch on public.board_columns;
create trigger board_columns_touch before update on public.board_columns
  for each row execute function public.touch_updated_at();
drop trigger if exists board_views_touch on public.board_views;
create trigger board_views_touch   before update on public.board_views
  for each row execute function public.touch_updated_at();
drop trigger if exists task_groups_touch on public.task_groups;
create trigger task_groups_touch   before update on public.task_groups
  for each row execute function public.touch_updated_at();
drop trigger if exists tasks_touch on public.tasks;
create trigger tasks_touch         before update on public.tasks
  for each row execute function public.touch_updated_at();
drop trigger if exists task_comments_touch on public.task_comments;
create trigger task_comments_touch before update on public.task_comments
  for each row execute function public.touch_updated_at();

-- --- join codes -----------------------------------------------------------

-- A join code, in the form PLNR-XXXX-XXXX.
--
-- Two things matter here, and the first version got both wrong.
--
-- LENGTH. Four characters over a 32-symbol alphabet is about a million codes.
-- join_workspace_with_code() is SECURITY DEFINER and answers anyone, so an
-- attacker can simply try them; at ten guesses a second that space falls in
-- roughly a day, and every workspace that exists gives each guess another
-- chance to land. Eight characters raises it to a trillion, which is not worth
-- anyone's time — and the rate limit below closes the door regardless.
--
-- RANDOMNESS. random() is a seeded PRNG, not a secret one: its output is
-- reproducible from its state, so codes drawn from it are related to each
-- other. gen_random_bytes() comes from pgcrypto and is drawn from the system's
-- cryptographic source.
--
-- The alphabet stays unambiguous — no O/0 or I/1 — because these get read
-- aloud and typed by hand, and the grouping into fours is for the same reason.
create extension if not exists pgcrypto;

create or replace function public.generate_join_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes    bytea := gen_random_bytes(8);
  result   text := '';
  i        int;
begin
  for i in 0..7 loop
    -- One byte per character, folded into the alphabet. 256 does not divide
    -- evenly by 32, but it is a whole multiple of it, so the fold stays
    -- uniform.
    result := result || substr(
      alphabet, (get_byte(bytes, i) % length(alphabet)) + 1, 1
    );
    if i = 3 then
      result := result || '-';
    end if;
  end loop;
  return 'PLNR-' || result;
end;
$$;

create or replace function public.assign_join_code()
returns trigger
language plpgsql
as $$
declare
  candidate text;
  attempts  int := 0;
begin
  if new.join_code is not null then
    return new;
  end if;
  loop
    candidate := public.generate_join_code();
    exit when not exists (select 1 from public.workspaces where join_code = candidate);
    attempts := attempts + 1;
    if attempts > 20 then
      -- Fall back to a longer code rather than looping forever.
      candidate := candidate || substr(md5(random()::text), 1, 4);
      exit;
    end if;
  end loop;
  new.join_code := candidate;
  return new;
end;
$$;

drop trigger if exists on_workspace_join_code on public.workspaces;
create trigger on_workspace_join_code
  before insert on public.workspaces
  for each row execute function public.assign_join_code();

-- --- workspace_id denormalization ----------------------------------------
--
-- Every table carries workspace_id so RLS reads it off the row instead of
-- walking task -> group -> board on every check. These triggers derive it from
-- the parent, so the client cannot set it wrong and moving a task between
-- boards cannot desynchronize it.

create or replace function public.derive_task_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent record;
begin
  select g.board_id, g.workspace_id into parent
  from public.task_groups g
  where g.id = new.group_id;

  if not found then
    raise exception 'Group % does not exist.', new.group_id;
  end if;

  new.board_id     := parent.board_id;
  new.workspace_id := parent.workspace_id;
  return new;
end;
$$;

-- Numbered, because Postgres fires same-timing triggers in *alphabetical*
-- order and these three have to run in a specific one:
--
--   1 derive   fills board_id and workspace_id from the group
--   2 default  picks the board's default status, needing board_id
--   3 check    rejects a status from another board, needing board_id
--
-- Named tasks_check_status / tasks_default_status / tasks_derive_workspace,
-- the check ran first and compared against a board_id that was still null,
-- so every insert failed with "Status ... does not belong to board <NULL>".
-- The prefix makes the dependency visible instead of leaving it to chance.
drop trigger if exists tasks_derive_workspace on public.tasks;
drop trigger if exists tasks_1_derive_workspace on public.tasks;
create trigger tasks_1_derive_workspace
  before insert or update of group_id on public.tasks
  for each row execute function public.derive_task_workspace();

create or replace function public.derive_group_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select b.workspace_id into new.workspace_id
  from public.boards b where b.id = new.board_id;

  if new.workspace_id is null then
    raise exception 'Board % does not exist.', new.board_id;
  end if;
  return new;
end;
$$;

drop trigger if exists task_groups_derive_workspace on public.task_groups;
create trigger task_groups_derive_workspace
  before insert or update of board_id on public.task_groups
  for each row execute function public.derive_group_workspace();

-- Same derivation for the board-scoped tables.
create or replace function public.derive_board_child_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select b.workspace_id into new.workspace_id
  from public.boards b where b.id = new.board_id;

  if new.workspace_id is null then
    raise exception 'Board % does not exist.', new.board_id;
  end if;
  return new;
end;
$$;

drop trigger if exists board_columns_derive_workspace on public.board_columns;
create trigger board_columns_derive_workspace
  before insert or update of board_id on public.board_columns
  for each row execute function public.derive_board_child_workspace();

drop trigger if exists board_views_derive_workspace on public.board_views;
create trigger board_views_derive_workspace
  before insert or update of board_id on public.board_views
  for each row execute function public.derive_board_child_workspace();

-- …and for the task-scoped ones.
create or replace function public.derive_task_child_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select t.workspace_id into new.workspace_id
  from public.tasks t where t.id = new.task_id;

  if new.workspace_id is null then
    raise exception 'Task % does not exist.', new.task_id;
  end if;
  return new;
end;
$$;

drop trigger if exists task_assignees_derive_workspace on public.task_assignees;
create trigger task_assignees_derive_workspace
  before insert on public.task_assignees
  for each row execute function public.derive_task_child_workspace();

drop trigger if exists task_column_values_derive_workspace on public.task_column_values;
create trigger task_column_values_derive_workspace
  before insert on public.task_column_values
  for each row execute function public.derive_task_child_workspace();

drop trigger if exists task_comments_derive_workspace on public.task_comments;
create trigger task_comments_derive_workspace
  before insert on public.task_comments
  for each row execute function public.derive_task_child_workspace();

drop trigger if exists task_activity_derive_workspace on public.task_activity;
create trigger task_activity_derive_workspace
  before insert on public.task_activity
  for each row execute function public.derive_task_child_workspace();

-- Reactions and mentions hang off a comment, not a task.
create or replace function public.derive_reaction_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select c.workspace_id into new.workspace_id
  from public.task_comments c where c.id = new.comment_id;

  if new.workspace_id is null then
    raise exception 'Comment % does not exist.', new.comment_id;
  end if;
  return new;
end;
$$;

drop trigger if exists task_comment_reactions_derive_workspace on public.task_comment_reactions;
create trigger task_comment_reactions_derive_workspace
  before insert on public.task_comment_reactions
  for each row execute function public.derive_reaction_workspace();

drop trigger if exists task_comment_mentions_derive_workspace on public.task_comment_mentions;
create trigger task_comment_mentions_derive_workspace
  before insert on public.task_comment_mentions
  for each row execute function public.derive_reaction_workspace();

-- --- status label belongs to the task's board -----------------------------
--
-- A plain foreign key can say "this status exists"; it cannot say "this status
-- belongs to *this* board". Without the check, a task on board A could carry
-- board B's status.
create or replace function public.check_status_board()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  label_board uuid;
begin
  if new.status_id is null then
    return new;
  end if;

  select board_id into label_board
  from public.board_status_labels where id = new.status_id;

  if label_board is distinct from new.board_id then
    raise exception 'Status % does not belong to board %.', new.status_id, new.board_id;
  end if;
  return new;
end;
$$;

-- Numbered 3: runs last, once board_id and the default status are both set.
drop trigger if exists tasks_check_status on public.tasks;
drop trigger if exists tasks_3_check_status on public.tasks;
create trigger tasks_3_check_status
  before insert or update of status_id, board_id on public.tasks
  for each row execute function public.check_status_board();

-- --- comment_count --------------------------------------------------------
--
-- Maintained here so the badge costs no query. Soft deletes mean an UPDATE can
-- change the count too, hence the three-way branch.
--
-- Counts replies as well as top-level messages.
--
-- It used to count only top-level ones, on the reasoning that a reply belongs
-- to its parent thread. But the chat header says "3 messages" — counting every
-- message, because that is what a person means by the word — so the badge read
-- 2 beside a panel headed 3. Two numbers for one thing, disagreeing.
create or replace function public.sync_task_comment_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.deleted_at is null then
      update public.tasks set comment_count = comment_count + 1
      where id = new.task_id;
    end if;

  elsif tg_op = 'DELETE' then
    if old.deleted_at is null then
      update public.tasks set comment_count = greatest(comment_count - 1, 0)
      where id = old.task_id;
    end if;

  elsif old.deleted_at is null and new.deleted_at is not null then
    update public.tasks set comment_count = greatest(comment_count - 1, 0)
    where id = new.task_id;

  elsif old.deleted_at is not null and new.deleted_at is null then
    update public.tasks set comment_count = comment_count + 1
    where id = new.task_id;
  end if;

  return null;  -- AFTER trigger; return value is ignored
end;
$$;

drop trigger if exists task_comments_sync_count on public.task_comments;
create trigger task_comments_sync_count
  after insert or update of deleted_at or delete on public.task_comments
  for each row execute function public.sync_task_comment_count();

-- Recomputes every task's count from the messages that actually exist.
--
-- Run after changing what the trigger counts, or if a count is ever suspected
-- of having drifted. Cheap enough to run on the whole table.
create or replace function public.resync_comment_counts()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  fixed int;
begin
  with actual as (
    select t.id, count(c.id) as n
    from public.tasks t
    left join public.task_comments c
      on c.task_id = t.id and c.deleted_at is null
    group by t.id
  )
  update public.tasks t
  set comment_count = actual.n
  from actual
  where t.id = actual.id and t.comment_count <> actual.n;

  get diagnostics fixed = row_count;
  return fixed;
end;
$$;

-- --- workspace bootstrap --------------------------------------------------
--
-- Creating a workspace enrols the creator as owner and gives them a starter
-- board, so nobody lands on an empty screen.
create or replace function public.handle_new_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_board uuid;
begin
  insert into public.workspace_members (workspace_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict do nothing;

  insert into public.boards (workspace_id, name, color, position, created_by)
  values (new.id, 'My first board', new.color, 0, new.owner_id)
  returning id into new_board;

  -- create_default_statuses fires on that insert, so the group's tasks have
  -- labels to point at.
  insert into public.task_groups (board_id, name, color, position)
  values (new_board, 'To do', new.color, 0);

  return new;
end;
$$;

drop trigger if exists on_workspace_created on public.workspaces;
create trigger on_workspace_created
  after insert on public.workspaces
  for each row execute function public.handle_new_workspace();

-- Every board starts with a usable set of labels. Teams rename them; the app
-- never has to special-case a board with no statuses.
create or replace function public.create_default_statuses()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.board_status_labels (board_id, name, color, position, is_done, is_default)
  values
    (new.id, 'Not started', 4290624957, 0, false, true),
    (new.id, 'Working on it', 4294951175, 1, false, false),
    (new.id, 'Stuck',        4293215557, 2, false, false),
    (new.id, 'Done',         4278233185, 3, true,  false);
  return new;
end;
$$;

drop trigger if exists boards_default_statuses on public.boards;
create trigger boards_default_statuses
  after insert on public.boards
  for each row execute function public.create_default_statuses();

-- New tasks get the board's default status when the client does not name one.
create or replace function public.apply_default_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status_id is null then
    select id into new.status_id
    from public.board_status_labels
    where board_id = new.board_id and is_default
    limit 1;
  end if;
  return new;
end;
$$;

-- Numbered 2: after derive has set board_id, before check validates it.
drop trigger if exists tasks_default_status on public.tasks;
drop trigger if exists tasks_2_default_status on public.tasks;
create trigger tasks_2_default_status
  before insert on public.tasks
  for each row execute function public.apply_default_status();

-- ===========================================================================
-- 3. RPCs
-- ===========================================================================

-- --- membership -----------------------------------------------------------

-- Fills in invitee_id when the invited email already belongs to an account, so
-- an invitation is linked to the real user from the moment it is created.
create or replace function public.link_invite_to_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.invitee_id is null and new.email is not null then
    select id into new.invitee_id
    from public.profiles
    where lower(email) = lower(trim(new.email));
  end if;

  -- Carry the address across the other way too, so a picker-created invite
  -- still has something to send mail to.
  if new.email is null and new.invitee_id is not null then
    select email into new.email from public.profiles where id = new.invitee_id;
  end if;

  return new;
end;
$$;

drop trigger if exists workspace_invites_link_profile on public.workspace_invites;
create trigger workspace_invites_link_profile
  before insert or update of email, invitee_id on public.workspace_invites
  for each row execute function public.link_invite_to_profile();

-- Someone invited by email before they signed up has an invitation with a null
-- invitee_id. This claims it the moment their profile appears, so the picker
-- and the members list agree from then on.
create or replace function public.link_invites_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.workspace_invites
  set invitee_id = new.id
  where invitee_id is null and lower(email) = lower(new.email);
  return new;
end;
$$;

drop trigger if exists profiles_link_invites on public.profiles;
create trigger profiles_link_invites
  after insert on public.profiles
  for each row execute function public.link_invites_on_signup();

-- The zero-argument version from before this gained a parameter. A default
-- argument does not replace the old signature, it sits alongside it, and
-- calling accept_pending_invites() with two candidates is ambiguous.
drop function if exists public.accept_pending_invites();

-- Accepts invitations addressed to the caller, by account or by email.
--
-- `target_invite` names one invitation; null accepts every pending one, which
-- is what the "accept all" affordance in the bell uses.
--
-- This is NOT called on sign-in any more. It used to be, which meant an
-- invitation was silently converted into a membership before the person ever
-- saw it — no notification, no choice, and decline was unreachable because the
-- row was already marked accepted by the time the bell rendered.
create or replace function public.accept_pending_invites(
  target_invite uuid default null
)
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
    where (
        invitee_id = auth.uid()
        or (invitee_id is null and lower(email) = lower(auth.jwt()->>'email'))
      )
      and accepted_at is null
      and declined_at is null
      and (target_invite is null or id = target_invite)
  ), best as (
    -- One row per workspace, keeping the most generous role offered.
    --
    -- The same person can hold two open invitations to one workspace: invited
    -- by email before signing up, then again through the picker afterwards.
    -- Feeding both to the INSERT below made it try to add the same
    -- (workspace_id, user_id) twice in a single statement, which ON CONFLICT
    -- cannot resolve — it only sees rows that were already committed.
    select distinct on (workspace_id) workspace_id, role
    from pending
    order by workspace_id,
             array_position(
               array['owner','admin','member','viewer']::public.workspace_role[],
               role
             )
  ), inserted as (
    insert into public.workspace_members (workspace_id, user_id, role)
    select workspace_id, auth.uid(), role from best
    on conflict (workspace_id, user_id) do nothing
    returning workspace_id
  )
  -- Every invitation is marked answered, including the redundant ones, so they
  -- stop showing up in the bell.
  update public.workspace_invites
  set accepted_at = now()
  where id in (select id from pending);

  get diagnostics claimed = row_count;
  return claimed;
end;
$$;

-- The invitations waiting for the caller, with enough context to answer them:
-- who sent it, how big the team is, and what the workspace is called.
--
-- SECURITY DEFINER for the member count alone. Counting workspace_members
-- means reading a table the invited person has no access to — they are not a
-- member yet, which is the entire point. Only the count crosses that line; no
-- names, no rows. Everything else here they could already read.
create or replace function public.my_pending_invites()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(jsonb_agg(invite order by created_at desc), '[]'::jsonb)
  from (
    select
      i.created_at,
      jsonb_build_object(
        'id',           i.id,
        'role',         i.role,
        'created_at',   i.created_at,
        'workspace_id', w.id,
        'name',         w.name,
        'color',        w.color,
        'member_count', (
          select count(*) from public.workspace_members m
          where m.workspace_id = w.id
        ),
        'invited_by', case
          when p.id is null then null
          else jsonb_build_object(
            'id', p.id, 'email', p.email,
            'full_name', p.full_name, 'avatar_url', p.avatar_url
          )
        end
      ) as invite
    from public.workspace_invites i
    join public.workspaces w on w.id = i.workspace_id
    left join public.profiles p on p.id = i.invited_by
    where i.accepted_at is null
      and i.declined_at is null
      and (
        i.invitee_id = auth.uid()
        or (i.invitee_id is null
            and lower(i.email) = lower(auth.jwt()->>'email'))
      )
      -- Somewhere you already belong is not a decision worth offering.
      and not exists (
        select 1 from public.workspace_members m
        where m.workspace_id = w.id and m.user_id = auth.uid()
      )
  ) rows;
$$;

-- Redeems a join code.
--
-- SECURITY DEFINER by necessity: someone not yet a member cannot select the
-- workspace to look its code up, so the lookup has to bypass RLS. It only ever
-- adds the *calling* user, and only as 'member', so it cannot grant anyone
-- else access or escalate a role.
create or replace function public.join_workspace_with_code(code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  target          public.workspaces%rowtype;
  normalized      text;
  recent_failures int;
begin
  if auth.uid() is null then
    return json_build_object('ok', false, 'error', 'not_signed_in');
  end if;

  -- Accept sloppy input: lower case, stray spaces, a missing prefix, and a
  -- missing separator — someone reading a code aloud will not pause for it.
  normalized := upper(regexp_replace(coalesce(code, ''), '\s', '', 'g'));
  if position('PLNR-' in normalized) = 1 then
    normalized := substr(normalized, 6);
  end if;
  normalized := replace(normalized, '-', '');
  if char_length(normalized) = 8 then
    normalized := substr(normalized, 1, 4) || '-' || substr(normalized, 5);
  end if;
  normalized := 'PLNR-' || normalized;

  -- Guessing has to cost something, or the code's length is the only defence
  -- and a script can simply wait it out. Ten wrong attempts in an hour is far
  -- beyond mistyping a code from a chat message.
  select count(*) into recent_failures
  from public.join_attempts
  where user_id = auth.uid()
    and succeeded = false
    and attempted_at > now() - interval '1 hour';

  if recent_failures >= 10 then
    return json_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select * into target from public.workspaces where join_code = normalized;

  if not found then
    insert into public.join_attempts (user_id, succeeded) values (auth.uid(), false);
    return json_build_object('ok', false, 'error', 'not_found');
  end if;

  if exists (
    select 1 from public.workspace_members
    where workspace_id = target.id and user_id = auth.uid()
  ) then
    return json_build_object('ok', false, 'error', 'already_member', 'name', target.name);
  end if;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (target.id, auth.uid(), 'member')
  on conflict do nothing;

  -- Getting it right clears the slate, so someone who fumbled a code twice
  -- before succeeding is not left near the limit.
  delete from public.join_attempts where user_id = auth.uid();

  return json_build_object('ok', true, 'name', target.name, 'id', target.id);
end;
$$;

-- People matching a typed query, for the invite picker.
--
-- SECURITY DEFINER with a deliberately narrow contract. The profiles_select
-- policy already lets any signed-in user read any profile, so this exposes
-- nothing new — but it does three things a raw client query cannot:
--
--   * hides anyone already in the workspace, or already invited to it
--   * requires at least two characters, so nobody can enumerate the whole
--     company by searching for the empty string
--   * caps results, so a one-letter-plus query cannot dump the directory
--
-- Restricted to people who can actually manage the workspace, since only they
-- can act on the result.
create or replace function public.search_invitable_users(
  target_workspace uuid,
  query            text,
  max_results      int default 10
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  needle text := lower(trim(coalesce(query, '')));
begin
  if not public.can_manage_workspace(target_workspace) then
    raise exception 'Only owners and admins can invite people.';
  end if;

  if char_length(needle) < 2 then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(row_to_json(matched) order by matched.sort_rank, matched.full_name)
    from (
      select
        p.id,
        p.email,
        p.full_name,
        p.avatar_url,
        -- A prefix match on the name is what the user most likely meant, so it
        -- sorts above a match buried mid-string or in the address.
        case
          when lower(p.full_name) like needle || '%' then 0
          when lower(p.email)     like needle || '%' then 1
          else 2
        end as sort_rank
      from public.profiles p
      where (lower(p.full_name) like '%' || needle || '%'
             or lower(p.email)  like '%' || needle || '%')
        and not exists (
          select 1 from public.workspace_members m
          where m.workspace_id = target_workspace and m.user_id = p.id
        )
        and not exists (
          select 1 from public.workspace_invites i
          where i.workspace_id = target_workspace
            and i.invitee_id = p.id
            and i.accepted_at is null
            and i.declined_at is null
        )
      order by sort_rank, p.full_name
      limit least(greatest(max_results, 1), 25)
    ) matched
  ), '[]'::jsonb);
end;
$$;

-- Invites someone who already has an account. The email route stays available
-- for people who have not signed up yet; this is the path the picker uses.
create or replace function public.invite_user(
  target_workspace uuid,
  target_user      uuid,
  invite_role      public.workspace_role default 'member'
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  target_email text;
begin
  if not public.can_manage_workspace(target_workspace) then
    raise exception 'Only owners and admins can invite people.';
  end if;

  -- Owner is granted by creating a workspace or by transfer, never by invite.
  if invite_role = 'owner' then
    raise exception 'A workspace can only have one owner.';
  end if;

  select email into target_email from public.profiles where id = target_user;
  if target_email is null then
    return json_build_object('ok', false, 'error', 'no_such_user');
  end if;

  if exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace and user_id = target_user
  ) then
    return json_build_object('ok', false, 'error', 'already_member');
  end if;

  insert into public.workspace_invites (workspace_id, invitee_id, email, role, invited_by)
  values (target_workspace, target_user, target_email, invite_role, auth.uid())
  on conflict (workspace_id, invitee_id) where invitee_id is not null
  do update set
    role        = excluded.role,
    invited_by  = excluded.invited_by,
    -- Re-inviting someone who declined should reopen the invitation rather
    -- than leave it looking answered.
    declined_at = null,
    created_at  = now();

  return json_build_object('ok', true, 'email', target_email);
end;
$$;

create or replace function public.regenerate_join_code(target_workspace uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  fresh text;
begin
  if not public.can_manage_workspace(target_workspace) then
    raise exception 'Only owners and admins can change the join code.';
  end if;

  loop
    fresh := public.generate_join_code();
    exit when not exists (select 1 from public.workspaces where join_code = fresh);
  end loop;

  update public.workspaces set join_code = fresh where id = target_workspace;
  return fresh;
end;
$$;

-- --- ordering -------------------------------------------------------------
--
-- Positions are numeric so a row moves by taking the midpoint between its new
-- neighbours: one UPDATE, one row, whatever the board size. The old integer
-- scheme renumbered every row after the insertion point — one round trip each,
-- non-atomic, and corrupted when two people dragged at once.
create or replace function public.reorder_task(
  target_task  uuid,
  target_group uuid,
  before_task  uuid default null,
  after_task   uuid default null
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  ws            uuid;
  lower_bound   numeric;
  upper_bound   numeric;
  new_position  numeric;
begin
  select workspace_id into ws from public.tasks where id = target_task;
  if ws is null then
    raise exception 'Task % does not exist.', target_task;
  end if;
  if not public.can_edit_workspace(ws) then
    raise exception 'You do not have permission to reorder this task.';
  end if;

  select position into lower_bound from public.tasks where id = before_task;
  select position into upper_bound from public.tasks where id = after_task;

  -- Four cases: between two rows, at the top, at the bottom, or into an empty
  -- group.
  if lower_bound is not null and upper_bound is not null then
    new_position := (lower_bound + upper_bound) / 2;
  elsif lower_bound is not null then
    new_position := lower_bound + 1;
  elsif upper_bound is not null then
    new_position := upper_bound - 1;
  else
    select coalesce(max(position), 0) + 1 into new_position
    from public.tasks
    where group_id = target_group and deleted_at is null;
  end if;

  update public.tasks
  set position = new_position, group_id = target_group
  where id = target_task;

  return new_position;
end;
$$;

-- Midpoints halve the gap each time, so a long enough drag sequence exhausts
-- precision even with numeric. This resets a group to whole numbers.
create or replace function public.renormalize_task_positions(target_group uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
begin
  select workspace_id into ws from public.task_groups where id = target_group;
  if not public.can_edit_workspace(ws) then
    raise exception 'You do not have permission to reorder this group.';
  end if;

  with ordered as (
    select id, row_number() over (order by position, created_at) as rn
    from public.tasks
    where group_id = target_group and deleted_at is null
  )
  update public.tasks t
  set position = ordered.rn
  from ordered
  where t.id = ordered.id;
end;
$$;

-- --- reading --------------------------------------------------------------

-- A whole workspace's boards, groups and tasks in one round trip.
--
-- loadBoards previously ran four sequential queries and joined them in Dart,
-- and counted notes by fetching every note row. This returns the nested
-- structure already assembled, with assignees embedded.
create or replace function public.board_tree(target_workspace uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  -- Pinned boards first, then by position. Sorted on the source columns, not
  -- on the JSON: `board->>'position'` compares text, so 10 sorts before 2.
  select coalesce(
    jsonb_agg(board order by pinned desc, position), '[]'::jsonb
  )
  from (
    select b.pinned, b.position, jsonb_build_object(
      'id',       b.id,
      'name',     b.name,
      'color',    b.color,
      'position', b.position,
      'pinned',   b.pinned,
      'statuses', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', s.id, 'name', s.name, 'color', s.color,
          'position', s.position, 'is_done', s.is_done, 'is_default', s.is_default
        ) order by s.position), '[]'::jsonb)
        from public.board_status_labels s where s.board_id = b.id
      ),
      'groups', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', g.id, 'board_id', g.board_id, 'name', g.name,
          'color', g.color, 'position', g.position, 'collapsed', g.collapsed,
          'tasks', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'id', t.id, 'group_id', t.group_id, 'board_id', t.board_id,
              'title', t.title, 'status_id', t.status_id,
              'priority', t.priority, 'due_date', t.due_date,
              'start_date', t.start_date, 'end_date', t.end_date,
              'progress', t.progress, 'progress_at', t.progress_at,
              'position', t.position,
              'comment_count', t.comment_count,
              'assignee_ids', (
                select coalesce(jsonb_agg(a.user_id), '[]'::jsonb)
                from public.task_assignees a where a.task_id = t.id
              )
            ) order by t.position), '[]'::jsonb)
            from public.tasks t
            where t.group_id = g.id and t.deleted_at is null
          )
        ) order by g.position), '[]'::jsonb)
        from public.task_groups g
        where g.board_id = b.id and g.deleted_at is null
      )
    ) as board
    from public.boards b
    where b.workspace_id = target_workspace
      and b.deleted_at is null
      and public.is_workspace_member(target_workspace)
  ) boards;
$$;

-- --- soft delete ----------------------------------------------------------

create or replace function public.soft_delete(entity text, target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
begin
  -- Whitelist rather than interpolating the caller's string into the FROM
  -- clause: `entity` reaches format() as an identifier only after passing
  -- this check, so there is no path to arbitrary SQL.
  if entity not in ('boards', 'task_groups', 'tasks', 'task_comments') then
    raise exception 'Cannot soft delete %.', entity;
  end if;

  execute format('select workspace_id from public.%I where id = $1', entity)
    into ws using target_id;

  if ws is null then
    raise exception 'Row % not found in %.', target_id, entity;
  end if;
  if not public.can_edit_workspace(ws) then
    raise exception 'You do not have permission to delete this.';
  end if;

  execute format('update public.%I set deleted_at = now() where id = $1', entity)
    using target_id;
end;
$$;

create or replace function public.restore(entity text, target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
begin
  if entity not in ('boards', 'task_groups', 'tasks', 'task_comments') then
    raise exception 'Cannot restore %.', entity;
  end if;

  execute format('select workspace_id from public.%I where id = $1', entity)
    into ws using target_id;

  if ws is null then
    raise exception 'Row % not found in %.', target_id, entity;
  end if;
  if not public.can_edit_workspace(ws) then
    raise exception 'You do not have permission to restore this.';
  end if;

  execute format('update public.%I set deleted_at = null where id = $1', entity)
    using target_id;
end;
$$;

-- Everything soft-deleted in a workspace, for a recycle bin screen.
create or replace function public.deleted_items(target_workspace uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'boards', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'deleted_at', deleted_at
      ) order by deleted_at desc), '[]'::jsonb)
      from public.boards
      where workspace_id = target_workspace and deleted_at is not null
    ),
    'groups', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'board_id', board_id, 'deleted_at', deleted_at
      ) order by deleted_at desc), '[]'::jsonb)
      from public.task_groups
      where workspace_id = target_workspace and deleted_at is not null
    ),
    'tasks', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'group_id', group_id, 'deleted_at', deleted_at
      ) order by deleted_at desc), '[]'::jsonb)
      from public.tasks
      where workspace_id = target_workspace and deleted_at is not null
    )
  )
  where public.is_workspace_member(target_workspace);
$$;

-- Hard-deletes anything binned more than 30 days ago. Schedule with pg_cron,
-- or call it by hand.
create or replace function public.purge_deleted()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  cutoff  timestamptz := now() - interval '30 days';
  removed int := 0;
  n       int;
begin
  delete from public.task_comments where deleted_at < cutoff;
  get diagnostics n = row_count; removed := removed + n;

  delete from public.tasks where deleted_at < cutoff;
  get diagnostics n = row_count; removed := removed + n;

  delete from public.task_groups where deleted_at < cutoff;
  get diagnostics n = row_count; removed := removed + n;

  delete from public.boards where deleted_at < cutoff;
  get diagnostics n = row_count; removed := removed + n;

  return removed;
end;
$$;

-- --- assignees ------------------------------------------------------------

-- Replaces a task's assignees wholesale, which is how the task dialog thinks
-- about it: the user picks a set and saves.
create or replace function public.set_task_assignees(
  target_task uuid,
  user_ids    uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
begin
  select workspace_id into ws from public.tasks where id = target_task;
  if ws is null then
    raise exception 'Task % does not exist.', target_task;
  end if;
  if not public.can_edit_workspace(ws) then
    raise exception 'You do not have permission to assign this task.';
  end if;

  delete from public.task_assignees
  where task_id = target_task
    and user_id <> all (coalesce(user_ids, '{}'::uuid[]));

  -- Only workspace members can be assigned; the join filters out anyone else
  -- rather than raising, so a stale client list does not fail the whole save.
  insert into public.task_assignees (task_id, user_id, workspace_id, assigned_by)
  select target_task, m.user_id, ws, auth.uid()
  from public.workspace_members m
  where m.workspace_id = ws
    and m.user_id = any (coalesce(user_ids, '{}'::uuid[]))
  on conflict (task_id, user_id) do nothing;
end;
$$;

-- --- activity -------------------------------------------------------------

create or replace function public.log_activity(
  target_task uuid,
  entry_kind  public.activity_kind,
  entry_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
begin
  select workspace_id into ws from public.tasks where id = target_task;
  if ws is null or not public.can_edit_workspace(ws) then
    return;  -- activity is a nice-to-have; never fail the real operation
  end if;

  insert into public.task_activity (task_id, workspace_id, actor_id, kind, detail)
  values (target_task, ws, auth.uid(), entry_kind, entry_detail);
end;
$$;

-- ===========================================================================
-- 4. Notifications
--
-- Raised by trigger at the moment the thing happens, so nothing has to be
-- polled and the client cannot forget to create one.
-- ===========================================================================

-- Central insert. SECURITY DEFINER because a notification is written *for
-- someone else* — the actor has no rights over the recipient's rows.
create or replace function public.notify_user(
  recipient    uuid,
  n_kind       public.notification_kind,
  n_title      text,
  n_body       text default '',
  n_workspace  uuid default null,
  n_task       uuid default null,
  n_board      uuid default null,
  n_invite     uuid default null,
  n_actor      uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Never notify someone about their own action: they were there.
  if recipient is null or recipient = coalesce(n_actor, auth.uid()) then
    return;
  end if;

  insert into public.notifications (
    user_id, workspace_id, kind, title, body,
    task_id, board_id, invite_id, actor_id
  )
  values (
    recipient, n_workspace, n_kind, n_title, n_body,
    n_task, n_board, n_invite, coalesce(n_actor, auth.uid())
  );
end;
$$;

-- Someone's display name, for notification copy.
create or replace function public.actor_name(target uuid)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    nullif(trim(full_name), ''),
    split_part(email, '@', 1),
    'Someone'
  )
  from public.profiles where id = target;
$$;

-- --- invitations ----------------------------------------------------------

create or replace function public.notify_on_invite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ws_name text;
begin
  -- Only when we know who they are. An invitation to someone with no account
  -- yet has nowhere to deliver — they get it from accept_pending_invites()
  -- when they first sign in.
  if new.invitee_id is null then
    return new;
  end if;

  select name into ws_name from public.workspaces where id = new.workspace_id;

  perform public.notify_user(
    recipient   => new.invitee_id,
    n_kind      => 'workspace_invite',
    n_title     => public.actor_name(new.invited_by) || ' invited you to ' || coalesce(ws_name, 'a workspace'),
    n_body      => 'You have been invited as ' || new.role::text || '.',
    n_workspace => new.workspace_id,
    n_invite    => new.id,
    n_actor     => new.invited_by
  );
  return new;
end;
$$;

drop trigger if exists workspace_invites_notify on public.workspace_invites;
create trigger workspace_invites_notify
  after insert on public.workspace_invites
  for each row execute function public.notify_on_invite();

-- Nothing announces an accepted invitation on its own.
--
-- There used to be a notify_on_invite_answered trigger telling the inviter
-- "X joined your workspace" — but accepting also inserts a workspace_members
-- row, and notify_on_member_joined already tells *everyone* in the workspace
-- the same sentence. The inviter is one of those people, so they got it twice.
--
-- The membership trigger is the right owner: it covers joining by code and by
-- invitation alike, and it does not need to know which route was taken.
drop trigger if exists workspace_invites_notify_answered
  on public.workspace_invites;
drop function if exists public.notify_on_invite_answered() cascade;

-- Rewrites the invited person's own notification once they answer it.
--
-- The title was written when the invitation arrived — "admin invited you to My
-- workspace" — and said the same thing forever after. Someone who had already
-- joined still read an open invitation in their bell, which is worse than
-- stale: it says the opposite of what happened.
--
-- The row is kept rather than deleted, so the history stays legible.
create or replace function public.settle_invite_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ws_name text;
  settled text;
begin
  if old.accepted_at is not distinct from new.accepted_at
     and old.declined_at is not distinct from new.declined_at then
    return new;
  end if;

  select name into ws_name from public.workspaces where id = new.workspace_id;

  if new.accepted_at is not null then
    settled := 'You joined ' || coalesce(ws_name, 'the workspace');
  elsif new.declined_at is not null then
    settled := 'You declined the invitation to '
               || coalesce(ws_name, 'a workspace');
  else
    return new;
  end if;

  update public.notifications
  set title   = settled,
      body    = '',
      read_at = coalesce(read_at, now())
  where invite_id = new.id
    and kind = 'workspace_invite';

  return new;
end;
$$;

drop trigger if exists workspace_invites_settle_notification
  on public.workspace_invites;
create trigger workspace_invites_settle_notification
  after update of accepted_at, declined_at on public.workspace_invites
  for each row execute function public.settle_invite_notification();

-- --- membership -----------------------------------------------------------

-- Everyone already in the workspace hears that someone joined.
create or replace function public.notify_on_member_joined()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ws_name text;
  who     text;
  existing record;
begin
  select name into ws_name from public.workspaces where id = new.workspace_id;
  who := public.actor_name(new.user_id);

  for existing in
    select user_id from public.workspace_members
    where workspace_id = new.workspace_id and user_id <> new.user_id
  loop
    perform public.notify_user(
      recipient   => existing.user_id,
      n_kind      => 'member_joined',
      n_title     => who || ' joined ' || coalesce(ws_name, 'the workspace'),
      n_workspace => new.workspace_id,
      n_actor     => new.user_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists workspace_members_notify_joined on public.workspace_members;
create trigger workspace_members_notify_joined
  after insert on public.workspace_members
  for each row execute function public.notify_on_member_joined();

create or replace function public.notify_on_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ws_name text;
begin
  if old.role = new.role then
    return new;
  end if;

  select name into ws_name from public.workspaces where id = new.workspace_id;

  perform public.notify_user(
    recipient   => new.user_id,
    n_kind      => 'role_changed',
    n_title     => 'You are now ' || new.role::text || ' in ' || coalesce(ws_name, 'a workspace'),
    n_workspace => new.workspace_id
  );
  return new;
end;
$$;

drop trigger if exists workspace_members_notify_role on public.workspace_members;
create trigger workspace_members_notify_role
  after update of role on public.workspace_members
  for each row execute function public.notify_on_role_change();

-- --- assignment -----------------------------------------------------------

create or replace function public.notify_on_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t record;
begin
  select title, board_id, workspace_id into t
  from public.tasks where id = new.task_id;

  perform public.notify_user(
    recipient   => new.user_id,
    n_kind      => 'task_assigned',
    n_title     => public.actor_name(new.assigned_by) || ' assigned you "' || t.title || '"',
    n_workspace => t.workspace_id,
    n_task      => new.task_id,
    n_board     => t.board_id,
    n_actor     => new.assigned_by
  );
  return new;
end;
$$;

drop trigger if exists task_assignees_notify on public.task_assignees;
create trigger task_assignees_notify
  after insert on public.task_assignees
  for each row execute function public.notify_on_assignment();

-- --- task changes ---------------------------------------------------------

-- Everyone assigned hears when a task moves, except whoever moved it.
create or replace function public.notify_on_task_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_label text;
  assignee  record;
begin
  if old.status_id is not distinct from new.status_id then
    return new;
  end if;

  select name into new_label
  from public.board_status_labels where id = new.status_id;

  for assignee in
    select user_id from public.task_assignees where task_id = new.id
  loop
    perform public.notify_user(
      recipient   => assignee.user_id,
      n_kind      => 'task_status_changed',
      n_title     => '"' || new.title || '" moved to ' || coalesce(new_label, 'no status'),
      n_workspace => new.workspace_id,
      n_task      => new.id,
      n_board     => new.board_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists tasks_notify_status on public.tasks;
create trigger tasks_notify_status
  after update of status_id on public.tasks
  for each row execute function public.notify_on_task_status();

-- --- notes and comments ---------------------------------------------------



-- Records who was named in a message, and tells them.
--
-- Mentions are stored rather than re-parsed on read: an edit that removes the
-- @name should not un-notify someone who has already been pinged, and the row
-- is what makes that history legible.
--
-- Matching is by display name against workspace members, longest name first —
-- otherwise "@Ana" would match inside "@Ana Maria" and claim the shorter of
-- the two.
create or replace function public.record_comment_mentions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t        record;
  member   record;
  everyone boolean;
begin
  select title, board_id, workspace_id into t
  from public.tasks where id = new.task_id;

  -- @everyone names the whole team at once, which is the natural way to ask
  -- "who can pick this up?". Matched on a word boundary so an address like
  -- someone@everyone.example does not trip it.
  everyone := new.body ~* '(^|\s)@everyone(\s|$|[[:punct:]])';

  for member in
    select p.id, p.full_name, p.email
    from public.workspace_members m
    join public.profiles p on p.id = m.user_id
    where m.workspace_id = new.workspace_id
      and m.user_id <> new.author_id
    order by char_length(coalesce(nullif(trim(p.full_name), ''), p.email)) desc
  loop
    if everyone or new.body ilike '%@' || coalesce(
         nullif(trim(member.full_name), ''), split_part(member.email, '@', 1)
       ) || '%' then

      insert into public.task_comment_mentions
        (comment_id, user_id, workspace_id)
      values (new.id, member.id, new.workspace_id)
      on conflict do nothing;

      perform public.notify_user(
        recipient   => member.id,
        n_kind      => 'mentioned',
        n_title     => public.actor_name(new.author_id)
                       || case when everyone then ' asked the team about "'
                               else ' mentioned you on "' end
                       || t.title || '"',
        n_body      => left(new.body, 140),
        n_workspace => new.workspace_id,
        n_task      => new.task_id,
        n_board     => t.board_id,
        n_actor     => new.author_id
      );
    end if;
  end loop;

  return null;  -- AFTER trigger
end;
$$;

-- Numbered like the tasks triggers: same-timing triggers fire alphabetically,
-- and notify_on_comment reads the rows this one writes. Leaving that to the
-- accident of "m" sorting before "n" is how the tasks ordering bug happened.
drop trigger if exists task_comments_mentions on public.task_comments;
drop trigger if exists task_comments_1_mentions on public.task_comments;
create trigger task_comments_1_mentions
  after insert on public.task_comments
  for each row execute function public.record_comment_mentions();

create or replace function public.notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t        record;
  assignee record;
  parent_author uuid;
begin
  select title, board_id, workspace_id into t
  from public.tasks where id = new.task_id;

  -- A reply notifies the person being replied to, whether or not they are
  -- assigned to the task.
  if new.parent_id is not null then
    select author_id into parent_author
    from public.task_comments where id = new.parent_id;

    perform public.notify_user(
      recipient   => parent_author,
      n_kind      => 'comment_added',
      n_title     => public.actor_name(new.author_id) || ' replied to you on "' || t.title || '"',
      n_body      => left(new.body, 140),
      n_workspace => t.workspace_id,
      n_task      => new.task_id,
      n_board     => t.board_id,
      n_actor     => new.author_id
    );
  end if;

  for assignee in
    select a.user_id from public.task_assignees a
    where a.task_id = new.task_id
      and a.user_id is distinct from parent_author
      -- A mention already told them, and more pointedly. Two notifications for
      -- one message reads as a bug.
      and not exists (
        select 1 from public.task_comment_mentions m
        where m.comment_id = new.id and m.user_id = a.user_id
      )
  loop
    perform public.notify_user(
      recipient   => assignee.user_id,
      n_kind      => 'comment_added',
      n_title     => public.actor_name(new.author_id) || ' commented on "' || t.title || '"',
      n_body      => left(new.body, 140),
      n_workspace => t.workspace_id,
      n_task      => new.task_id,
      n_board     => t.board_id,
      n_actor     => new.author_id
    );
  end loop;

  return new;
end;
$$;

-- Numbered 2: runs after mentions, whose rows it checks to avoid notifying
-- the same person twice for one message.
drop trigger if exists task_comments_notify on public.task_comments;
drop trigger if exists task_comments_2_notify on public.task_comments;
create trigger task_comments_2_notify
  after insert on public.task_comments
  for each row execute function public.notify_on_comment();

-- --- stalled work ---------------------------------------------------------

-- Stamps progress_at only when progress actually moves.
--
-- updated_at cannot answer "has this task progressed", because renaming it or
-- changing a date resets that too — a genuinely stalled task would look busy.
create or replace function public.touch_progress_at()
returns trigger
language plpgsql
as $$
begin
  if new.progress is distinct from old.progress then
    new.progress_at = now();
  end if;
  return new;
end;
$$;

-- Numbered 4: after the status triggers, so it sees the final progress value.
drop trigger if exists tasks_4_touch_progress on public.tasks;
create trigger tasks_4_touch_progress
  before update of progress on public.tasks
  for each row execute function public.touch_progress_at();

-- Moves started-but-stalled work to the board's stuck status.
--
-- "Started but stalled" is deliberately narrow:
--
--   * the task is on an in-between status — not the board's default, and not
--     done. A task nobody has begun is not stuck, it is just not started.
--   * progress is above zero, so someone genuinely started it
--   * progress has not moved in `stale_days`
--
-- Boards name their own statuses, so the stuck label is found by name rather
-- than assumed. A board that renamed or deleted it does not use the concept,
-- and its tasks are left alone rather than being moved somewhere arbitrary.
--
-- Schedule alongside the due sweep:
--   select cron.schedule('stale-sweep', '15 8 * * *',
--                        'select public.sweep_stalled_tasks()');
create or replace function public.sweep_stalled_tasks(stale_days int default 3)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  t       record;
  moved   int := 0;
begin
  for t in
    select tk.id, tk.title, tk.board_id, tk.workspace_id, stuck.id as stuck_id
    from public.tasks tk
    join public.board_status_labels cur on cur.id = tk.status_id
    -- The board's own stuck label, if it has one.
    join public.board_status_labels stuck
      on stuck.board_id = tk.board_id
     and lower(stuck.name) like '%stuck%'
     and not stuck.is_done
     and not stuck.is_default
    where tk.deleted_at is null
      -- In-between only: skip not-started and done.
      and not cur.is_default
      and not cur.is_done
      -- Someone actually began it.
      and tk.progress > 0
      and tk.progress < 1
      -- And has not touched it since.
      and tk.progress_at < now() - make_interval(days => greatest(stale_days, 1))
      -- Already stuck is not a move worth making, or notifying about.
      and tk.status_id <> stuck.id
  loop
    -- The status triggers on this update keep board_id and the check honest,
    -- and tasks_notify_status tells whoever is assigned.
    update public.tasks set status_id = t.stuck_id where id = t.id;
    moved := moved + 1;
  end loop;

  return moved;
end;
$$;

-- --- due dates ------------------------------------------------------------

-- The zero-argument version from before this gained a parameter. A default
-- argument sits alongside the old signature rather than replacing it, and a
-- bare sweep_due_tasks() call would then be ambiguous.
drop function if exists public.sweep_due_tasks();
--
-- The one kind nothing triggers, because "a date arrived" is not an event any
-- row change signals. Schedule this with pg_cron:
--
--   select cron.schedule('due-sweep', '0 8 * * *',
--                        'select public.sweep_due_tasks()');
--
-- Nothing calls this on its own. Without that cron entry the function exists
-- and works but never runs, which reads as "due-date notifications are broken"
-- — see SETUP.md, which now lists it as a required step rather than an
-- optional one.
--
-- Running it more often than daily is harmless: the query below skips anyone
-- who already got the same reminder in the last 20 hours.
create or replace function public.sweep_due_tasks(lead_days int default 3)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  t       record;
  created int := 0;
  days    int;
begin
  for t in
    select
      tk.id, tk.title, tk.board_id, tk.workspace_id, tk.due_date,
      a.user_id,
      (tk.due_date - current_date) as days_left
    from public.tasks tk
    join public.task_assignees a on a.task_id = tk.id
    left join public.board_status_labels s on s.id = tk.status_id
    where tk.deleted_at is null
      and tk.due_date is not null
      -- Everything from `lead_days` out to already overdue. Reminding once on
      -- the eve of a deadline is not a reminder, it is a surprise — so the
      -- window opens early and closes only when the work is done.
      and tk.due_date <= current_date + greatest(lead_days, 0)
      -- Finished work is not a reminder.
      and coalesce(s.is_done, false) = false
      -- Once a day per task, so a sweep that runs hourly does not nag. Checked
      -- here rather than by a unique index, because indexing created_at::date
      -- requires an immutable expression and that cast is not one.
      and not exists (
        select 1 from public.notifications n
        where n.task_id = tk.id
          and n.user_id = a.user_id
          and n.kind in ('task_due_soon', 'task_overdue')
          and n.created_at > now() - interval '20 hours'
      )
  loop
    days := t.days_left;

    perform public.notify_user(
      recipient   => t.user_id,
      n_kind      => case when days < 0 then 'task_overdue'::public.notification_kind
                          else 'task_due_soon'::public.notification_kind end,
      -- Counts down as the date approaches, so each day's reminder says
      -- something new rather than repeating yesterday's.
      n_title     => case
                       when days < -1 then
                         '"' || t.title || '" is ' || abs(days) || ' days overdue'
                       when days = -1 then '"' || t.title || '" is a day overdue'
                       when days = 0  then '"' || t.title || '" is due today'
                       when days = 1  then '"' || t.title || '" is due tomorrow'
                       else '"' || t.title || '" is due in ' || days || ' days'
                     end,
      n_body      => 'Due ' || to_char(t.due_date, 'FMDay, FMMon FMDD'),
      n_workspace => t.workspace_id,
      n_task      => t.id,
      n_board     => t.board_id,
      -- No actor: the system raised this, nobody did it.
      n_actor     => null
    );
    created := created + 1;
  end loop;

  return created;
end;
$$;

-- --- reading and dismissing ----------------------------------------------

create or replace function public.unread_notification_count()
returns int
language sql
security definer
set search_path = public
stable
as $$
  select count(*)::int from public.notifications
  where user_id = auth.uid() and read_at is null;
$$;

create or replace function public.mark_notifications_read(ids uuid[] default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  touched int;
begin
  update public.notifications
  set read_at = now()
  where user_id = auth.uid()
    and read_at is null
    -- Null marks everything: "mark all as read".
    and (ids is null or id = any (ids));

  get diagnostics touched = row_count;
  return touched;
end;
$$;

-- Keeps the table from growing without bound. Read notifications older than 30
-- days, and anything at all older than 90.
create or replace function public.purge_notifications()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  removed int;
begin
  delete from public.notifications
  where (read_at is not null and read_at < now() - interval '30 days')
     or created_at < now() - interval '90 days';

  get diagnostics removed = row_count;
  return removed;
end;
$$;

-- ===========================================================================
-- Grants
--
-- SECURITY DEFINER functions run with the definer's rights, so each is
-- explicitly granted to authenticated and withheld from anon.
-- ===========================================================================
grant execute on function public.is_workspace_member(uuid)       to authenticated;
grant execute on function public.can_edit_workspace(uuid)        to authenticated;
grant execute on function public.can_manage_workspace(uuid)      to authenticated;
grant execute on function public.accept_pending_invites(uuid)    to authenticated;
grant execute on function public.my_pending_invites()            to authenticated;
grant execute on function public.join_workspace_with_code(text)  to authenticated;
grant execute on function public.search_invitable_users(uuid, text, int) to authenticated;
grant execute on function public.invite_user(uuid, uuid, public.workspace_role) to authenticated;
grant execute on function public.regenerate_join_code(uuid)      to authenticated;
grant execute on function public.reorder_task(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.renormalize_task_positions(uuid) to authenticated;
grant execute on function public.board_tree(uuid)                to authenticated;
grant execute on function public.soft_delete(text, uuid)         to authenticated;
grant execute on function public.restore(text, uuid)             to authenticated;
grant execute on function public.deleted_items(uuid)             to authenticated;
grant execute on function public.set_task_assignees(uuid, uuid[]) to authenticated;
grant execute on function public.log_activity(uuid, public.activity_kind, jsonb) to authenticated;

grant execute on function public.unread_notification_count()      to authenticated;
grant execute on function public.mark_notifications_read(uuid[])  to authenticated;

-- Maintenance and internals: called by pg_cron or by triggers, never by a
-- client. notify_user in particular writes rows for *other* people, so it must
-- not be reachable from the API.
revoke execute on function public.purge_deleted()       from public, anon, authenticated;
revoke execute on function public.resync_comment_counts()
  from public, anon, authenticated;
revoke execute on function public.purge_notifications() from public, anon, authenticated;
revoke execute on function public.sweep_due_tasks(int)  from public, anon, authenticated;
revoke execute on function public.sweep_stalled_tasks(int)
  from public, anon, authenticated;
revoke execute on function public.notify_user(
  uuid, public.notification_kind, text, text, uuid, uuid, uuid, uuid, uuid
) from public, anon, authenticated;
