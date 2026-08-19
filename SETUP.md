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

> ⚠️ **This drops every existing Planner table before recreating them.** On a
> fresh project that does nothing. On a project with real data it destroys all
> of it — run the files in [`supabase/migrations/`](supabase/migrations/) one at
> a time instead, so you can stop before `0001_reset.sql`.
>
> Accounts survive either way: `auth.users` is never touched, and profiles are
> rebuilt from it.

It creates:

| Table | Purpose |
|---|---|
| `profiles` | Public user data, kept in sync with `auth.users` by a trigger |
| `workspaces` / `workspace_members` / `workspace_invites` | Teams and access |
| `boards` / `task_groups` / `tasks` | The planner itself |
| `board_status_labels` | Each board's own statuses — rename "Working" freely |
| `task_assignees` | Who a task is assigned to; several people per task |
| `board_columns` / `task_column_values` | User-defined columns per board |
| `board_views` | Saved Table/Kanban/Timeline/Calendar views |
| `task_notes` / `task_note_reactions` | Team-visible notes on a task |
| `task_comments` / `task_activity` | Discussion and history |
| `notifications` | Invitations, assignments, due dates, mentions |

Every table has row level security enabled. A user can only read or write rows
belonging to a workspace they are a member of — the client never filters by user
id itself, so a bug in the app cannot leak another team's data.

Why the schema is shaped this way is written up in
[`supabase/DESIGN.md`](supabase/DESIGN.md).

### Due-date reminders

Notifications for invitations, assignments and comments fire from triggers, so
they need no setup. Due-date reminders are the exception — "a date arrived" is
not something any row change signals. Enable **Database → Extensions → pg_cron**,
then run:

```sql
select cron.schedule(
  'due-sweep', '0 8 * * *', 'select public.sweep_due_tasks()'
);
```

That checks once each morning. Running it more often is harmless: a unique index
stops the same task notifying the same person twice in a day.

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

- `PlannerSetup-<version>.exe` — installer with Start Menu, optional desktop
  shortcut, uninstall support, and the `planner://` URL scheme.
- `Planner-Portable-<version>.zip` — unpack and run `planner.exe`.

The version everywhere — in the executable, the installer and the file names —
comes from the tag, so `v1.2.0` produces `PlannerSetup-1.2.0.exe`. The
`version:` field in `pubspec.yaml` only matters for local builds.

### Auto-update

On startup, Windows release builds ask the GitHub API for the latest release
of this repository. When its tag is newer than the running version, the app
offers to update; accepting downloads `PlannerSetup-<version>.exe` to the temp
folder and runs it silently, which closes the app, installs over it and
relaunches it. Declining just continues into the app — the offer returns on
the next launch.

For this to work the repository must stay public (the check is an
unauthenticated `releases/latest` call) and releases must be cut by tagging,
so the executable's version and the tag agree. Debug builds never check.
Portable-ZIP users get the same offer; accepting converts them to an
installed copy rather than updating the unpacked folder in place.

> **Which key?** Use the **anon / publishable** key. It is meant to ship inside
> a client app — row level security is what actually protects your data.
>
> Never put the **`service_role`** key in this project. It bypasses RLS
> entirely, and anyone with a copy of the app could read and write your whole
> database. It belongs only on a server.

### "Windows protected your PC"

Installing shows a blue SmartScreen dialog, and the **Run anyway** button is
hidden behind **More info**. Nothing is wrong with the build: Windows shows this
for any installer that is not signed by a certificate it recognises. Every
unsigned app gets it.

**There is no code change that removes this.** Antivirus exclusions, manifest
edits and installer settings do not help, because the warning is about the
missing signature, not about behaviour. Two real options:

**1. Buy a code signing certificate** — the only complete fix.

| | Standard OV | Extended Validation (EV) |
|---|---|---|
| Cost | ~$200–400/year | ~$400–700/year |
| Warning gone | After reputation builds | Immediately |
| Storage | File or token | Hardware token required |

Since June 2023 Microsoft requires all certificates be stored on hardware, so
even an OV certificate arrives on a USB token. Sellers include DigiCert,
Sectigo and SSL.com. An OV certificate still shows the warning at first —
SmartScreen needs to see a few hundred installs before it trusts a new
publisher. EV skips that wait, which is what you are paying the difference for.

Once you have one, uncomment the two `SignTool` lines at the bottom of
[`installer/Planner.iss`](installer/Planner.iss) and configure the tool under
**Tools → Configure Sign Tools** in Inno Setup.

**2. Tell your team to expect it.** For an internal tool with a handful of
`@vintazk.com` users this is usually the sensible call — a certificate costs
more per year than the annoyance is worth. Send them:

> Click **More info**, then **Run anyway**. Windows shows this because the app
> is not code-signed, not because anything is wrong with it.

They can confirm they have the real file by checking **Properties → Details**:
publisher *Vintazk*, version *1.0.0*.

If Windows *also* quarantines the file or Defender flags it as a threat, that is
a different problem — a false positive worth reporting at
[the Microsoft submission site](https://www.microsoft.com/en-us/wdsi/filesubmission),
which usually clears within a few days.

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
