-- ---------------------------------------------------------------------------
-- 0008 — Chat read receipts
--
-- One row per person per task: when they last had the task's chat open.
-- The chat shows "Seen by …" under the newest message by comparing these
-- stamps against the message's created_at. A single stamp rather than
-- per-message rows, because "have they seen the latest?" is the only question
-- the UI asks — and it keeps the table from growing with every message.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

create table if not exists public.task_chat_reads (
  task_id      uuid not null references public.tasks(id)      on delete cascade,
  user_id      uuid not null references public.profiles(id)   on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (task_id, user_id)
);

alter table public.task_chat_reads enable row level security;

-- Anyone who can read the task can see who has read its chat.
drop policy if exists task_chat_reads_select on public.task_chat_reads;
create policy task_chat_reads_select on public.task_chat_reads
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

-- Writes go through mark_chat_read() below, which stamps auth.uid() itself —
-- these policies hold the same line for anyone hitting the table directly:
-- you may only record your own reading, and only where you belong.
drop policy if exists task_chat_reads_insert on public.task_chat_reads;
create policy task_chat_reads_insert on public.task_chat_reads
  for insert to authenticated
  with check (
    user_id = auth.uid() and public.is_workspace_member(workspace_id)
  );

drop policy if exists task_chat_reads_update on public.task_chat_reads;
create policy task_chat_reads_update on public.task_chat_reads
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid() and public.is_workspace_member(workspace_id)
  );

-- The one write path the app uses. SECURITY DEFINER so the workspace_id is
-- taken from the task row rather than trusted from the client; membership is
-- still checked, so reading a chat you cannot see records nothing.
create or replace function public.mark_chat_read(p_task uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.task_chat_reads (task_id, user_id, workspace_id)
  select t.id, auth.uid(), t.workspace_id
  from public.tasks t
  where t.id = p_task
    and t.deleted_at is null
    and public.is_workspace_member(t.workspace_id)
  on conflict (task_id, user_id) do update set last_read_at = now();
$$;

grant execute on function public.mark_chat_read(uuid) to authenticated;

-- Receipts are live: "Seen" appears the moment a teammate opens the chat.
do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.task_chat_reads';
  exception
    when duplicate_object then null;  -- already published
  end;
end
$$;

alter table public.task_chat_reads replica identity full;
