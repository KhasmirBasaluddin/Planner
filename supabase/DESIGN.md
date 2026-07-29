# Planner — database design

Why the schema looks the way it does. Read this before changing it.

## Shape

```
profiles                                    mirrors auth.users
  │
workspaces ──< workspace_members >── profiles
  │       └──< workspace_invites
  │
  ├──< boards
  │     ├──< board_columns          the columns this board defines
  │     ├──< board_views            saved Table / Kanban / Calendar views
  │     └──< task_groups
  │           └──< tasks
  │                 ├──< task_assignees >── profiles     many people per task
  │                 ├──< task_column_values ── board_columns
  │                 ├──< task_notes ──< task_note_reactions
  │                 ├──< task_comments
  │                 └──< task_activity
```

Four levels of containment — workspace, board, group, task — each a foreign key
into the one above. Everything else hangs off a task.

## Decisions

### Every table carries `workspace_id`

Denormalized on purpose, and the one place this schema stores a derivable value.

The old schema resolved a task's workspace by walking `task → group → board`
inside a SECURITY DEFINER function, called once per row per policy check. Every
read of every task ran a three-table join before returning a single row.

Now the workspace is on the row and RLS reads it directly. A trigger keeps it
correct on insert and update, so the client cannot set it wrong and moving a
task between boards cannot desynchronize it. The duplication is real but it is
maintained by the database, not by application code.

### Status and priority are rows, not strings

The old schema had `status text not null default 'notStarted'`, which accepts
`'banana'`. It also contradicted `board_columns`, whose whole purpose is letting
each board define its own labels.

Both now live in `board_status_labels`, keyed to the board. A task's status is a
foreign key into that table. Each board gets a default set on creation, so the
common case still just works, and renaming "Working" to "In progress" is an
update to one row instead of a rewrite of every task.

`position` orders the labels; `is_done` marks which ones count as complete, so
progress rollups do not hardcode a name.

### Assignees are a junction table

`tasks.assignee_id` allowed exactly one person. Monday.com assigns several, and
so does any real team. `task_assignees` is the junction, with a composite
primary key so the same person cannot be added twice.

`tasks.owner` is gone. It stored a *copy* of the assignee's display name, so
renaming yourself left your old name on every task you had ever been assigned.
The name belongs to `profiles` and is read through the join.

### Positions are `numeric`, not `int`

Reordering with integers means renumbering every row after the insertion point —
the old repository issued one UPDATE per task in a loop, so moving a task in a
200-row board was 200 round trips, non-atomic, and corrupted by two people
dragging at once.

`numeric` lets a row move between its neighbours by taking the midpoint of their
positions: one UPDATE, one row, regardless of board size. `reorder_task()` does
this server-side and returns the new position.

Midpoints halve the gap each time, so a pathological drag sequence eventually
exhausts precision. `numeric` is arbitrary-precision, so this takes far longer
to matter than with a float, and `renormalize_task_positions()` resets a group
to whole numbers when it does.

### Soft deletes

`deleted_at` on boards, groups, tasks and notes. RLS filters deleted rows out of
normal reads, so nothing needs to remember to add `where deleted_at is null`;
`restore_*` functions bring them back, and `purge_deleted()` clears anything
older than 30 days.

Hard deletes still cascade — this is a recycle bin, not immutability.

### One round trip per board

`loadBoards` used to be four sequential queries plus client-side joins, and note
counts fetched every note row just to count them.

`board_tree(workspace_id)` returns the whole nested structure as JSON in one
call, with counts aggregated in the database. `task_notes_count` is a column
maintained by trigger rather than a query.

### Access control

Two SECURITY DEFINER helpers decide everything:

- `is_workspace_member(workspace)` — can read
- `can_edit_workspace(workspace)` — can write (owner, admin, member; not viewer)

SECURITY DEFINER because a policy on `workspace_members` that reads
`workspace_members` recurses forever. The function bypasses RLS on that one
table so the policy can ask the question at all.

Both are `stable`, so Postgres caches the result within a statement instead of
re-running it per row.

### Foreign keys point at `profiles`, not `auth.users`

PostgREST can only embed a related table when a foreign key connects the two.
`auth.users` lives in a schema PostgREST does not expose, so `profiles(...)` in
a select failed with "Could not find a relationship". Every user reference now
targets `public.profiles`, which is itself keyed to `auth.users`.

This is what the three `fix-*.sql` files were patching. They are no longer
needed.

## Files

| File | Purpose |
|---|---|
| `migrations/0001_reset.sql` | Drops the old schema. Destructive. |
| `migrations/0002_core.sql` | Tables, constraints, indexes |
| `migrations/0003_functions.sql` | Triggers, helpers, RPCs |
| `migrations/0004_policies.sql` | RLS |
| `migrations/0005_realtime.sql` | Publication and replica identity |
| `migrations/0006_seed.sql` | Backfills profiles from existing auth users |

Run them in order in the SQL Editor. `schema.sql` is the four concatenated, for
setting up a fresh project in one paste.
