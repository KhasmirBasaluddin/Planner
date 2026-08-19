import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer release found on GitHub, with everything needed to install it.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.installerUrl,
  });

  final String version;
  final String currentVersion;
  final Uri installerUrl;
}

/// Checks GitHub Releases for a newer Windows build and runs its installer.
///
/// Releases are published by `.github/workflows/release.yml`, which stamps
/// both the executable and the installer with the version from the git tag —
/// so comparing the latest tag against the running executable's version is
/// all an update check needs.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const String repo = 'KhasmirBasaluddin/Planner';

  final http.Client _client;

  /// The newer release, or null when already up to date. Also null when the
  /// check fails: an unreachable network must never surface as a startup
  /// error for a feature the user did not ask for.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final response = await _client
          .get(
            Uri.https('api.github.com', '/repos/$repo/releases/latest'),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }

      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (release['tag_name'] as String? ?? '').replaceFirst(
        RegExp('^v'),
        '',
      );
      if (tag.isEmpty || !isNewerVersion(tag, current)) {
        return null;
      }

      // The release also carries a portable ZIP; only the installer asset can
      // replace an existing install.
      final assets = (release['assets'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      String? url;
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.startsWith('plannersetup') && name.endsWith('.exe')) {
          url = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (url == null) {
        return null;
      }

      return UpdateInfo(
        version: tag,
        currentVersion: current,
        installerUrl: Uri.parse(url),
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads the installer into the temp directory, reporting progress as a
  /// 0–1 fraction — or null while the server has not said how big it is.
  Future<File> downloadInstaller(
    UpdateInfo update, {
    void Function(double? progress)? onProgress,
  }) async {
    final response = await _client.send(
      http.Request('GET', update.installerUrl),
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'Download failed (HTTP ${response.statusCode})',
        uri: update.installerUrl,
      );
    }

    final file = File(
      '${Directory.systemTemp.path}'
      '${Platform.pathSeparator}PlannerSetup-${update.version}.exe',
    );
    final sink = file.openWrite();
    final total = response.contentLength;
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null || total == 0 ? null : received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  }

  /// Hands off to the installer and exits. `/SILENT` leaves only a progress
  /// bar on screen; the installer closes this process (CloseApplications=yes
  /// in Planner.iss) and relaunches the app when it finishes.
  Future<void> installAndExit(File installer) async {
    await Process.start(installer.path, const [
      '/SILENT',
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  /// Aborts any in-flight request; safe to call more than once.
  void dispose() => _client.close();

  /// Numeric comparison of dotted versions, ignoring a `+build` suffix — a
  /// string compare would call 1.10.0 older than 1.9.0.
  static bool isNewerVersion(String candidate, String current) {
    List<int> parse(String version) => version
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
    final a = parse(candidate);
    final b = parse(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) {
        return x > y;
      }
    }
    return false;
  }
}
