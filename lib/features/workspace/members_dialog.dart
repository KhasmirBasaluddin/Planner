import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../core/supabase/auth_service.dart';
import '../../core/supabase/planner_repository.dart';
import '../../models/planner_models.dart';
import '../../shared/utils/planner_colors.dart';
import '../../shared/utils/text_rules.dart';
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

  /// People matching what has been typed. Already-members and already-invited
  /// are filtered out server-side, so everything here can be invited.
  List<UserProfile> _matches = [];
  Timer? _searchDebounce;

  WorkspaceRole _inviteRole = WorkspaceRole.member;
  bool _loading = true;
  bool _inviting = false;
  bool _searching = false;
  String? _error;
  late String _joinCode = widget.workspace.joinCode;
  RealtimeChannel? _teamChannel;

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
    // Membership and invitations are live: a teammate joining by code, an
    // invitation being answered, or another admin changing a role all show up
    // here without anyone reopening the dialog.
    _teamChannel = widget.repository.subscribeToTeam(
      workspaceId: widget.workspace.id,
      onChange: () {
        if (mounted) {
          _load();
        }
      },
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _emailController.dispose();
    final channel = _teamChannel;
    if (channel != null) {
      widget.repository.unsubscribe(channel);
    }
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

  /// Looks up people as the user types.
  ///
  /// Debounced: a request per keystroke would be several per word, and the
  /// server refuses anything under two characters anyway.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _matches = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final matches = await widget.repository.searchInvitableUsers(
          workspaceId: widget.workspace.id,
          query: query,
        );
        if (mounted && _emailController.text.trim() == query) {
          setState(() {
            _matches = matches;
            _searching = false;
          });
        }
      } catch (_) {
        // A failed lookup should not block inviting by email, which still
        // works for someone who has no account yet.
        if (mounted) {
          setState(() {
            _matches = [];
            _searching = false;
          });
        }
      }
    });
  }

  /// Invites someone who already has an account, linked by id rather than by
  /// a string that has to match later.
  Future<void> _inviteUser(UserProfile profile) async {
    setState(() {
      _inviting = true;
      _error = null;
    });

    try {
      await widget.repository.inviteUser(
        workspaceId: widget.workspace.id,
        userId: profile.id,
        role: _inviteRole,
      );
      _emailController.clear();
      setState(() => _matches = []);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Invited ${profile.displayName}')),
          );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _describe(error));
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }

  /// Invites by raw email, for someone who has not signed up yet — the one
  /// case where there is no account to point at.
  Future<void> _invite() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final email = _emailController.text.trim().toLowerCase();

    // If they do have an account, link the invitation to it rather than
    // leaving it addressed to a string.
    final known = _matches
        .where((profile) => profile.email.toLowerCase() == email)
        .firstOrNull;
    if (known != null) {
      await _inviteUser(known);
      return;
    }

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
      setState(() => _matches = []);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Invited $email')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _describe(error));
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }

  /// StateError carries a message written for the user; anything else does not.
  String _describe(Object error) {
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
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
            // The join code grants access to anyone holding it, so it belongs
            // with the people who decide who has access. Showing it to members
            // let them hand out entry to a workspace they cannot manage.
            if (_canManage) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: JoinCodeCard(
                  code: _joinCode,
                  canManage: _canManage,
                  onRegenerate: _regenerateCode,
                ),
              ),
              _buildInviteRow(),
            ] else
              const SizedBox(height: 4),
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
    final typed = _emailController.text.trim();
    // Only offer the raw-email fallback once what has been typed actually looks
    // like an address and matches nobody — otherwise it reads as a suggestion
    // to invite a half-finished string.
    final showEmailFallback =
        typed.contains('@') &&
        !_searching &&
        _matches.every((p) => p.email.toLowerCase() != typed.toLowerCase());

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    // A search term with an emoji in it can never match a
                    // name or an email, neither of which may contain one.
                    inputFormatters: [emojiFreeFormatter],
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: _onSearchChanged,
                    onFieldSubmitted: (_) => _inviting ? null : _invite(),
                    decoration: InputDecoration(
                      hintText: 'Search by name, or type an email',
                      prefixIcon: const Icon(
                        Icons.person_search_outlined,
                        size: 17,
                        color: plannerFaint,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: plannerFaint,
                                ),
                              ),
                            )
                          : null,
                    ),
                    validator: (value) {
                      final email = (value ?? '').trim();
                      if (email.isEmpty) {
                        return 'Search for a teammate, or enter an email.';
                      }
                      // Only an address needs validating; picking someone from
                      // the list never runs this.
                      if (!RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(email)) {
                        return 'Pick someone from the list, or enter a full '
                            'email address.';
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
            if (_matches.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 176),
                decoration: BoxDecoration(
                  color: plannerCard,
                  borderRadius: BorderRadius.circular(radiusSm),
                  border: Border.all(color: plannerBorder),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _matches.length,
                  itemBuilder: (context, index) {
                    final profile = _matches[index];
                    return InkWell(
                      onTap: _inviting ? null : () => _inviteUser(profile),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            UserAvatar(
                              profile: profile,
                              size: 28,
                              showTooltip: false,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: plannerInk,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    profile.email,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: plannerMuted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.add_circle_outline_rounded,
                              size: 17,
                              color: plannerBlue,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (showEmailFallback) ...[
              const SizedBox(height: 6),
              Text(
                _matches.isEmpty
                    ? 'Nobody here by that name. Invite $typed by email — they '
                          'will join when they sign up.'
                    : 'Or invite $typed by email.',
                style: const TextStyle(color: plannerMuted, fontSize: 11.5),
              ),
            ],
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
