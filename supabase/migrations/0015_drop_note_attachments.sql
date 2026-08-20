-- 0015 — Work notes are text only
--
-- Run after 0014. Safe to re-run.
--
-- 0013 gave notes file attachments, backed by a private storage bucket with a
-- 25 MB per-file cap. That is the right design on a paid plan and the wrong
-- one on the free tier, which allows 1 GB in total: forty files at the cap
-- would fill it, and the failure mode is uploads breaking for everyone with no
-- obvious cause.
--
-- So attachments come out entirely rather than being left half-disabled. A
-- note is what was done, in words — which is the part that actually gets read
-- when someone reviews finished work.
--
-- The notes themselves, the submit / send-back / approve loop, and everything
-- 0014 added are untouched.

-- ---------------------------------------------------------------------------
-- The rows
--
-- Dropped before the bucket: the table references nothing in storage, but
-- doing it in this order means a re-run cannot leave rows pointing at objects
-- that are already gone.
-- ---------------------------------------------------------------------------

drop table if exists public.task_note_attachments cascade;

-- ---------------------------------------------------------------------------
-- The files
--
-- Deleting the objects first, then the bucket. A bucket with contents cannot
-- be dropped, and on a database where somebody managed to upload before this
-- ran, those bytes are exactly what needs reclaiming.
-- ---------------------------------------------------------------------------

delete from storage.objects where bucket_id = 'task-attachments';
delete from storage.buckets where id = 'task-attachments';

drop policy if exists task_attachments_read   on storage.objects;
drop policy if exists task_attachments_write  on storage.objects;
drop policy if exists task_attachments_delete on storage.objects;

-- ---------------------------------------------------------------------------
-- Realtime
--
-- Removing a table from the publication is not automatic when it is dropped
-- in every Postgres version, and a stale entry makes the publication noisy to
-- read later. Guarded because the table may already be gone.
-- ---------------------------------------------------------------------------

do $$
begin
  alter publication supabase_realtime drop table public.task_note_attachments;
exception
  when undefined_object or undefined_table then null;
end
$$;

-- ---------------------------------------------------------------------------
-- The note trigger no longer has a second table to worry about
--
-- sync_note_count() only ever read task_notes, so it needs no change. This is
-- a note for whoever reads this file later wondering whether it was missed.
-- ---------------------------------------------------------------------------
