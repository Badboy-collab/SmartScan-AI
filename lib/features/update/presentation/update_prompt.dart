import 'package:flutter/material.dart';

import '../../../core/utils/app_info.dart';
import '../../../core/utils/app_launcher.dart';
import '../../../core/utils/app_settings.dart';
import '../../../core/utils/update_checker.dart';

/// User-facing side of the update check.
///
/// [autoCheck] runs once when the main shell appears and only speaks up when a
/// newer release actually exists (and the user has not already dismissed it).
/// [manualCheck] is the Settings entry point and always reports a result.
class UpdatePrompt {
  UpdatePrompt._();

  static Future<void> autoCheck(BuildContext context) async {
    final info = (await UpdateChecker.check()).info;
    if (info == null || !context.mounted) return;

    final current = (await AppInfo.load()).versionName;
    if (UpdateChecker.compareVersions(info.version, current) <= 0) return;

    final dismissed = await AppSettings.dismissedUpdateVersion();
    if (dismissed == info.version || !context.mounted) return;

    await _showAvailable(context, current, info);
  }

  static Future<void> manualCheck(BuildContext context) async {
    final current = (await AppInfo.load()).versionName;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(),
    );

    final result = await UpdateChecker.check();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!result.reachedServer) {
      await _showMessage(
        context,
        'Could not check for updates',
        'Installed version: $current\nPlease check your internet connection and try again.',
      );
      return;
    }

    final info = result.info;
    if (info == null || UpdateChecker.compareVersions(info.version, current) <= 0) {
      await _showMessage(
        context,
        "You're up to date",
        'AH Scanner $current is the latest version.',
      );
      return;
    }

    await _showAvailable(context, current, info);
  }

  static Future<void> _showMessage(
    BuildContext context,
    String title,
    String message,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showAvailable(
    BuildContext context,
    String current,
    UpdateInfo info,
  ) async {
    final rawNotes = info.notes;
    final notes = rawNotes.isEmpty
        ? null
        : (rawNotes.length > 500 ? '${rawNotes.substring(0, 500)}…' : rawNotes);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AH Scanner ${info.version}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Installed: $current',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (notes != null) ...[
                const SizedBox(height: 12),
                Text(notes, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await AppSettings.setDismissedUpdateVersion(info.version);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final url =
                  info.downloadUrl.isNotEmpty ? info.downloadUrl : info.releaseUrl;
              final opened = await openExternalUrl(url);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!opened) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open the download page'),
                  ),
                );
              }
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
          ),
          SizedBox(width: 16),
          Text('Checking for updates…'),
        ],
      ),
    );
  }
}
