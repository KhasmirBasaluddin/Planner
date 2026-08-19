import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// Native system toasts, so an alert still lands when the window is buried
/// or minimised — the in-app bell and snackbars only reach someone who is
/// already looking at Planner.
///
/// Everything here degrades to a no-op: toasts are reinforcement, and a
/// machine where they cannot be shown must never lose the app over it.
class DesktopToast {
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isWindows) {
      return;
    }
    try {
      await localNotifier.setup(
        appName: 'Planner',
        // Windows only shows toasts for apps with a Start Menu shortcut
        // carrying an AppUserModelID; this creates one when it is missing.
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _ready = true;
    } catch (_) {
      // Without setup, show() below stays silent.
    }
  }

  static Future<void> show({required String title, String body = ''}) async {
    if (!_ready) {
      return;
    }
    try {
      final notification = LocalNotification(
        title: title,
        body: body.trim().isEmpty ? null : body,
      );
      await notification.show();
    } catch (_) {
      // A toast that fails to render is not worth an error dialog.
    }
  }
}
