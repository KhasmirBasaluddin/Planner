import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/supabase/auth_service.dart';
import '../../shared/utils/planner_colors.dart';
import '../../shared/utils/text_rules.dart';

enum _AuthMode { signIn, signUp, reset }

/// Password rules for new accounts.
///
/// Length does more for real-world strength than character-class rules, so the
/// floor is 8 with a nudge toward longer, and the mix requirement is kept mild
/// rather than the usual "one of each of four types" — that pattern reliably
/// produces `Password1!` and nothing safer.
class _PasswordCheck {
  const _PasswordCheck({
    required this.hasLength,
    required this.hasLetter,
    required this.hasNumberOrSymbol,
    required this.isLong,
  });

  factory _PasswordCheck.of(String value) {
    return _PasswordCheck(
      hasLength: value.length >= 8,
      hasLetter: RegExp(r'[A-Za-z]').hasMatch(value),
      hasNumberOrSymbol: RegExp(r'[0-9\W_]').hasMatch(value),
      isLong: value.length >= 12,
    );
  }

  final bool hasLength;
  final bool hasLetter;
  final bool hasNumberOrSymbol;
  final bool isLong;

  bool get isValid => hasLength && hasLetter && hasNumberOrSymbol;

  /// 0–3, for the strength meter.
  int get score {
    if (!isValid) {
      return hasLength || hasLetter ? 1 : 0;
    }
    return isLong ? 3 : 2;
  }

  String get label => switch (score) {
    0 => 'Too short',
    1 => 'Weak',
    2 => 'Good',
    _ => 'Strong',
  };

  Color get color => switch (score) {
    0 || 1 => plannerRed,
    2 => plannerYellow,
    _ => plannerGreen,
  };
}

/// Sign-in / sign-up / password reset, presented as a split screen: a branded
/// panel that sells the product on the left, and the form on the right. On
/// narrow windows the panel drops away and the form takes over.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _obscure = true;
  bool _staySignedIn = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _switchTo(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _notice = null;
      _confirmController.clear();
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      switch (_mode) {
        case _AuthMode.signIn:
          await widget.auth.signIn(
            email: _emailController.text,
            password: _passwordController.text,
            staySignedIn: _staySignedIn,
          );
        // The auth state stream drives navigation; nothing to do here.
        // Invitations are not claimed on sign-in — they wait in the
        // notification centre for an explicit accept or decline.

        case _AuthMode.signUp:
          final response = await widget.auth.signUp(
            email: _emailController.text,
            password: _passwordController.text,
            fullName: _nameController.text,
          );
          if (response.session == null && mounted) {
            // Email confirmation is on for this project.
            setState(() {
              _mode = _AuthMode.signIn;
              _notice =
                  'Account created. Check ${_emailController.text.trim()} '
                  'for a confirmation link, then sign in.';
            });
          }

        case _AuthMode.reset:
          await widget.auth.sendPasswordReset(_emailController.text);
          if (mounted) {
            setState(() {
              _mode = _AuthMode.signIn;
              _notice =
                  'If an account exists for ${_emailController.text.trim()}, '
                  'a reset link is on its way.';
            });
          }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = describeAuthError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 940;
          return Row(
            children: [
              if (wide) const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(
                flex: wide ? 4 : 1,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 48,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: _buildForm(showLogo: !wide),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm({required bool showLogo}) {
    final isSignUp = _mode == _AuthMode.signUp;
    final isReset = _mode == _AuthMode.reset;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLogo) ...[
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/planner.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Planner',
                  style: TextStyle(
                    color: plannerInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
          Text(
            switch (_mode) {
              _AuthMode.signIn => 'Welcome back',
              _AuthMode.signUp => 'Create your account',
              _AuthMode.reset => 'Reset your password',
            },
            style: const TextStyle(
              color: plannerInk,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_mode) {
              _AuthMode.signIn =>
                'Sign in to pick up where your team left off.',
              _AuthMode.signUp =>
                'Use your @vintazk.com email to join your team.',
              _AuthMode.reset =>
                'Enter your email and we will send you a reset link.',
            },
            style: const TextStyle(
              color: plannerMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          if (_notice != null) ...[
            _Banner(
              message: _notice!,
              color: plannerGreen,
              icon: Icons.check_circle_outline_rounded,
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            _Banner(
              message: _error!,
              color: plannerRed,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: 16),
          ],

          if (isSignUp) ...[
            const _FieldLabel('Full name'),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              maxLength: kMaxFullNameLength,
              decoration: const InputDecoration(hintText: 'Juan Dela Cruz'),
              // Pasted emoji are dropped rather than rejected: the paste is
              // usually a name with one stray character in it, and silently
              // keeping the name beats refusing the whole thing.
              inputFormatters: [emojiFreeFormatter],
              validator: (value) {
                final name = (value ?? '').trim();
                if (name.isEmpty) {
                  return 'Tell us what to call you.';
                }
                if (name.length > kMaxFullNameLength) {
                  return 'Use $kMaxFullNameLength characters or fewer.';
                }
                return validateNoEmoji(name, what: 'name');
              },
            ),
            const SizedBox(height: 16),
          ],

          const _FieldLabel('Email'),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            inputFormatters: [emojiFreeFormatter],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'you@vintazk.com'),
            validator: (value) {
              final email = (value ?? '').trim();
              if (email.isEmpty) {
                return 'Enter your email address.';
              }
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'That does not look like an email address.';
              }
              // The pattern above only excludes whitespace and stray @, so an
              // address with an emoji in the local part slips through it.
              final emojiError = validateNoEmoji(email, what: 'email address');
              if (emojiError != null) {
                return emojiError;
              }
              if (!isAllowedCompanyEmail(email)) {
                return 'Use your @vintazk.com email address.';
              }
              return null;
            },
          ),

          if (!isReset) ...[
            const SizedBox(height: 16),
            const _FieldLabel('Password'),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              maxLength: isSignUp ? kMaxPasswordLength : null,
              autofillHints: [
                isSignUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                hintText: isSignUp ? 'At least 6 characters' : '••••••••',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: plannerMuted,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: isSignUp
                  ? (value) =>
                        setState(() {}) // refresh the strength meter
                  : null,
              validator: (value) {
                final password = value ?? '';
                if (password.isEmpty) {
                  return 'Enter your password.';
                }
                if (isSignUp && password.length > kMaxPasswordLength) {
                  return 'Use $kMaxPasswordLength characters or fewer.';
                }
                // Signup only, and no formatter on this field. Someone whose
                // existing password contains an emoji must still be able to
                // type it to sign in — stripping it here would lock them out
                // of their own account with no way to tell why.
                if (isSignUp && containsEmoji(password)) {
                  return 'Emoji are not allowed in a password.';
                }
                if (isSignUp && !_PasswordCheck.of(password).isValid) {
                  return 'Use at least 8 characters, with a letter and a '
                      'number or symbol.';
                }
                return null;
              },
            ),

            // Below the field, not beside the label: a reset link belongs after
            // the thing you just failed to remember, and pairing it with the
            // label crowds them into the same line.
            if (_mode == _AuthMode.signIn) ...[
              const SizedBox(height: 8),
              _LinkButton(
                label: 'Forgot your password?',
                onPressed: () => _switchTo(_AuthMode.reset),
              ),
            ],

            // Strength feedback while choosing a password. Shown only once
            // there is something to judge, so an empty form is not scolding.
            if (isSignUp && _passwordController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              _StrengthMeter(
                check: _PasswordCheck.of(_passwordController.text),
              ),
            ],

            // Confirm field: catches the typo that would otherwise lock someone
            // out of an account they just created.
            if (isSignUp) ...[
              const SizedBox(height: 16),
              const _FieldLabel('Confirm password'),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscure,
                maxLength: kMaxPasswordLength,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _busy ? null : _submit(),
                decoration: const InputDecoration(hintText: 'Type it again'),
                validator: (value) {
                  if ((value ?? '').isEmpty) {
                    return 'Confirm your password.';
                  }
                  if (value != _passwordController.text) {
                    return 'These passwords do not match.';
                  }
                  // Only reachable on signup, where the password field rejects
                  // emoji too — but checked here as well so the two fields
                  // cannot disagree about what a valid password is.
                  return validateNoEmoji(value, what: 'password');
                },
              ),
            ],
          ],

          // Session length. Supabase refreshes tokens silently while this is
          // on, so the practical effect is staying signed in until sign-out.
          if (_mode == _AuthMode.signIn) ...[
            const SizedBox(height: 14),
            _StaySignedIn(
              value: _staySignedIn,
              onChanged: (value) => setState(() => _staySignedIn = value),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(switch (_mode) {
                      _AuthMode.signIn => 'Sign in',
                      _AuthMode.signUp => 'Create account',
                      _AuthMode.reset => 'Send reset link',
                    }),
            ),
          ),

          const SizedBox(height: 20),
          Center(
            child: switch (_mode) {
              _AuthMode.signIn => _SwitchPrompt(
                question: "Don't have an account?",
                action: 'Sign up',
                onPressed: () => _switchTo(_AuthMode.signUp),
              ),
              _AuthMode.signUp => _SwitchPrompt(
                question: 'Already have an account?',
                action: 'Sign in',
                onPressed: () => _switchTo(_AuthMode.signIn),
              ),
              _AuthMode.reset => _SwitchPrompt(
                question: 'Remembered it?',
                action: 'Back to sign in',
                onPressed: () => _switchTo(_AuthMode.signIn),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// The left half of the split screen.
///
/// Rather than asserting that the product keeps a team in sync, this shows it:
/// a board whose rows advance on a timer, with an activity feed naming who did
/// what. The claim and the demonstration are the same object.
class _BrandPanel extends StatefulWidget {
  const _BrandPanel();

  @override
  State<_BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<_BrandPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Slow on purpose — this sits behind a login form and should never pull
  /// focus from the fields.
  static const _stepDuration = Duration(milliseconds: 2600);

  int _step = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _stepDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _step = (_step + 1) % _script.length);
          _controller.forward(from: 0);
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _script[_step];

    return ColoredBox(
      // Warm paper rather than the dark gradient this kind of panel usually
      // gets. It matches the email templates, so the product reads the same
      // from inbox to app, and light is simply rarer here — which does more for
      // distinctiveness than any amount of gradient work.
      color: _paper,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _PaperPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 40, 46, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.asset(
                        'assets/images/planner.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Planner',
                      style: TextStyle(
                        color: _paperInk,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    // Set like the header of a printed page.
                    Text(
                      'TODAY',
                      style: TextStyle(
                        color: _paperInkFaint.withValues(alpha: 0.8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),

                const Spacer(flex: 2),

                // Printed type with the final phrase written in by hand — the
                // mix is what sells the page as something worked on rather than
                // produced. All-handwriting would cost too much legibility.
                const Text(
                  'A plan that keeps',
                  style: TextStyle(
                    color: _paperInk,
                    fontSize: 36,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      'itself ',
                      style: TextStyle(
                        color: _paperInk,
                        fontSize: 36,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                      ),
                    ),
                    Text(
                      'up to date.',
                      style: GoogleFonts.caveat(
                        color: _paperMargin,
                        fontSize: 42,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SizedBox(
                  width: 330,
                  child: Text(
                    'Every change your team makes lands here instantly — no '
                    'refresh, no guessing which version is current.',
                    style: TextStyle(
                      color: _paperInkSoft,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                _LiveBoard(frame: frame),
                const SizedBox(height: 14),
                _ActivityLine(frame: frame),

                const Spacer(flex: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One frame of the looping demo.
class _BoardFrame {
  const _BoardFrame({
    required this.rows,
    required this.actor,
    required this.action,
    required this.actorColor,
  });

  final List<_BoardRow> rows;
  final String actor;
  final String action;
  final Color actorColor;
}

class _BoardRow {
  const _BoardRow(
    this.title,
    this.status,
    this.progress, {
    this.justChanged = false,
  });

  final String title;
  final _DemoStatus status;
  final double progress;

  /// Highlights the row that moved in this frame.
  final bool justChanged;
}

/// The three states this animation cycles through.
///
/// Local to the sign-in screen on purpose. Real statuses are defined per board
/// and live in the database; this is a scripted illustration shown to someone
/// who has not signed in yet, so it has no board to read them from.
enum _DemoStatus {
  notStarted('not started', plannerSlate),
  working('working', plannerYellow),
  done('done', plannerGreen);

  const _DemoStatus(this.label, this.color);
  final String label;
  final Color color;
}

/// A short scripted sequence: work progresses, and each step is attributed to a
/// person — which is the actual point of a shared board.
const List<_BoardFrame> _script = [
  _BoardFrame(
    actor: 'Maria Beatrice',
    action: 'moved Design review to Done',
    actorColor: plannerGreen,
    rows: [
      _BoardRow('Design review', _DemoStatus.done, 1.0, justChanged: true),
      _BoardRow('API integration', _DemoStatus.working, 0.55),
      _BoardRow('User testing', _DemoStatus.notStarted, 0.0),
    ],
  ),
  _BoardFrame(
    actor: 'Mohammad Aldrin',
    action: 'pushed API integration to 80%',
    actorColor: plannerYellow,
    rows: [
      _BoardRow('Design review', _DemoStatus.done, 1.0),
      _BoardRow('API integration', _DemoStatus.working, 0.8, justChanged: true),
      _BoardRow('User testing', _DemoStatus.notStarted, 0.0),
    ],
  ),
  _BoardFrame(
    actor: 'John Kent',
    action: 'started User testing',
    actorColor: plannerCyan,
    rows: [
      _BoardRow('Design review', _DemoStatus.done, 1.0),
      _BoardRow('API integration', _DemoStatus.working, 0.8),
      _BoardRow('User testing', _DemoStatus.working, 0.2, justChanged: true),
    ],
  ),
  _BoardFrame(
    actor: 'AL-Khasmir',
    action: 'closed out API integration',
    actorColor: plannerGreen,
    rows: [
      _BoardRow('Design review', _DemoStatus.done, 1.0),
      _BoardRow('API integration', _DemoStatus.done, 1.0, justChanged: true),
      _BoardRow('User testing', _DemoStatus.working, 0.45),
    ],
  ),
];

/// The checklist, written straight onto the ruled sheet.
///
/// No card, no border: a floating white panel would look pasted onto the paper.
/// Items sit on the rules the way handwriting does, in a pen-like face, with
/// hand-drawn checkboxes.
class _LiveBoard extends StatelessWidget {
  const _LiveBoard({required this.frame});

  final _BoardFrame frame;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 390,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A written heading, underlined by hand.
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'This week',
              style: GoogleFonts.caveat(
                color: _paperPen,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(96, 6),
            painter: const _UnderlinePainter(),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < frame.rows.length; i++)
            _LiveRow(row: frame.rows[i]),
        ],
      ),
    );
  }
}

/// A single handwritten line item.
class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.row});

  final _BoardRow row;

  @override
  Widget build(BuildContext context) {
    final done = row.status == _DemoStatus.done;
    final color = row.status.color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        // A soft highlighter swipe over the line that just changed.
        color: row.justChanged ? const Color(0x33FFE082) : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          // Hand-drawn box; the tick strokes itself on when the task completes.
          SizedBox(
            width: 20,
            height: 20,
            child: CustomPaint(painter: _CheckboxPainter(checked: done)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Text(
                  row.title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.caveat(
                    color: done ? _paperInkFaint : _paperPen,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Struck through with a pen line rather than a text decoration,
                // which renders too mechanically against a written face.
                if (done)
                  Positioned.fill(
                    child: CustomPaint(painter: const _StrikePainter()),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Status noted in the margin, small, like an annotation.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 260),
            opacity: done ? 0.55 : 1,
            child: Text(
              done ? 'done' : row.status.label,
              style: GoogleFonts.caveat(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A wobbly hand-drawn underline. The slight overshoot at each end is what
/// separates a pen stroke from a rectangle.
class _UnderlinePainter extends CustomPainter {
  const _UnderlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _paperMargin.withValues(alpha: 0.5)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(1, size.height * 0.6)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.15,
        size.width * 0.7,
        size.height * 0.5,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.72,
        size.width - 1,
        size.height * 0.35,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _UnderlinePainter oldDelegate) => false;
}

/// A pen checkbox: a square with imperfect corners, plus a tick when checked.
class _CheckboxPainter extends CustomPainter {
  const _CheckboxPainter({required this.checked});

  final bool checked;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = _paperInkFaint
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Corners deliberately do not meet exactly — a closed, perfect square reads
    // as printed, and this should read as drawn.
    final box = Path()
      ..moveTo(3.5, 2.5)
      ..lineTo(size.width - 2.5, 3.2)
      ..lineTo(size.width - 3.2, size.height - 2.8)
      ..lineTo(2.8, size.height - 3.5)
      ..close();
    canvas.drawPath(box, pen);

    if (!checked) {
      return;
    }

    // The tick overshoots the box, the way a real one does.
    final tick = Paint()
      ..color = plannerGreen
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.76)
      ..lineTo(size.width * 0.86, size.height * 0.16);

    canvas.drawPath(path, tick);
  }

  @override
  bool shouldRepaint(covariant _CheckboxPainter oldDelegate) =>
      oldDelegate.checked != checked;
}

/// A struck-through line with a slight rise, as drawn by hand.
class _StrikePainter extends CustomPainter {
  const _StrikePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _paperInkFaint.withValues(alpha: 0.75)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final y = size.height * 0.52;
    final path = Path()
      ..moveTo(0, y + 1.5)
      ..quadraticBezierTo(size.width * 0.5, y - 2, size.width, y - 0.5);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrikePainter oldDelegate) => false;
}

/// A curved arrow scribbled in from the left, the way you would point at
/// something you just added to a page.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final shaft = Path()
      ..moveTo(1, size.height * 0.25)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.1,
        size.width - 3,
        size.height * 0.62,
      );
    canvas.drawPath(shaft, pen);

    // Head, drawn as two short strokes rather than a filled triangle.
    final head = Path()
      ..moveTo(size.width - 9, size.height * 0.42)
      ..lineTo(size.width - 3, size.height * 0.62)
      ..lineTo(size.width - 10, size.height * 0.8);
    canvas.drawPath(head, pen);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({required this.frame});

  final _BoardFrame frame;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 390,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        // Stack the outgoing and incoming lines on top of each other rather
        // than side by side. The default layout builder lays them out in a
        // Row-like flow mid-transition, which makes two different notes appear
        // to collide.
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            for (final child in previousChildren) Positioned.fill(child: child),
            ?currentChild,
          ],
        ),
        child: Row(
          key: ValueKey(frame.action),
          children: [
            // An arrow scribbled in from the margin, pointing at the note.
            CustomPaint(
              size: const Size(22, 14),
              painter: _ArrowPainter(color: frame.actorColor),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${frame.actor} ${frame.action}',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.caveat(
                  color: frame.actorColor.withValues(alpha: 0.95),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'just now',
              style: GoogleFonts.caveat(color: _paperInkFaint, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// The panel backdrop: drafting paper.
///
/// A fine grid with heavier every-fifth rules, a horizontal time axis, and a
/// few plotted bars — the visual language of a plan being laid out, drawn at
/// low contrast so it never competes with the login form beside it.
///
/// Deliberately not a soft radial gradient. Structure carries more meaning than
/// atmosphere here, and reads as drawn rather than generated.
// --- Paper palette ---------------------------------------------------------
// Kept local to the login screen. These are a distinct surface from the app's
// design tokens: warm, printed, and used nowhere else.
const Color _paper = Color(0xFFF4F1EA);
const Color _paperRule = Color(0xFFE3DCCC);
const Color _paperInk = Color(0xFF22211E);

/// Ballpoint blue-black, for anything meant to read as handwritten.
const Color _paperPen = Color(0xFF2A3358);
const Color _paperInkSoft = Color(0xFF54504A);
const Color _paperInkFaint = Color(0xFF8F887A);
const Color _paperMargin = Color(0xFFD4674F);

/// The panel backdrop: a sheet of ruled paper.
///
/// Horizontal rules with a red margin line down the left, exactly as on a pad.
/// The content column starts to the right of the margin, so the headline and
/// demo sit in the writing area the way handwriting would.
///
/// Rules fade toward the bottom of the sheet rather than running edge to edge —
/// a uniform grid to the frame edge is what makes generated backgrounds look
/// applied rather than drawn.
class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  static const _lineSpacing = 30.0;
  static const _marginX = 34.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()..strokeWidth = 1;

    for (var y = _lineSpacing * 2; y < size.height; y += _lineSpacing) {
      // Fade the rules out over the last third of the sheet.
      final depth = (y / size.height).clamp(0.0, 1.0);
      final fade = depth < 0.62 ? 1.0 : (1.0 - (depth - 0.62) / 0.38);
      rule.color = _paperRule.withValues(alpha: 0.85 * fade);
      canvas.drawLine(Offset(_marginX, y), Offset(size.width, y), rule);
    }

    // Margin rule: two hairlines, the way a printed pad has a double rule.
    final margin = Paint()
      ..color = _paperMargin.withValues(alpha: 0.55)
      ..strokeWidth = 1.1;
    canvas.drawLine(
      const Offset(_marginX, 0),
      Offset(_marginX, size.height),
      margin,
    );
    canvas.drawLine(
      const Offset(_marginX + 3, 0),
      Offset(_marginX + 3, size.height),
      Paint()
        ..color = _paperMargin.withValues(alpha: 0.22)
        ..strokeWidth = 1,
    );

    _paintPunchHoles(canvas, size);
  }

  /// Three punch holes in the margin — the detail that makes the surface read
  /// as a real sheet rather than a striped rectangle.
  void _paintPunchHoles(Canvas canvas, Size size) {
    final hole = Paint()..color = const Color(0xFFE7E2D6);
    final holeEdge = Paint()
      ..color = const Color(0xFFD8D1C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final fraction in const [0.22, 0.5, 0.78]) {
      final center = Offset(_marginX / 2 - 1, size.height * fraction);
      canvas.drawCircle(center, 6, hole);
      canvas.drawCircle(center, 6, holeEdge);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) => false;
}

/// Three segments that fill as the password improves, with a word for what the
/// bar means — a bar alone leaves people guessing what "enough" looks like.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.check});

  final _PasswordCheck check;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 3; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 3,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: check.score >= i ? check.color : plannerBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        SizedBox(
          width: 62,
          child: Text(
            check.label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: check.color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Stay signed in" — on by default, since this is a desktop app people keep
/// open. Turning it off is the meaningful choice, on a shared machine.
class _StaySignedIn extends StatelessWidget {
  const _StaySignedIn({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (next) => onChanged(next ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Stay signed in on this device',
              style: TextStyle(color: plannerText, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: plannerInk,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text(
            label,
            style: const TextStyle(
              color: plannerBlue,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchPrompt extends StatelessWidget {
  const _SwitchPrompt({
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          question,
          style: const TextStyle(color: plannerMuted, fontSize: 13),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Text(
              action,
              style: const TextStyle(
                color: plannerBlue,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
