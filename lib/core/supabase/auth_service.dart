import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The custom URL scheme Windows hands back to the app after a browser
/// redirect. The installer registers it for the current Windows user.
const String kAppScheme = 'planner';
const String kAuthCallbackUrl = '$kAppScheme://auth-callback';
const String kAllowedEmailDomain = 'vintazk.com';
const int kMaxFullNameLength = 60;
const int kMaxPasswordLength = 72;

/// Points the `planner://` scheme at the currently running executable.
///
/// The portable ZIP can be extracted anywhere, so an installer cannot know its
/// final path. Refreshing this per-user registration on launch also keeps links
/// working after the extracted folder is moved.
Future<void> ensureWindowsProtocolRegistration() async {
  if (!Platform.isWindows) {
    return;
  }

  final executable = Platform.resolvedExecutable;
  const root = r'HKCU\Software\Classes\planner';
  final values = <List<String>>[
    ['add', root, '/ve', '/d', 'URL:Planner Protocol', '/f'],
    ['add', root, '/v', 'URL Protocol', '/d', '', '/f'],
    ['add', '$root\\DefaultIcon', '/ve', '/d', '"$executable",0', '/f'],
    [
      'add',
      '$root\\shell\\open\\command',
      '/ve',
      '/d',
      '"$executable" "%1"',
      '/f',
    ],
  ];

  try {
    for (final arguments in values) {
      final result = await Process.run('reg.exe', arguments, runInShell: false);
      if (result.exitCode != 0) {
        return;
      }
    }
  } catch (_) {
    // A locked-down Windows policy may reject registry writes. The app still
    // works normally; only opening confirmation links from email is affected.
  }
}

bool isPlannerAuthCallback(Uri uri) {
  if (uri.scheme.toLowerCase() != kAppScheme ||
      uri.host.toLowerCase() != 'auth-callback') {
    return false;
  }
  final fragment = Uri.splitQueryString(uri.fragment);
  return uri.queryParameters.containsKey('code') ||
      uri.queryParameters.containsKey('error') ||
      uri.queryParameters.containsKey('error_code') ||
      uri.queryParameters.containsKey('error_description') ||
      fragment.containsKey('access_token') ||
      fragment.containsKey('error') ||
      fragment.containsKey('error_code') ||
      fragment.containsKey('error_description');
}

bool isAllowedCompanyEmail(String email) {
  final normalized = email.trim().toLowerCase();
  final parts = normalized.split('@');
  return parts.length == 2 &&
      parts.first.isNotEmpty &&
      parts.last == kAllowedEmailDomain;
}

void requireAllowedCompanyEmail(String email) {
  if (!isAllowedCompanyEmail(email)) {
    throw const AuthException(
      'Only @vintazk.com email addresses are allowed.',
      statusCode: '403',
    );
  }
}

bool isValidFullName(String fullName) {
  final normalized = fullName.trim();
  return normalized.isNotEmpty && normalized.length <= kMaxFullNameLength;
}

void requireValidFullName(String fullName) {
  if (!isValidFullName(fullName)) {
    throw const AuthException(
      'Full name must be between 1 and 60 characters.',
      statusCode: '400',
    );
  }
}

void requireValidPasswordLength(String password) {
  if (password.length > kMaxPasswordLength) {
    throw const AuthException(
      'Password must be 72 characters or fewer.',
      statusCode: '400',
    );
  }
}

/// Sign-in, sign-up, and the session stream the route guard listens to.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => currentSession != null;

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  /// Signs in.
  ///
  /// [staySignedIn] controls whether the session survives closing the app.
  /// Supabase persists and silently refreshes sessions by default, so the
  /// meaningful case is the opposite: when it is false we drop the stored
  /// session on exit, which is what someone on a shared machine expects.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
    bool staySignedIn = true,
  }) async {
    requireAllowedCompanyEmail(email);
    final response = await _auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    _persistSession = staySignedIn;
    return response;
  }

  /// When false, [endEphemeralSession] clears the session as the app closes.
  bool _persistSession = true;

  bool get persistSession => _persistSession;

  /// Called on app shutdown. A no-op when the user asked to stay signed in.
  Future<void> endEphemeralSession() async {
    if (!_persistSession) {
      await signOut();
    }
  }

  /// Creates an account. The confirmation email links back to the app via the
  /// custom scheme, so clicking it signs the user straight in rather than
  /// dropping them on a web page.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) {
    requireAllowedCompanyEmail(email);
    requireValidFullName(fullName);
    requireValidPasswordLength(password);
    return _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
      emailRedirectTo: kAuthCallbackUrl,
    );
  }

  Future<void> sendPasswordReset(String email) {
    requireAllowedCompanyEmail(email);
    return _auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: kAuthCallbackUrl,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Exchanges a callback URL for a session. Supabase handles both PKCE
  /// (`?code=`) and implicit (`#access_token=`) callbacks here, including
  /// propagating errors returned in the callback.
  Future<void> completeSessionFromUrl(Uri uri) async {
    await _auth.getSessionFromUrl(uri);
  }

  // Invitations are deliberately NOT claimed here.
  //
  // Signing in used to call accept_pending_invites(), which turned every
  // pending invitation into a membership before the person saw it: no
  // notification, no choice, and declining was impossible because the row was
  // already accepted by the time the bell rendered. They now wait in the
  // notification centre until accepted or declined.
}

/// Listens for `planner://` callbacks and completes the sign-in they carry.
///
/// This is what makes "click the link in your email and you are simply signed
/// in" work for confirmation and password-reset links, instead of returning
/// the user to a password prompt.
class DeepLinkHandler {
  DeepLinkHandler(this._auth);

  final AuthService _auth;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  String? _handledCallback;

  /// Called with a human-readable message when a callback fails, so the UI can
  /// surface it instead of appearing to hang.
  void Function(String message)? onError;

  /// Called after the callback creates a session.
  void Function()? onSuccess;

  void start() {
    // app_links includes the cold-start link in this stream on Windows. Using
    // getInitialLink as well can deliver and exchange the same PKCE code twice.
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handle(uri)),
      onError: (Object error) => onError?.call(error.toString()),
    );
  }

  Future<void> _handle(Uri uri) async {
    if (!isPlannerAuthCallback(uri)) {
      return;
    }

    // A one-time auth code must never be exchanged twice. Windows or an email
    // client can occasionally deliver the same activation more than once.
    final callback = uri.toString();
    if (_handledCallback == callback) {
      return;
    }
    _handledCallback = callback;

    try {
      await _auth.completeSessionFromUrl(uri);
      onSuccess?.call();
    } catch (error) {
      onError?.call(describeAuthError(error));
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// Maps Supabase's auth errors onto messages worth showing a user.
String describeAuthError(Object error) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'That email and password combination does not match an account.';
    }
    if (message.contains('email not confirmed')) {
      return 'Check your inbox and confirm your email before signing in.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with that email already exists. Try signing in.';
    }
    if (message.contains('password should be at least')) {
      return 'Password is too short — use at least 6 characters.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    if (message.contains('provider is not enabled')) {
      return 'That sign-in method is not enabled for this project yet.';
    }
    if (message.contains('code verifier') ||
        message.contains('pkce') ||
        message.contains('flow state')) {
      return 'That confirmation link has expired or was already used. '
          'Try signing in, or request a new link.';
    }
    return error.message;
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'Cannot reach Supabase. Check your internet connection.';
  }
  return text;
}
