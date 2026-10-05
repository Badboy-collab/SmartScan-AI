import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/utils/app_info.dart';
import '../../../core/utils/app_launcher.dart';
import '../../../core/utils/app_settings.dart';
import '../../../core/utils/update_checker.dart';
import '../data/services/apk_downloader.dart';
import '../data/services/update_installer.dart';

/// User-facing side of the update check.
///
/// [autoCheck] runs once when the main shell appears and only speaks up when a
/// newer release actually exists (and the user has not already dismissed it).
/// [manualCheck] is the Settings entry point and always reports a result.
///
/// When the release ships an APK asset the update is fully in-app: the file is
/// downloaded with a progress bar and handed to the system installer. Releases
/// without an asset still fall back to the release page in the browser.
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
    if (!context.mounted) return;

    // showDialog() completes only when its route is popped, so it must NOT be
    // awaited here - awaiting it left "Checking for updates..." on screen
    // forever. It is dismissed explicitly below once the check returns.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(),
    ));

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
              Navigator.pop(ctx);

              if (info.hasApkAsset) {
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _UpdateDownloadDialog(info: info),
                );
                return;
              }

              // No APK asset published: the browser is the only way to get it.
              final url = info.downloadUrl.isNotEmpty
                  ? info.downloadUrl
                  : info.releaseUrl;
              final opened = await openExternalUrl(url);
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open the download page'),
                  ),
                );
              }
            },
            child: Text(info.hasApkAsset ? 'Update now' : 'Download'),
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

enum _Phase { downloading, ready, needsPermission, failed }

/// Downloads the release APK inside the app and installs it, so updating never
/// sends the user to a browser or a file manager.
class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  _Phase _phase = _Phase.downloading;
  File? _file;
  int _received = 0;
  int? _total;
  int _lastPercent = -1;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = null;
      _lastPercent = -1;
      _error = '';
    });

    try {
      final file = await ApkDownloader.download(
        url: widget.info.downloadUrl,
        fileName: 'AH-Scanner-${widget.info.version}.apk',
        onProgress: (received, total) {
          if (!mounted) return;
          // One rebuild per whole percent keeps the dialog (and the download)
          // light; without a Content-Length the size text updates freely.
          final percent =
              (total == null || total <= 0) ? null : received * 100 ~/ total;
          if (percent != null && percent == _lastPercent) return;
          _lastPercent = percent ?? _lastPercent;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e is HttpException ? e.message : '$e';
      });
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null) return;

    if (!await UpdateInstaller.canInstall()) {
      if (!mounted) return;
      setState(() => _phase = _Phase.needsPermission);
      return;
    }

    final failure = await UpdateInstaller.install(file);
    if (failure == null || !mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = failure;
    });
  }

  String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Updating AH Scanner'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _content(context),
        ),
      ),
      actions: _actions(context),
    );
  }

  List<Widget> _content(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Colors.grey.shade600);

    switch (_phase) {
      case _Phase.downloading:
        final percent = (_total == null || _total! <= 0)
            ? null
            : (_received * 100 ~/ _total!).clamp(0, 100);
        return [
          Text('AH Scanner ${widget.info.version}', style: muted),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: percent == null ? null : percent / 100,
            backgroundColor: Colors.teal.withValues(alpha: 0.15),
            color: Colors.teal,
          ),
          const SizedBox(height: 10),
          Text(
            percent == null
                ? 'Downloading… ${_size(_received)}'
                : 'Downloading… $percent%  (${_size(_received)}'
                    '${_total == null ? '' : ' of ${_size(_total!)}'})',
            style: muted,
          ),
        ];

      case _Phase.ready:
        return [
          Text('Downloaded ${_size(_received)}.', style: muted),
          const SizedBox(height: 12),
          const Text(
            'Tap Install and confirm the prompt Android shows. The app closes '
            'by itself while it updates.',
            style: TextStyle(fontSize: 13),
          ),
        ];

      case _Phase.needsPermission:
        return [
          const Text(
            'Android needs your permission once before it can install updates '
            'for this app.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            'Turn on "Allow from this source" for AH Scanner, then come back '
            'and tap Install again.',
            style: muted,
          ),
        ];

      case _Phase.failed:
        return [
          const Text('The update could not be installed', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_error, style: muted),
        ];
    }
  }

  List<Widget> _actions(BuildContext context) {
    switch (_phase) {
      case _Phase.downloading:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hide'),
          ),
        ];

      case _Phase.ready:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: _install,
            child: const Text('Install'),
          ),
        ];

      case _Phase.needsPermission:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await UpdateInstaller.openInstallSettings();
              if (mounted) setState(() => _phase = _Phase.ready);
            },
            child: const Text('Open settings'),
          ),
        ];

      case _Phase.failed:
        return [
          TextButton(
            onPressed: () async {
              await openExternalUrl(widget.info.releaseUrl);
            },
            child: const Text('Open release page'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: _download,
            child: const Text('Try again'),
          ),
        ];
    }
  }
}
