import 'package:flutter/material.dart';

import '../../core/supabase/auth_service.dart';
import '../../core/supabase/planner_repository.dart';
import '../../models/planner_models.dart';
import '../../shared/utils/password_rules.dart';
import '../../shared/utils/planner_colors.dart';

/// Your own account: the name teammates see, and the password you sign in
/// with.
///
/// The two live together because they are the only things about yourself you
/// can change, but they behave differently on purpose. A password is yours
/// alone and can be changed whenever you like. A name is shared — it is how
/// every comment, mention and assignment you have ever made is attributed — so
/// it is rate limited to one change a week.
Future<bool?> showAccountDialog(
  BuildContext context, {
  required AuthService auth,
  required PlannerRepository repository,
  required String currentName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _AccountDialog(
      auth: auth,
      repository: repository,
      currentName: currentName,
    ),
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.auth,
    required this.repository,
    required this.currentName,
  });

  final AuthService auth;
  final PlannerRepository repository;
  final String currentName;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

/// Which half of the dialog is on screen.
///
/// Tabs rather than one long column: the two tasks are unrelated, and stacking
/// them meant a password field sitting under a name field, which reads as one
/// form where saving the top half might submit the bottom.
enum _Tab { profile, security }

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.currentName,
  );
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();

  _Tab _tab = _Tab.profile;

  /// Null until the cooldown has been read. The name field stays disabled
  /// until then rather than flickering from editable to locked.
  NameChangeStatus? _nameStatus;

  bool _savingName = false;
  bool _savingPassword = false;
  String? _nameError;
  String? _passwordError;
  String? _nameSuccess;
  String? _passwordSuccess;
  bool _showPasswords = false;
  bool _nameWasChanged = false;

  @override
  void initState() {
    super.initState();
    _loadNameStatus();
    // Redraw as they type: the strength meter, the requirement ticks, and
    // whether Save has anything to do.
    _name.addListener(_redraw);
    _newPassword.addListener(_redraw);
    _confirmPassword.addListener(_redraw);
    _currentPassword.addListener(_redraw);
  }

  void _redraw() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _loadNameStatus() async {
    final status = await widget.repository.nameChangeStatus();
    if (mounted) {
      setState(() => _nameStatus = status);
    }
  }

  bool get _nameEdited => _name.text.trim() != widget.currentName.trim();
  bool get _nameLocked =>
      _nameStatus != null && !_nameStatus!.canChangeNow;

  Future<void> _saveName() async {
    final next = _name.text.trim();
    setState(() {
      _nameError = null;
      _nameSuccess = null;
    });

    if (!isValidFullName(next)) {
      setState(
        () => _nameError =
            'Enter a name between 1 and $kMaxFullNameLength characters.',
      );
      return;
    }

    setState(() => _savingName = true);
    try {
      await widget.repository.updateMyProfile(fullName: next);
      if (!mounted) {
        return;
      }
      // Re-read rather than assume: the cooldown starts now, and the date it
      // ends comes from the database that just stamped it.
      await _loadNameStatus();
      if (mounted) {
        setState(() {
          _savingName = false;
          _nameWasChanged = true;
          _nameSuccess = 'Your name has been updated.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _savingName = false;
          _nameError = _describe(error);
        });
      }
    }
  }

  Future<void> _savePassword() async {
    setState(() {
      _passwordError = null;
      _passwordSuccess = null;
    });

    final current = _currentPassword.text;
    final next = _newPassword.text;

    if (current.isEmpty) {
      setState(() => _passwordError = 'Enter your current password.');
      return;
    }
    if (!PasswordCheck.of(next).isValid) {
      setState(
        () => _passwordError = 'Your new password does not meet the '
            'requirements below.',
      );
      return;
    }
    if (next != _confirmPassword.text) {
      setState(() => _passwordError = 'The two new passwords do not match.');
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await widget.auth.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) {
        return;
      }
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      setState(() {
        _savingPassword = false;
        _passwordSuccess = 'Your password has been changed.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _savingPassword = false;
          _passwordError = _describe(error);
        });
      }
    }
  }

  /// Turns a raw exception into the one sentence written for a person.
  String _describe(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
    // Postgres prefixes the trigger's message with its own noise; the
    // cooldown sentence inside it is the part worth showing.
    final cooldown = RegExp(
      r'You can change your name again on [^.]+\.',
    ).firstMatch(raw);
    return cooldown?.group(0) ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.auth.currentUser?.email ?? '';
    final viewport = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: plannerCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: viewport.height - 80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Identity(name: widget.currentName, email: email),
            _Tabs(
              current: _tab,
              onChanged: (tab) => setState(() => _tab = tab),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                child: _tab == _Tab.profile
                    ? _buildProfile()
                    : _buildSecurity(),
              ),
            ),
            const Divider(height: 1, color: plannerBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    // True tells the caller the name changed, so it can refresh
                    // the navbar and member lists without a full reload.
                    onPressed: () =>
                        Navigator.of(context).pop(_nameWasChanged),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === Profile ===

  Widget _buildProfile() {
    final status = _nameStatus;
    final ready = status != null;
    final canSave =
        ready && !_nameLocked && !_savingName && _nameEdited;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FieldLabel('Display name'),
        const SizedBox(height: 7),
        TextField(
          controller: _name,
          enabled: ready && !_nameLocked && !_savingName,
          maxLength: kMaxFullNameLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Your name',
            counterText: '',
            prefixIcon: const Icon(
              Icons.badge_outlined,
              size: 18,
              color: plannerFaint,
            ),
            // The count only matters as the limit approaches, so it appears
            // then rather than sitting there as permanent clutter.
            suffixText: _name.text.length > kMaxFullNameLength - 15
                ? '${_name.text.length}/$kMaxFullNameLength'
                : null,
            suffixStyle: const TextStyle(color: plannerFaint, fontSize: 11),
          ),
          onSubmitted: (_) => canSave ? _saveName() : null,
        ),
        const SizedBox(height: 12),
        _CooldownCard(status: status),
        if (_nameError != null) ...[
          const SizedBox(height: 12),
          _Banner(_nameError!, tone: plannerRed),
        ],
        if (_nameSuccess != null) ...[
          const SizedBox(height: 12),
          _Banner(_nameSuccess!, tone: plannerGreen),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: canSave ? _saveName : null,
            icon: _savingName
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 17),
            label: Text(_savingName ? 'Saving…' : 'Save changes'),
          ),
        ),
      ],
    );
  }

  // === Security ===

  Widget _buildSecurity() {
    final check = PasswordCheck.of(_newPassword.text);
    final confirm = _confirmPassword.text;
    final matches = confirm.isNotEmpty && confirm == _newPassword.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FieldLabel('Current password'),
        const SizedBox(height: 7),
        TextField(
          controller: _currentPassword,
          obscureText: !_showPasswords,
          enabled: !_savingPassword,
          decoration: InputDecoration(
            hintText: 'Enter your current password',
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: plannerFaint,
            ),
            suffixIcon: IconButton(
              tooltip: _showPasswords ? 'Hide passwords' : 'Show passwords',
              icon: Icon(
                _showPasswords
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: plannerMuted,
              ),
              onPressed: () =>
                  setState(() => _showPasswords = !_showPasswords),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('New password'),
        const SizedBox(height: 7),
        TextField(
          controller: _newPassword,
          obscureText: !_showPasswords,
          enabled: !_savingPassword,
          maxLength: kMaxPasswordLength,
          decoration: const InputDecoration(
            hintText: 'Choose a new password',
            counterText: '',
            prefixIcon: Icon(
              Icons.key_outlined,
              size: 18,
              color: plannerFaint,
            ),
          ),
        ),
        if (_newPassword.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          _StrengthMeter(check: check),
          const SizedBox(height: 12),
          _Requirements(check: check),
        ],
        const SizedBox(height: 18),
        const _FieldLabel('Confirm new password'),
        const SizedBox(height: 7),
        TextField(
          controller: _confirmPassword,
          obscureText: !_showPasswords,
          enabled: !_savingPassword,
          maxLength: kMaxPasswordLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Type it again',
            counterText: '',
            prefixIcon: const Icon(
              Icons.key_outlined,
              size: 18,
              color: plannerFaint,
            ),
            // Answered inline, so a mismatch is caught while typing rather
            // than after pressing the button.
            suffixIcon: confirm.isEmpty
                ? null
                : Icon(
                    matches
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: matches ? plannerGreen : plannerRed,
                  ),
          ),
          onSubmitted: (_) => _savingPassword ? null : _savePassword(),
        ),
        if (_passwordError != null) ...[
          const SizedBox(height: 12),
          _Banner(_passwordError!, tone: plannerRed),
        ],
        if (_passwordSuccess != null) ...[
          const SizedBox(height: 12),
          _Banner(_passwordSuccess!, tone: plannerGreen),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _savingPassword ? null : _savePassword,
            icon: _savingPassword
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_reset_rounded, size: 17),
            label: Text(_savingPassword ? 'Changing…' : 'Change password'),
          ),
        ),
      ],
    );
  }
}

/// Who you are, across the top. Grounds the dialog in the account being
/// edited — useful on a shared machine, where "whose password am I changing?"
/// is a real question.
class _Identity extends StatelessWidget {
  const _Identity({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final display = name.trim().isEmpty ? _localPart(email) : name.trim();
    final initial = display.trim().isEmpty
        ? '?'
        : display.trim().substring(0, 1).toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint(plannerBlue, 0.13), tint(plannerViolet, 0.09)],
        ),
        border: const Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: avatarColor(email),
              shape: BoxShape.circle,
              boxShadow: shadowLg,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerMuted,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(
              Icons.close_rounded,
              size: 19,
              color: plannerMuted,
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  static String _localPart(String email) {
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onChanged});

  final _Tab current;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _TabButton(
            icon: Icons.person_outline_rounded,
            label: 'Profile',
            selected: current == _Tab.profile,
            onTap: () => onChanged(_Tab.profile),
          ),
          _TabButton(
            icon: Icons.shield_outlined,
            label: 'Security',
            selected: current == _Tab.security,
            onTap: () => onChanged(_Tab.security),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = selected ? plannerBlue : plannerMuted;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? plannerBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: tone),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: tone,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The seven-day rule, stated before it is hit rather than after.
class _CooldownCard extends StatelessWidget {
  const _CooldownCard({required this.status});

  final NameChangeStatus? status;

  @override
  Widget build(BuildContext context) {
    final value = status;
    final locked = value != null && !value.canChangeNow;
    final tone = locked ? plannerYellow : plannerBlue;

    final String text;
    if (value == null) {
      text = 'Checking when you can change your name…';
    } else if (locked) {
      final days = value.daysRemaining;
      text = days <= 1
          ? 'You changed your name recently. You can change it again tomorrow.'
          : 'You changed your name recently. You can change it again in '
                '$days days.';
    } else {
      text =
          'This is how teammates see you on every board, comment and mention. '
          'You can change it once every 7 days.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint(tone, 0.07),
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: tint(tone, 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            locked ? Icons.lock_clock_rounded : Icons.info_outline_rounded,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: plannerText,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.check});

  final PasswordCheck check;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 4,
              decoration: BoxDecoration(
                color: i < check.score ? check.color : plannerBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 5),
        ],
        const SizedBox(width: 10),
        SizedBox(
          width: 54,
          child: Text(
            check.label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: check.color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// What the password still needs, ticked off as it is met.
class _Requirements extends StatelessWidget {
  const _Requirements({required this.check});

  final PasswordCheck check;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Rule(met: check.hasLength, text: 'At least 8 characters'),
        const SizedBox(height: 4),
        _Rule(met: check.hasLetter, text: 'Contains a letter'),
        const SizedBox(height: 4),
        _Rule(
          met: check.hasNumberOrSymbol,
          text: 'Contains a number or symbol',
        ),
        const SizedBox(height: 4),
        _Rule(
          met: check.isLong,
          text: '12 or more characters (recommended)',
          optional: true,
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({
    required this.met,
    required this.text,
    this.optional = false,
  });

  final bool met;
  final String text;

  /// A suggestion rather than a rule, so an unmet one is not an error.
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final color = met
        ? plannerGreen
        : (optional ? plannerFaint : plannerMuted);

    return Row(
      children: [
        Icon(
          met
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: met ? plannerText : color,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tint(tone, 0.09),
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: tint(tone, 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tone == plannerRed
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: tone == plannerRed ? plannerRed : plannerText,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: plannerText,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
