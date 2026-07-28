# Setup

Planner is an online-only app: all data lives in Supabase, so you need a
project before the app will run. The free tier is enough.

## 1. Create a Supabase project

1. Sign up at [supabase.com](https://supabase.com) and create a new project.
2. Pick a region close to you and save the database password somewhere safe —
   you will not need it for this app, but Supabase will ask you to set one.

## 2. Create the database schema

1. In the Supabase dashboard, open **SQL Editor → New query**.
2. Paste the entire contents of [`supabase/schema.sql`](supabase/schema.sql).
3. Click **Run**.

The script is idempotent, so re-running it later to pick up changes is safe.

It creates:

| Table | Purpose |
|---|---|
| `profiles` | Public user data, kept in sync with `auth.users` by a trigger |
| `workspaces` / `workspace_members` / `workspace_invites` | Teams and access |
| `boards` / `task_groups` / `tasks` | The planner itself |
| `board_columns` / `task_column_values` | User-defined columns per board |
| `board_views` | Saved Table/Kanban/Timeline/Calendar views |
| `task_notes` / `task_note_reactions` | Team-visible notes on a task |
| `task_comments` / `task_activity` | Discussion and history |

Every table has row level security enabled. A user can only read or write rows
belonging to a workspace they are a member of — the client never filters by user
id itself, so a bug in the app cannot leak another team's data.

## 3. Add your credentials

1. Copy `.env.example` to `.env`.
2. In Supabase, go to **Project Settings → API** and copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon / publishable** key → `SUPABASE_ANON_KEY`

```
SUPABASE_URL=https://abcdefgh.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
```

`.env` is gitignored and will not be committed.

## 3b. Restrict accounts to Vintazk email

The desktop app only accepts `@vintazk.com` addresses. To enforce the same
rule on the server, open **Authentication -> Hooks -> Before User Created**,
choose **Postgres**, and select:

```
public.hook_allow_vintazk_email
```

That function is created by `supabase/schema.sql`. Once enabled, Supabase
rejects every other domain before creating the user, even if someone bypasses
the desktop app and calls the Auth API directly.

## Desktop releases

GitHub Actions builds both a Windows installer and portable ZIP for every
version tag. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` under
**Repository Settings -> Secrets and variables -> Actions**, then push a tag
such as `v1.0.0`. The resulting GitHub Release contains:

- `PlannerSetup-1.0.0.exe` — installer with Start Menu, optional desktop
  shortcut, uninstall support, and the `planner://` URL scheme.
- `Planner-Portable-1.0.0.zip` — unpack and run `planner.exe`.

> **Which key?** Use the **anon / publishable** key. It is meant to ship inside
> a client app — row level security is what actually protects your data.
>
> Never put the **`service_role`** key in this project. It bypasses RLS
> entirely, and anyone with a copy of the app could read and write your whole
> database. It belongs only on a server.

## 4. Email confirmation (optional)

By default Supabase emails a confirmation link on sign-up. While developing,
you may prefer to skip it:

**Authentication → Sign In / Providers → Email → Confirm email → off**

With it on, the app tells the user to check their inbox and returns them to the
sign-in screen.

> **Set up email delivery before you get far.** Supabase's built-in SMTP allows
> only a few messages per hour and then fails outright with
> `Error sending confirmation email` — which looks like a bug in the app but is
> not. See [`supabase/email-setup.md`](supabase/email-setup.md); the quick-start
> path takes about five minutes and needs no domain.

## 4b. Register the URL scheme (Windows)

Confirmation and password-reset links redirect to `planner://auth-callback`, so
that clicking one opens the app already signed in rather than returning you to a
password prompt. Windows needs to know which program owns that scheme:

In Supabase, first open **Authentication -> URL Configuration** and add this
exact value under **Redirect URLs**:

```
planner://auth-callback
```

```powershell
.\tools\register_url_scheme.ps1
```

The packaged app refreshes this registration automatically when it launches.
That makes the portable ZIP self-configuring after extraction and keeps links
working if its folder is moved. The script remains useful for debug builds.

Writes to `HKCU`, so no administrator rights are needed. Without it the browser
reports "no app is associated with this link" and the confirmation appears to do
nothing.

For debug builds, re-run the script after moving the executable. Undo the
manual registration with `-Remove`.

## 5. Run

```bash
flutter pub get
flutter run -d windows
```

If credentials are missing or still contain the placeholder values, the app
starts and shows a setup screen instead of failing with a network error.

## How teams work

- Signing in for the first time creates **My workspace**, owned by you.
- **Members & invites** in the workspace menu invites someone by email.
- The invitation is stored against that address. When that person signs up or
  signs in, `accept_pending_invites()` turns it into a real membership — so you
  can invite people who do not have an account yet.
- Roles: **Owner** (full control), **Admin** (manage people and content),
  **Member** (create and edit), **Viewer** (read-only). The UI hides editing
  controls for viewers, and RLS enforces the same rule server-side.

## Troubleshooting

**"The database schema is missing"** — step 2 was not run, or was run against a
different project than the one in `.env`.

**Sign-up succeeds but sign-in says "email not confirmed"** — check the inbox
for the confirmation link, or turn confirmation off (step 4).

**A teammate cannot see a board** — they must be a member of that workspace.
Check **Members & invites**; a pending invitation is not yet a membership.

## Windows build note

`windows/CMakeLists.txt` passes `/FS` to MSVC. Visual Studio 2026 (MSVC 14.50)
compiles source files in parallel against one shared PDB, and the CMake config
Flutter generates omits that flag, which fails with
`error C1041: cannot open program database`. The flag is guarded by `if(MSVC)`
and is harmless on older toolchains.
