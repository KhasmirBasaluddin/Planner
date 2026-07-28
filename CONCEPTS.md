# How Planner is organised

Four levels, each inside the one above it.

```
Workspace   "Vintazk Business"          ← the TEAM. People join this.
│                                          join code: PLNR-7K2M
├── Board   "Website Redesign"          ← a PROJECT
│   ├── Group  "Design"                 ← a PHASE
│   │   ├── Task  "Wireframes"          ← the WORK
│   │   └── Task  "Style guide"
│   └── Group  "Build"
│       └── Task  "Homepage"
│
└── Board   "Q1 Marketing"              ← another project, same team
    └── Group  "Campaigns"
        └── Task  "Launch email"
```

The short version: **you invite people to a workspace, and you organise work
into boards.**

---

## Workspace — *who*

The team boundary. Everything else lives inside one.

- People join a **workspace**, not a board. Once in, they see every board it
  contains.
- Each workspace has a **join code** like `PLNR-7K2M`. Share it and anyone with
  it can join as a member.
- Members have a role: **Owner**, **Admin**, **Member** or **Viewer**.
- Most people need exactly one workspace.

**When a second workspace makes sense:** genuinely separate groups of people who
should not see each other's work — a company workspace and a personal one, or
two clients whose teams must not overlap. Not for separating projects; that is
what boards are for.

## Board — *what*

One project, client, or area of work. You will have several.

- Lives inside exactly one workspace.
- Visible to everyone in that workspace — creating a board does not invite
  anyone, and there is no per-board access. Anyone in the workspace sees it.
- Has its own colour, so it is identifiable in the sidebar.
- Can be viewed as a **Table**, a **Kanban** board, or a **Calendar** — three
  presentations of the same tasks, not three separate things.

## Group — *which phase*

A section inside a board. "Design / Build / Launch", "This week / Next week", or
however you think about the work.

- A board needs at least one group before it can hold a task — a task has to
  live somewhere.
- Collapsible, so a long board stays readable.

## Task — *the work*

The actual unit of work, inside a group.

Carries a title, an assignee, status, priority, a due date, a start/end
timeline, and progress. Each task also has **notes**: a shared thread the whole
workspace can read, write to, and react to, with each note attributed to whoever
wrote it.

---

## The flow, first time through

1. **Sign up** — confirm your email, and you land on the welcome screen.
2. **Create a workspace** — name your team. A starter board and a "To do" group
   are created with it, so you are not staring at an empty screen.
3. **Add tasks** — *New task* in the board header.
4. **Invite the team** — workspace menu → *Members & invites* → copy the join
   code and send it to them. They pick *Join with a code* and they are in.
5. **Add more boards** — the `+` beside BOARDS in the sidebar, one per project.

## Roles

| Role | Edit content | Manage people | Notes |
|---|---|---|---|
| **Owner** | ✅ | ✅ | Created the workspace. Cannot be removed. |
| **Admin** | ✅ | ✅ | Invite, remove, change roles, rotate the join code. |
| **Member** | ✅ | ❌ | The default for anyone who joins. |
| **Viewer** | ❌ | ❌ | Read-only. Editing controls are hidden. |

Roles are **per workspace**. The same person can own one and be a viewer in
another.

Enforced in two places: the UI hides what you cannot do, and row level security
in Postgres rejects the write regardless. A modified client cannot bypass it.

---

## Common questions

**Why do I create a workspace before a board?**
A board has to belong to one — it is a foreign key, not a preference. Creating
a workspace makes a starter board at the same time, so in practice it is one
step.

**Can I share a single board with someone outside the team?**
Not currently. Access is workspace-wide by design: join the team, see the
boards. Per-board guests would need a separate role and extra policies.

**Can someone be in two workspaces?**
Yes, with a different role in each. The sidebar switcher moves between them.

**What if a join code gets shared too widely?**
An owner or admin can regenerate it under *Members & invites*. The old code
stops working immediately; people who already joined stay.

**Is it live?**
Yes. Boards, groups, tasks and notes subscribe to Postgres changes, so a
teammate's edit appears without a refresh.
