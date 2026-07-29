import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/core/supabase/auth_service.dart';
import 'package:planner/models/planner_models.dart';
import 'package:planner/shared/utils/planner_colors.dart';

void main() {
  group('Company email policy', () {
    test('accepts the vintazk.com domain without case sensitivity', () {
      expect(isAllowedCompanyEmail('person@vintazk.com'), isTrue);
      expect(isAllowedCompanyEmail(' PERSON@VINTAZK.COM '), isTrue);
    });

    test('rejects other and lookalike domains', () {
      expect(isAllowedCompanyEmail('person@gmail.com'), isFalse);
      expect(isAllowedCompanyEmail('person@sub.vintazk.com'), isFalse);
      expect(isAllowedCompanyEmail('person@vintazk.com.example'), isFalse);
      expect(isAllowedCompanyEmail('@vintazk.com'), isFalse);
    });
  });

  group('Auth callback URLs', () {
    test('accepts Planner PKCE and implicit callbacks', () {
      expect(
        isPlannerAuthCallback(
          Uri.parse('planner://auth-callback?code=one-time-code'),
        ),
        isTrue,
      );
      expect(
        isPlannerAuthCallback(
          Uri.parse('planner://auth-callback#access_token=token'),
        ),
        isTrue,
      );
    });

    test('rejects unrelated and malformed Planner URLs', () {
      expect(
        isPlannerAuthCallback(
          Uri.parse('https://example.com/auth-callback?code=code'),
        ),
        isFalse,
      );
      expect(
        isPlannerAuthCallback(Uri.parse('planner://something-else?code=code')),
        isFalse,
      );
      expect(
        isPlannerAuthCallback(Uri.parse('planner://auth-callback')),
        isFalse,
      );
    });
  });

  group('Full name policy', () {
    test('accepts names up to 60 characters', () {
      expect(isValidFullName('Alex Rivera'), isTrue);
      expect(isValidFullName('A' * kMaxFullNameLength), isTrue);
    });

    test('rejects blank and overlong names', () {
      expect(isValidFullName('   '), isFalse);
      expect(isValidFullName('A' * (kMaxFullNameLength + 1)), isFalse);
    });
  });

  group('Password length policy', () {
    test('accepts passwords up to Supabase maximum', () {
      expect(
        () => requireValidPasswordLength('A' * kMaxPasswordLength),
        returnsNormally,
      );
    });

    test('rejects passwords over Supabase maximum', () {
      expect(
        () => requireValidPasswordLength('A' * (kMaxPasswordLength + 1)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('UserProfile', () {
    test('falls back to the email local-part when no name is set', () {
      const profile = UserProfile(
        id: 'u1',
        email: 'alex.rivera@example.com',
        fullName: '',
      );
      expect(profile.displayName, 'alex.rivera');
    });

    test('prefers the full name when present', () {
      const profile = UserProfile(
        id: 'u1',
        email: 'alex@example.com',
        fullName: 'Alex Rivera',
      );
      expect(profile.displayName, 'Alex Rivera');
    });

    test('builds initials from the first two name parts', () {
      const profile = UserProfile(
        id: 'u1',
        email: 'a@example.com',
        fullName: 'Alex Rivera',
      );
      expect(profile.initials, 'AR');
    });

    test('builds initials from a single-word name', () {
      const profile = UserProfile(
        id: 'u1',
        email: 'a@example.com',
        fullName: 'Alex',
      );
      expect(profile.initials, 'AL');
    });

    test('never throws on an empty profile', () {
      const profile = UserProfile(id: 'u1', email: '', fullName: '');
      expect(profile.initials, isNotEmpty);
    });
  });

  group('WorkspaceRole', () {
    test('viewers cannot edit; everyone else can', () {
      expect(WorkspaceRole.viewer.canEdit, isFalse);
      expect(WorkspaceRole.member.canEdit, isTrue);
      expect(WorkspaceRole.admin.canEdit, isTrue);
      expect(WorkspaceRole.owner.canEdit, isTrue);
    });

    test('only owners and admins manage members', () {
      expect(WorkspaceRole.owner.canManageMembers, isTrue);
      expect(WorkspaceRole.admin.canManageMembers, isTrue);
      expect(WorkspaceRole.member.canManageMembers, isFalse);
      expect(WorkspaceRole.viewer.canManageMembers, isFalse);
    });

    test('unknown role names fall back to member rather than throwing', () {
      expect(WorkspaceRole.fromName('bogus'), WorkspaceRole.member);
    });
  });

  group('PlannerTask dates', () {
    PlannerTask taskWith({DateTime? due}) {
      return PlannerTask(
        id: 't1',
        groupId: 'g1',
        boardId: 'b1',
        title: 'Test',
        priority: TaskPriority.medium,
        progress: 0.5,
        position: 0,
        dueDate: due,
      );
    }

    test('a past due date is overdue', () {
      final task = taskWith(
        due: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(task.isOverdue(), isTrue);
    });

    test('a completed task is never overdue', () {
      // Completion is the board's definition now, so the caller passes it in
      // rather than the task deciding for itself.
      final task = taskWith(
        due: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(task.isOverdue(done: true), isFalse);
    });

    test('a task with no due date is never overdue', () {
      expect(taskWith().isOverdue(), isFalse);
    });

    test("today's date is due today, not overdue", () {
      final task = taskWith(due: DateTime.now());
      expect(task.isDueToday, isTrue);
      expect(task.isOverdue(), isFalse);
    });

    test('a future due date is neither overdue nor due today', () {
      final task = taskWith(due: DateTime.now().add(const Duration(days: 3)));
      expect(task.isOverdue(), isFalse);
      expect(task.isDueToday, isFalse);
    });
  });

  group('PlannerTask.fromMap', () {
    test('parses a Supabase row', () {
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'board_id': 'b1',
        'title': 'Ship it',
        'status_id': 's-working',
        'assignee_ids': ['u1', 'u2'],
        'priority': 'high',
        'due_date': '2026-03-14',
        'progress': 0.25,
        'position': 2,
        'comment_count': 3,
      });

      expect(task.title, 'Ship it');
      expect(task.statusId, 's-working');
      expect(task.priority, TaskPriority.high);
      expect(task.dueDate, DateTime(2026, 3, 14));
      expect(task.commentCount, 3);
      // A task can carry several assignees; the old model held only one.
      expect(task.assigneeIds, ['u1', 'u2']);
    });

    test('tolerates missing optional fields', () {
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'title': 'Bare',
        'priority': 'nonsense',
      });

      // Unknown enum values fall back rather than throwing.
      expect(task.priority, TaskPriority.medium);
      expect(task.statusId, isNull);
      expect(task.assigneeIds, isEmpty);
      expect(task.dueDate, isNull);
      expect(task.progress, 0);
      expect(task.commentCount, 0);
    });
  });

  group('Board rollups', () {
    // The board defines its own statuses, so completion is looked up through
    // them rather than compared against a fixed enum value.
    const doneLabel = StatusLabel(
      id: 's-done',
      name: 'Done',
      color: Colors.green,
      position: 1,
      isDone: true,
    );
    const workingLabel = StatusLabel(
      id: 's-working',
      name: 'Working',
      color: Colors.orange,
      position: 0,
    );

    const done = PlannerTask(
      id: 't1',
      groupId: 'g1',
      boardId: 'b1',
      title: 'A',
      statusId: 's-done',
      priority: TaskPriority.low,
      progress: 1,
      position: 0,
    );
    const open = PlannerTask(
      id: 't2',
      groupId: 'g1',
      boardId: 'b1',
      title: 'B',
      statusId: 's-working',
      priority: TaskPriority.low,
      progress: 0.5,
      position: 1,
    );

    const board = Board(
      id: 'b1',
      name: 'Board',
      color: Colors.blue,
      statuses: [workingLabel, doneLabel],
      groups: [
        TaskGroup(
          id: 'g1',
          boardId: 'b1',
          name: 'Group',
          color: Colors.blue,
          tasks: [done, open],
        ),
        TaskGroup(
          id: 'g2',
          boardId: 'b1',
          name: 'Empty',
          color: Colors.blue,
          tasks: [],
        ),
      ],
    );

    test('counts tasks and completions across groups', () {
      expect(board.taskCount, 2);
      expect(board.doneCount, 1);
    });

    test('resolves a task status by id', () {
      expect(board.statusById('s-done')?.name, 'Done');
      expect(board.statusById(null), isNull);
      // A label deleted out from under a task leaves it unresolvable rather
      // than crashing.
      expect(board.statusById('s-gone'), isNull);
    });

    test('isDone reads the board label, not the task', () {
      expect(board.isDone(done), isTrue);
      expect(board.isDone(open), isFalse);
    });
  });

  group('Color helpers', () {
    test('avatar color is stable for the same seed', () {
      expect(avatarColor('user-1'), avatarColor('user-1'));
    });

    test('onAccent picks readable text for light and dark fills', () {
      expect(onAccent(const Color(0xFFFFF3B0)), plannerInk);
      expect(onAccent(const Color(0xFF1C1E2E)), Colors.white);
    });
  });
}
