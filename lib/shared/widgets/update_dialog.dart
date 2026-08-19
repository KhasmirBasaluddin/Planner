import 'package:flutter/material.dart';

import '../../core/updates/update_service.dart';
import '../utils/planner_colors.dart';
import 'app_dialog.dart';

/// Checks for a newer release and, when one exists, offers to install it.
/// Silent when up to date or offline — startup must not hinge on GitHub.
Future<void> promptForUpdateIfAvailable(BuildContext context) async {
  final service = UpdateService();
  final update = await service.checkForUpdate();
  if (update == null || !context.mounted) {
    service.dispose();
    return;
  }

  final install = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      icon: Icons.system_update_alt_rounded,
      title: 'Update available',
      message:
          'Planner ${update.version} is ready to install — you have '
          '${update.currentVersion}. The app restarts once the update '
          'finishes.',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Update now'),
        ),
      ],
    ),
  );

  if (install != true || !context.mounted) {
    service.dispose();
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _UpdateProgressDialog(service: service, update: update),
  );
  service.dispose();
}

/// Downloads the installer with a progress bar, then hands off to it. On
/// success this dialog never closes — the installer shuts the app down.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({required this.service, required this.update});

  final UpdateService service;
  final UpdateInfo update;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final installer = await widget.service.downloadInstaller(
        widget.update,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      await widget.service.installAndExit(installer);
    } catch (error) {
      // Cancelling closes the client, which surfaces here as an error after
      // the dialog is gone — only a failure the user can still see matters.
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AppDialog(
        icon: Icons.error_outline_rounded,
        tone: plannerRed,
        title: 'Update failed',
        message:
            'The update could not be downloaded. You can keep using this '
            'version and try again the next time the app starts.\n\n$_error',
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AppDialog(
      icon: Icons.download_rounded,
      title: 'Downloading update',
      message:
          'Planner ${widget.update.version} is downloading. The installer '
          'starts on its own when the download completes.',
      content: ClipRRect(
        borderRadius: BorderRadius.circular(radiusXs),
        child: LinearProgressIndicator(value: _progress, minHeight: 6),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Closing the client aborts the in-flight download.
            widget.service.dispose();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
