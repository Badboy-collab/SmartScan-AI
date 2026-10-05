import 'dart:io' as dart_io;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/app_info.dart';
import '../../../../core/utils/app_launcher.dart';
import '../../../../core/utils/update_checker.dart';
import '../../../update/presentation/update_prompt.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../../../../main.dart';
import '../../../documents/presentation/providers/document_provider.dart';
import '../../../ocr/presentation/widgets/vision_key_dialog.dart';

/// The "Me" tab.
///
/// Every row here leads somewhere real. An earlier version advertised a bound
/// AH Scanner account with 10 GB of cloud storage, "Pro privileges", points,
/// sync and business features - none of which exist in this app - and half of
/// the rows did nothing when tapped.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// Where this app actually lives. Used for "recommend" and "feedback",
  /// neither of which needs an account or a backend.
  static const String _repoUrl =
      'https://github.com/${UpdateChecker.owner}/${UpdateChecker.repo}';
  static const String _issuesUrl = '$_repoUrl/issues';
  static const String _latestReleaseUrl = '$_repoUrl/releases/latest';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context),
            const SizedBox(height: 8),
            _buildSettingsList(context, dividerColor),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6);

    return Container(
      color: theme.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AH Scanner',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Scan • Enhance • OCR',
                  style: TextStyle(fontSize: 12, color: Colors.teal, letterSpacing: 0.3),
                ),
                const SizedBox(height: 4),
                FutureBuilder<AppInfo>(
                  future: AppInfo.load(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return Text(
                      info == null
                          ? 'Version …'
                          : 'Version ${info.versionName} (${info.versionCode})',
                      style: TextStyle(fontSize: 12, color: muted),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context, Color dividerColor) {
    final theme = Theme.of(context);

    return Container(
      color: theme.cardColor,
      child: Column(
        children: [
          _buildListTile(context, Icons.palette_outlined, 'App Theme', trailingText: _getThemeName(themeNotifier.mode), onTap: () {
            _showThemeSelectorDialog(context);
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.folder_open_outlined, 'Manage Documents', onTap: () {
            context.go('/documents');
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.document_scanner_outlined, 'Camera & Save Settings', onTap: () {
            context.push('/more_settings');
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.key_outlined, 'OCR — Vision API Key', onTap: () {
            _showVisionApiKeyDialog(context);
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.system_update_alt, 'Check for Updates', onTap: () {
            UpdatePrompt.manualCheck(context);
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.info_outline, 'About AH Scanner', onTap: () {
            _showAboutDialog(context);
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.thumb_up_outlined, 'Recommend AH Scanner', onTap: () {
            _recommend();
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.help_outline, 'Help & Feedback', onTap: () {
            _open(context, _issuesUrl);
          }),
          Divider(color: dividerColor, height: 1),
          const _StorageStatWidget(),
        ],
      ),
    );
  }

  /// Shares the download link through whatever the user uses to chat - the
  /// whole "tell a friend" flow needs no account on our side.
  Future<void> _recommend() async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: 'AH Scanner — scan, enhance, OCR and convert documents.\n'
            'Download: $_latestReleaseUrl',
      ));
    } catch (_) {
      // A cancelled or unsupported share sheet is not worth an error dialog.
    }
  }

  Future<void> _open(BuildContext context, String url) async {
    final opened = await openExternalUrl(url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link')),
      );
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset('assets/images/app_logo.png', width: 84, height: 84, fit: BoxFit.cover),
            ),
            const SizedBox(height: 14),
            Text(
              'AH Scanner',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color),
            ),
            const SizedBox(height: 4),
            const Text('Scan • Enhance • OCR', style: TextStyle(fontSize: 13, color: Colors.teal, letterSpacing: 0.3)),
            const SizedBox(height: 10),
            const Text('Developed by AH Creations', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            FutureBuilder<AppInfo>(
              future: AppInfo.load(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                return Text(
                  info == null ? 'Version …' : 'Version ${info.versionName} (${info.versionCode})',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _getThemeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.navyBlue:
        return 'Navy Blue';
      case AppThemeMode.system:
        return 'System';
    }
  }

  void _showThemeSelectorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Select App Theme',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption(ctx, '☀️ Light Theme (Default)', AppThemeMode.light),
            _buildThemeOption(ctx, '🌙 Dark Theme', AppThemeMode.dark),
            _buildThemeOption(ctx, '🌊 Navy Blue Theme', AppThemeMode.navyBlue),
            _buildThemeOption(ctx, '⚙️ System Theme', AppThemeMode.system),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(BuildContext context, String label, AppThemeMode mode) {
    final isSelected = themeNotifier.mode == mode;
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? Colors.teal : Colors.grey,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.teal : theme.textTheme.bodyLarge?.color,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () {
        themeNotifier.setAppTheme(mode);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _showVisionApiKeyDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;

    // Same dialog the OCR page uses, so the key can be tested before saving.
    await showVisionKeyDialog(
      context,
      currentKey: prefs.getString('google_vision_api_key') ?? '',
    );
  }

  Widget _buildListTile(BuildContext context, IconData icon, String title, {String? trailingText, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.iconTheme.color?.withValues(alpha: 0.7) ?? Colors.grey),
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(trailingText, style: const TextStyle(color: Colors.teal, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: theme.iconTheme.color?.withValues(alpha: 0.4) ?? Colors.grey, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _StorageStatWidget extends StatefulWidget {
  const _StorageStatWidget();
  @override
  State<_StorageStatWidget> createState() => _StorageStatWidgetState();
}

class _StorageStatWidgetState extends State<_StorageStatWidget> {
  String _usedSpace = "Calculating...";

  @override
  void initState() {
    super.initState();
    _calcSize();
  }

  Future<void> _calcSize() async {
    try {
      final docs = getIt<DocumentProvider>().documents;
      int bytes = 0;
      for (var d in docs) {
        final dir = dart_io.Directory(d.dirPath);
        if (await dir.exists()) {
          await for (var entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is dart_io.File) bytes += await entity.length();
          }
        }
      }
      if (mounted) setState(() => _usedSpace = "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB");
    } catch (e) {
      if (mounted) setState(() => _usedSpace = "0.00 MB");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.storage, color: theme.iconTheme.color?.withValues(alpha: 0.7) ?? Colors.grey),
      title: Text('Local Storage Used', style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: Text(_usedSpace, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6), fontSize: 13)),
    );
  }
}
