import 'package:flutter/material.dart';

import '../../core/supabase/auth_service.dart';
import '../../core/supabase/planner_repository.dart';
import '../../models/planner_models.dart';
import '../../shared/utils/planner_colors.dart';
import '../../shared/widgets/user_avatar.dart';
import 'join_workspace_dialog.dart';

/// Manage who is in a workspace: current members, their roles, and pending
/// invitations.
Future<void> showMembersDialog({
  required BuildContext context,
  required Workspace workspace,
  required PlannerRepository repository,
  required String currentUserId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MembersDialog(
      workspace: workspace,
      repository: repository,
      currentUserId: currentUserId,
    ),
  );
}

class _MembersDialog extends StatefulWidget {
  const _MembersDialog({
    required this.workspace,
    required this.repository,
    required this.currentUserId,
  });

  final Workspace workspace;
  final PlannerRepository repository;
  final String currentUserId;

  @override
  State<_MembersDialog> createState() => _MembersDialogState();
}

class _MembersDialogState extends State<_MembersDialog> {
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  List<WorkspaceMember> _members = [];
  List<WorkspaceInvite> _invites = [];
  WorkspaceRole _inviteRole = WorkspaceRole.member;
  bool _loading = true;
  bool _inviting = false;
  String? _error;
  late String _joinCode = widget.workspace.joinCode;

  Future<void> _regenerateCode() async {
    try {
      final fresh = await widget.repository.regenerateJoinCode(
        widget.workspace.id,
      );
      if (mounted) {
        setState(() => _joinCode = fresh);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  bool get _canManage => widget.workspace.role.canManageMembers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final members = await widget.repository.loadMembers(widget.workspace.id);
      final invites = await widget.repository.loadInvites(widget.workspace.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _members = members;
        _invites = invites;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _invite() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final email = _emailController.text.trim().toLowerCase();

    // Catch the common case before hitting the network.
    if (_members.any((m) => m.profile.email.toLowerCase() == email)) {
      setState(() => _error = 'That person is already a member.');
      return;
    }

    setState(() {
      _inviting = true;
      _error = null;
    });

    try {
      await widget.repository.inviteMember(
        workspaceId: widget.workspace.id,
        email: email,
        role: _inviteRole,
      );
      _emailController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Invited $email')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }

  Future<void> _removeMember(WorkspaceMember member) async {
    setState(() => _error = null);
    try {
      await widget.repository.removeMember(
        workspaceId: widget.workspace.id,
        userId: member.profile.id,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _changeRole(WorkspaceMember member, WorkspaceRole role) async {
    try {
      await widget.repository.changeMemberRole(
        workspaceId: widget.workspace.id,
        userId: member.profile.id,
        role: role,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _revokeInvite(WorkspaceInvite invite) async {
    try {
      await widget.repository.revokeInvite(invite.id);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: JoinCodeCard(
                code: _joinCode,
                canManage: _canManage,
                onRegenerate: _regenerateCode,
              ),
            ),
            if (_canManage) _buildInviteRow(),
            if (_error != null) _buildError(),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : _buildList(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint(widget.workspace.color, 0.12),
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            child: Icon(
              Icons.groups_outlined,
              size: 18,
              color: widget.workspace.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.workspace.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _canManage
                      ? 'Invite teammates and manage their access'
                      : 'People with access to this workspace',
                  style: const TextStyle(color: plannerMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onFieldSubmitted: (_) => _inviting ? null : _invite(),
                decoration: const InputDecoration(
                  hintText: 'teammate@vintazk.com',
                  prefixIcon: Icon(
                    Icons.mail_outline_rounded,
                    size: 17,
                    color: plannerFaint,
                  ),
                  prefixIconConstraints: BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                ),
                validator: (value) {
                  final email = (value ?? '').trim();
                  if (email.isEmpty) {
                    return 'Enter an email to invite.';
                  }
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                    return 'That does not look like an email address.';
                  }
                  if (!isAllowedCompanyEmail(email)) {
                    return 'Use an @vintazk.com email address.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            _RolePicker(
              role: _inviteRole,
              // Ownership transfers are not part of inviting.
              options: const [
                WorkspaceRole.admin,
                WorkspaceRole.member,
                WorkspaceRole.viewer,
              ],
              onChanged: (role) => setState(() => _inviteRole = role),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 42,
              child: FilledButton(
                onPressed: _inviting ? null : _invite,
                child: _inviting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Invite'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: tint(plannerRed, 0.07),
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: tint(plannerRed, 0.25)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 15,
              color: plannerRed,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(
                  color: plannerRed,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionLabel('Members · ${_members.length}'),
        for (final member in _members)
          _MemberRow(
            member: member,
            isSelf: member.profile.id == widget.currentUserId,
            canManage: _canManage && member.role != WorkspaceRole.owner,
            onRemove: () => _removeMember(member),
            onRoleChanged: (role) => _changeRole(member, role),
          ),
        if (_invites.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SectionLabel('Pending invitations · ${_invites.length}'),
          for (final invite in _invites)
            _InviteRow(
              invite: invite,
              canManage: _canManage,
              onRevoke: () => _revokeInvite(invite),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: plannerFaint,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isSelf,
    required this.canManage,
    required this.onRemove,
    required this.onRoleChanged,
  });

  final WorkspaceMember member;
  final bool isSelf;
  final bool canManage;
  final VoidCallback onRemove;
  final ValueChanged<WorkspaceRole> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
      child: Row(
        children: [
          UserAvatar(profile: member.profile, size: 32),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.profile.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: plannerInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: plannerDivider,
                          borderRadius: BorderRadius.circular(radiusXs),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            color: plannerMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  member.profile.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: plannerMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (canManage && !isSelf)
            _RolePicker(
              role: member.role,
              options: const [
                WorkspaceRole.admin,
                WorkspaceRole.member,
                WorkspaceRole.viewer,
              ],
              onChanged: onRoleChanged,
            )
          else
            _RoleBadge(role: member.role),
          if (canManage && !isSelf)
            IconButton(
              tooltip: 'Remove from workspace',
              icon: const Icon(Icons.close_rounded, size: 16),
              color: plannerFaint,
              onPressed: onRemove,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.invite,
    required this.canManage,
    required this.onRevoke,
  });

  final WorkspaceInvite invite;
  final bool canManage;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: plannerSurface,
              shape: BoxShape.circle,
              border: Border.all(color: plannerBorder),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              size: 15,
              color: plannerFaint,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  invite.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Text(
                  'Joins when they sign in with this email',
                  style: TextStyle(color: plannerFaint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          _RoleBadge(role: invite.role),
          if (canManage)
            IconButton(
              tooltip: 'Revoke invitation',
              icon: const Icon(Icons.close_rounded, size: 16),
              color: plannerFaint,
              onPressed: onRevoke,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final WorkspaceRole role;

  @override
  Widget build(BuildContext context) {
    final color = role == WorkspaceRole.owner ? plannerViolet : plannerMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tint(color, 0.09),
        borderRadius: BorderRadius.circular(radiusXs),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.role,
    required this.options,
    required this.onChanged,
  });

  final WorkspaceRole role;
  final List<WorkspaceRole> options;
  final ValueChanged<WorkspaceRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<WorkspaceRole>(
      tooltip: 'Change role',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            height: 40,
            child: Row(
              children: [
                Icon(
                  option == role
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 15,
                  color: option == role ? plannerBlue : plannerFaint,
                ),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      switch (option) {
                        WorkspaceRole.owner => 'Full control',
                        WorkspaceRole.admin => 'Manage people and content',
                        WorkspaceRole.member => 'Create and edit content',
                        WorkspaceRole.viewer => 'Read-only access',
                      },
                      style: const TextStyle(color: plannerFaint, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: plannerCard,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: plannerBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              role.label,
              style: const TextStyle(
                color: plannerText,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: plannerFaint,
            ),
          ],
        ),
      ),
    );
  }
}
