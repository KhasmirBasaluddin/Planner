import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants.dart';
import 'core/notifications/desktop_toast.dart';
import 'core/supabase/auth_service.dart';
import 'core/supabase/planner_repository.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme.dart';
import 'features/auth/login_page.dart';
import 'features/planner/planner_page.dart';
import 'shared/utils/planner_colors.dart';
import 'shared/widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Makes confirmation links work for both installed and portable ZIP builds.
  await ensureWindowsProtocolRegistration();

  // Native toasts for urgent notifications; a no-op wherever unsupported.
  await DesktopToast.init();

  // Credentials come from the gitignored .env file (or --dart-define in CI).
  await SupabaseConfig.load();

  // Without credentials the app still starts, but shows setup instructions
  // rather than failing with an opaque network error.
  var initialized = false;
  String? initError;
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
        // Planner owns Windows deep-link handling below. Leaving Supabase
        // Flutter's observer enabled would exchange the same one-time PKCE
        // code twice when app_links delivers the callback.
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );
      initialized = true;
    } catch (error) {
      initError = error.toString();
    }
  }

  runApp(PlannerApp(initialized: initialized, initError: initError));
}

class PlannerApp extends StatelessWidget {
  const PlannerApp({super.key, this.initialized = false, this.initError});

  final bool initialized;
  final String? initError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appName,
      theme: buildAppTheme(),
      home: initialized
          ? const _AuthGate()
          : _SetupRequiredPage(error: initError),
    );
  }
}

/// Shows the login screen or the app depending on the current session, and
/// switches automatically when the user signs in or out.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  late final AuthService _auth;
  late final PlannerRepository _repository;
  late final DeepLinkHandler _deepLinks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final client = Supabase.instance.client;
    _auth = AuthService(client);
    _repository = PlannerRepository(client);

    // Catches `planner://auth-callback` from a confirmation or password-reset
    // email and turns it into a session. The auth stream below then swaps the
    // login screen for the app — so clicking the link in an email signs you
    // straight in rather than returning you to a password prompt.
    _deepLinks = DeepLinkHandler(_auth)
      ..onSuccess = () {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                backgroundColor: plannerGreen,
                content: Text('Email confirmed. You are now signed in.'),
              ),
            );
        }
      }
      ..onError = (message) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(backgroundColor: plannerRed, content: Text(message)),
            );
        }
      };
    _deepLinks.start();

    // Offer any newer GitHub release once the first frame is up, so the
    // dialog has a navigator to attach to. Debug builds skip it: the check
    // would nag developers whose local version trails the published one.
    if (!kDebugMode && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          promptForUpdateIfAvailable(context);
        }
      });
    }
  }

  /// Honours "stay signed in": when it was unchecked, the session is dropped as
  /// the app is detached. `dispose` is not reliable for this on desktop, since
  /// closing the window does not always unwind the widget tree.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _auth.endEphemeralSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _auth.onAuthStateChange,
      builder: (context, snapshot) {
        // currentSession is already populated for a restored session, so there
        // is no flash of the login screen on launch.
        final session = snapshot.data?.session ?? _auth.currentSession;
        if (session == null) {
          return LoginPage(auth: _auth);
        }
        return PlannerPage(
          key: ValueKey(session.user.id),
          auth: _auth,
          repository: _repository,
        );
      },
    );
  }
}

/// Shown when the app was built without Supabase credentials.
class _SetupRequiredPage extends StatelessWidget {
  const _SetupRequiredPage({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: plannerSurface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: plannerBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: plannerYellow,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      error == null
                          ? 'Supabase setup required'
                          : 'Could not connect to Supabase',
                      style: const TextStyle(
                        color: plannerInk,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  error ?? SupabaseConfig.setupInstructions,
                  style: const TextStyle(
                    color: plannerText,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: plannerSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: plannerBorder),
                  ),
                  child: const SelectableText(
                    'flutter run -d windows \\\n'
                    '  --dart-define=SUPABASE_URL=https://xxx.supabase.co \\\n'
                    '  --dart-define=SUPABASE_ANON_KEY=eyJhbGci...',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      height: 1.6,
                      color: plannerInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
