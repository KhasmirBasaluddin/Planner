import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase connection settings.
///
/// Values are read from a gitignored `.env` file at the project root, so
/// credentials never enter version control:
///
/// ```
/// SUPABASE_URL=https://your-project-ref.supabase.co
/// SUPABASE_ANON_KEY=eyJhbGci...
/// ```
///
/// Copy `.env.example` to `.env` and fill in your own values, both from the
/// Supabase dashboard under Project Settings → API.
///
/// A `--dart-define` of the same name takes precedence, which is how CI and
/// release builds supply values without shipping a file.
///
/// ## On what is actually secret
///
/// The **anon / publishable** key belongs here. It is designed to be shipped in
/// a client: it identifies the project, and row level security decides what any
/// given signed-in user may read or write. Keeping it out of git is good
/// hygiene, but it is still embedded in the built binary and recoverable by
/// anyone who has the app — that is expected and safe.
///
/// The **`service_role`** key is the real secret. It bypasses RLS completely.
/// It must never appear in this project, in `.env`, or in any client code. It
/// belongs only on a server or in Supabase Edge Function secrets.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String _urlFromDefine = String.fromEnvironment('SUPABASE_URL');
  static const String _keyFromDefine = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static bool _envLoaded = false;

  /// Reads `.env` if present. Missing file is not an error — the app falls back
  /// to --dart-define values and, failing that, shows setup instructions.
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
      _envLoaded = true;
    } catch (_) {
      _envLoaded = false;
    }
  }

  static String _read(String key, String fromDefine) {
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }
    if (_envLoaded) {
      return dotenv.env[key] ?? '';
    }
    return '';
  }

  static String get url => _read('SUPABASE_URL', _urlFromDefine);

  static String get anonKey => _read('SUPABASE_ANON_KEY', _keyFromDefine);

  static bool get isConfigured {
    final currentUrl = url;
    final currentKey = anonKey;
    // Guard against the placeholder values in .env.example being used as-is.
    return currentUrl.isNotEmpty &&
        currentKey.isNotEmpty &&
        !currentUrl.contains('your-project-ref') &&
        !currentKey.contains('your-anon-key');
  }

  static const String setupInstructions =
      'Supabase is not configured yet.\n\n'
      '1. Create a free project at supabase.com\n'
      '2. Open the SQL Editor and run the contents of supabase/schema.sql\n'
      '3. Copy .env.example to .env and paste in your Project URL and anon key '
      '(Project Settings → API)\n'
      '4. Restart the app';
}
