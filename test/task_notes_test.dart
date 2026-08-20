import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:planner/models/planner_models.dart';

void main() {
  group('note kinds', () {
    test('wire names match the task_note_kind enum in 0013', () {
      expect(TaskNoteKind.update.wire, 'update');
      expect(TaskNoteKind.submission.wire, 'submission');
      expect(TaskNoteKind.rejection.wire, 'rejection');
      expect(TaskNoteKind.approval.wire, 'approval');
    });

    test('an unknown kind falls back rather than throwing', () {
      // A newer server could send a kind this build has never heard of. The
      // note still has to render.
      expect(TaskNoteKind.fromName('something_new'), TaskNoteKind.update);
      expect(TaskNoteKind.fromName(''), TaskNoteKind.update);
    });

    test('verdicts are the two an ordinary member may not write', () {
      // Mirrors the insert policy in 0013: approving or sending back is a
      // supervisor's call, submitting your own work is not.
      expect(TaskNoteKind.rejection.isVerdict, isTrue);
      expect(TaskNoteKind.approval.isVerdict, isTrue);
      expect(TaskNoteKind.submission.isVerdict, isFalse);
      expect(TaskNoteKind.update.isVerdict, isFalse);
    });
  });

  group('reading a note', () {
    test('carries the status move it explains', () {
      final note = TaskNote.fromMap({
        'id': 'n1',
        'task_id': 't1',
        'kind': 'rejection',
        'body': 'Lighting is off',
        'status_from': 'Done',
        'status_to': 'Working on it',
        'created_at': '2026-08-20T09:00:00Z',
      });

      expect(note.kind, TaskNoteKind.rejection);
      expect(note.statusFrom, 'Done');
      expect(note.statusTo, 'Working on it');
      expect(note.movedStatus, isTrue);
    });

    test('a note that changed nothing does not claim a move', () {
      // An approval leaves the task where it is, so there is no arrow to draw.
      final note = TaskNote.fromMap({
        'id': 'n2',
        'task_id': 't1',
        'kind': 'approval',
        'status_from': 'Done',
        'status_to': 'Done',
        'created_at': '2026-08-20T09:00:00Z',
      });
      expect(note.movedStatus, isFalse);
    });

    test('a plain update has no move at all', () {
      final note = TaskNote.fromMap({
        'id': 'n3',
        'task_id': 't1',
        'body': 'Halfway through',
        'created_at': '2026-08-20T09:00:00Z',
      });
      expect(note.movedStatus, isFalse);
      expect(note.kind, TaskNoteKind.update);
    });

    test('edited is a stamp, not a comparison of timestamps', () {
      final fresh = TaskNote.fromMap({
        'id': 'n4',
        'task_id': 't1',
        'created_at': '2026-08-20T09:00:00Z',
      });
      final edited = TaskNote.fromMap({
        'id': 'n5',
        'task_id': 't1',
        'created_at': '2026-08-20T09:00:00Z',
        'edited_at': '2026-08-20T09:05:00Z',
      });
      expect(fresh.wasEdited, isFalse);
      expect(edited.wasEdited, isTrue);
    });

    test('a missing body reads as empty rather than throwing', () {
      // A note can be nothing but attachments.
      final note = TaskNote.fromMap({
        'id': 'n6',
        'task_id': 't1',
        'created_at': '2026-08-20T09:00:00Z',
      });
      expect(note.body, '');
    });
  });

  group('attachments', () {
    NoteAttachment attachment(int bytes, [String type = 'image/png']) {
      return NoteAttachment.fromMap({
        'id': 'a1',
        'note_id': 'n1',
        'storage_path': 'ws/task/uuid-photo.png',
        'file_name': 'photo.png',
        'content_type': type,
        'byte_size': bytes,
      });
    }

    test('images are flagged so they can preview inline', () {
      expect(attachment(100).isImage, isTrue);
      expect(attachment(100, 'application/pdf').isImage, isFalse);
    });

    test('sizes read the way a person would say them', () {
      expect(attachment(512).readableSize, '512 B');
      expect(attachment(2048).readableSize, '2 KB');
      expect(attachment(3 * 1024 * 1024).readableSize, '3.0 MB');
    });

    test('a zero-byte file still reports a size', () {
      expect(attachment(0).readableSize, '0 B');
    });
  });

  group('pending uploads', () {
    test('report their size before anything is uploaded', () {
      final upload = NoteUpload(
        fileName: 'shot.jpg',
        bytes: Uint8List(4096),
        contentType: 'image/jpeg',
      );
      expect(upload.readableSize, '4 KB');
      expect(upload.isImage, isTrue);
    });
  });

  group('task counts', () {
    test('note_count rides along with the task', () {
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'board_id': 'b1',
        'title': 'Ship it',
        'note_count': 3,
        'comment_count': 12,
      });
      expect(task.noteCount, 3);
      expect(task.commentCount, 12);
    });

    test('a task from a server without 0014 still loads', () {
      // note_count, status_by and status_at are all absent before the
      // migration runs. The board has to render anyway.
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'board_id': 'b1',
        'title': 'Ship it',
      });
      expect(task.noteCount, 0);
      expect(task.statusBy, isNull);
      expect(task.statusAt, isNull);
    });

    test('who moved the status is resolved to a profile', () {
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'board_id': 'b1',
        'title': 'Ship it',
        'status_at': '2026-08-20T09:00:00Z',
        'status_by': {
          'id': 'u1',
          'email': 'ak@vintazk.com',
          'full_name': 'Al-Khasmir',
        },
      });
      expect(task.statusBy?.displayName, 'Al-Khasmir');
      expect(task.statusAt, isNotNull);
    });

    test('a status moved by a trigger has no person attached', () {
      // auth.uid() is null for a scheduled sweep, and "nobody in particular"
      // is the honest answer rather than inventing an actor.
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'board_id': 'b1',
        'title': 'Ship it',
        'status_at': '2026-08-20T09:00:00Z',
        'status_by': null,
      });
      expect(task.statusBy, isNull);
      expect(task.statusAt, isNotNull);
    });
  });
}
