import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The custom URL scheme Windows hands back to the app after a browser
/// redirect. Registered by [DeepLinkHandler.registerWindowsScheme].
const String kAppScheme = 'planner';
const String kAuthCallbackUrl = '$kAppScheme://auth-callback';

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
    return _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
      emailRedirectTo: kAuthCallbackUrl,
    );
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: kAuthCallbackUrl,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Exchanges a callback URL for a session. Handles both shapes Supabase uses:
  /// PKCE (`?code=`) and the implicit flow (`#access_token=`).
  Future<void> completeSessionFromUrl(Uri uri) async {
    final code = uri.queryParameters['code'];
    if (code != null) {
      await _auth.exchangeCodeForSession(code);
      return;
    }

    // Implicit flow puts the tokens in the fragment, which
    // getSessionFromUrl parses for us.
    if (uri.fragment.contains('access_token')) {
      await _auth.getSessionFromUrl(uri);
    }
  }

  /// Turns invitations addressed to this user's email into memberships. Safe to
  /// call on every sign-in; a no-op when nothing is pending.
  Future<int> acceptPendingInvites() async {
    try {
      final result = await _client.rpc<dynamic>('accept_pending_invites');
      if (result is int) {
        return result;
      }
      return int.tryParse('$result') ?? 0;
    } catch (_) {
      // Never block sign-in on invite claiming.
      return 0;
    }
  }
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

  /// Called with a human-readable message when a callback fails, so the UI can
  /// surface it instead of appearing to hang.
  void Function(String message)? onError;

  Future<void> start() async {
    // A link that launched the app arrives here rather than on the stream.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handle(initial);
      }
    } catch (_) {
      // No initial link is the normal case.
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object error) => onError?.call(error.toString()),
    );
  }

  Future<void> _handle(Uri uri) async {
    if (uri.scheme != kAppScheme) {
      return;
    }
    try {
      await _auth.completeSessionFromUrl(uri);
      await _auth.acceptPendingInvites();
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
    if (message.contains('code verifier') || message.contains('pkce')) {
      return 'That sign-in link has expired. Try signing in again.';
    }
    return error.message;
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'Cannot reach Supabase. Check your internet connection.';
  }
  return text;
}
