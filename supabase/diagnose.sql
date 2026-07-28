-- Diagnostic for "0 members" + permission error.
--
-- One query, one result set — the SQL Editor only shows the last statement's
-- output, so everything is unioned together rather than run as six separate
-- selects.
--
-- Run it and paste back the whole table.

select * from (
  -- Does the workspace exist, and who owns it?
  select
    1                     as sort,
    'workspace'           as item,
    w.name                as detail,
    w.owner_id::text      as value,
    ''                    as extra
  from public.workspaces w

  union all

  -- Is there a membership row? This is what RLS actually checks.
  select
    2,
    'membership',
    m.role::text,
    m.user_id::text,
    'workspace ' || left(m.workspace_id::text, 8)
  from public.workspace_members m

  union all

  -- Did the profile trigger fire? loadMembers joins profiles, so a missing
  -- profile row yields zero members even when the membership exists.
  select
    3,
    'auth user',
    u.email,
    u.id::text,
    case when p.id is null then 'NO PROFILE ROW' else 'has profile' end
  from auth.users u
  left join public.profiles p on p.id = u.id

  union all

  -- Do the triggers exist?
  select
    4,
    'trigger',
    tgname,
    tgrelid::regclass::text,
    case tgenabled when 'O' then 'enabled' else 'DISABLED' end
  from pg_trigger
  where not tgisinternal
    and tgrelid in ('public.workspaces'::regclass, 'auth.users'::regclass)

  union all

  -- Are the RLS helper functions present and SECURITY DEFINER?
  select
    5,
    'function',
    proname,
    case when prosecdef then 'security definer' else 'INVOKER — WRONG' end,
    ''
  from pg_proc
  where pronamespace = 'public'::regnamespace
    and proname in (
      'is_workspace_member', 'can_edit_workspace',
      'handle_new_workspace', 'handle_new_user'
    )

  union all

  -- Counts, so an empty section is obvious rather than just absent.
  select 6, 'count', 'workspaces', count(*)::text, '' from public.workspaces
  union all
  select 6, 'count', 'members', count(*)::text, '' from public.workspace_members
  union all
  select 6, 'count', 'profiles', count(*)::text, '' from public.profiles
  union all
  select 6, 'count', 'auth users', count(*)::text, '' from auth.users
) rows
order by sort, item, detail;
