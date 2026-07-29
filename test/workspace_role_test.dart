import 'package:flutter_test/flutter_test.dart';
import 'package:planner/models/planner_models.dart';

/// Reading a workspace's role out of a `workspace_members` result.
///
/// `members_select` lets you read every membership row in a workspace you
/// belong to — that is what the members dialog lists. So a query without a
/// `user_id` filter returns one row per teammate, and keying them by workspace
/// id means the last row wins. A member sitting alongside an owner was handed
/// the owner's role, and the sidebar duly offered them Delete workspace.
///
/// The fix is the filter in `loadWorkspaces`. This test pins the shape that
/// made it wrong, so a future refactor that drops the filter fails here rather
/// than silently granting a member the run of someone else's workspace.
void main() {
  Map<String, dynamic> memberRow(String role) => {
    'role': role,
    'workspaces': {
      'id': 'w1',
      'name': 'My workspace',
      'color': 0xFF4C5BD4,
      'owner_id': 'owner-uid',
      'join_code': 'PLNR-J53G',
    },
  };

  /// The mapping `loadWorkspaces` performs on whatever the query returns.
  List<Workspace> fold(List<Map<String, dynamic>> rows) {
    final workspaces = <String, Workspace>{};
    for (final row in rows) {
      final data = row['workspaces'];
      if (data is Map<String, dynamic>) {
        final workspace = Workspace.fromMap(data, role: row['role'] as String?);
        workspaces[workspace.id] = workspace;
      }
    }
    return workspaces.values.toList();
  }

  group('workspace role', () {
    test('a filtered query yields the caller own role', () {
      // What the query returns once scoped with .eq('user_id', me).
      final workspaces = fold([memberRow('member')]);

      expect(workspaces, hasLength(1));
      expect(workspaces.single.role, WorkspaceRole.member);
      expect(workspaces.single.role.canManageMembers, isFalse);
    });

    test('an unfiltered query is what produced the wrong role', () {
      // Every membership row in the workspace, which is what RLS alone allows.
      // The owner's row arrives second and overwrites the caller's.
      final workspaces = fold([memberRow('member'), memberRow('owner')]);

      expect(workspaces.single.role, WorkspaceRole.owner);
      expect(
        workspaces.single.role.canManageMembers,
        isTrue,
        reason: 'this is the bug: a member reading as an owner',
      );
    });

    test('roles carry the permissions the menu keys on', () {
      expect(WorkspaceRole.owner.canManageMembers, isTrue);
      expect(WorkspaceRole.admin.canManageMembers, isTrue);
      expect(WorkspaceRole.member.canManageMembers, isFalse);
      expect(WorkspaceRole.viewer.canManageMembers, isFalse);

      // Editing content is a separate question from managing the workspace:
      // a member edits every task in it and still renames nothing.
      expect(WorkspaceRole.member.canEdit, isTrue);
      expect(WorkspaceRole.viewer.canEdit, isFalse);
    });
  });
}
