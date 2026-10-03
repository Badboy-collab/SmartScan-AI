import 'dart:io' as dart_io;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/app_info.dart';
import '../../../update/presentation/update_prompt.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../../../../main.dart';
import '../../../documents/presentation/providers/document_provider.dart';
import '../../../ocr/presentation/widgets/vision_key_dialog.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
            _buildTopBanner(context),
            _buildActionGrid(context),
            const SizedBox(height: 8),
            _buildSettingsList(context, dividerColor),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBanner(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFE0B2), Color(0xFFFFB74D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.only(top: 16, bottom: 24, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(icon: const Icon(Icons.crop_free, color: Colors.black87), onPressed: () {}),
              IconButton(icon: const Icon(Icons.message, color: Colors.black87), onPressed: () {}),
            ],
          ),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white70,
                child: const Icon(Icons.person, size: 36, color: Color(0xFFE65100)),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bind Phone/Email', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(
                      'Bind AH Scanner account for 10GB cloud space and multi-device sync',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFECCC),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('AH Scanner Pro', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('20+ Pro Privileges Active', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
                const Icon(Icons.chevron_right, color: Colors.black87),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.cardColor,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildGridItem(context, Icons.cloud_upload, 'Cloud Space', Colors.blue),
          _buildGridItem(context, Icons.business_center, 'Business', Colors.teal),
          _buildGridItem(context, Icons.task_alt, 'Tasks', Colors.deepOrange),
          _buildGridItem(context, Icons.monetization_on, 'Points\n0 Points', Colors.amber[800]!),
        ],
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, IconData icon, String label, Color color) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
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
          _buildListTile(context, Icons.person_outline, 'Account'),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.cloud_sync_outlined, 'Sync'),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.document_scanner_outlined, 'Scan Settings'),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.key_outlined, 'OCR — Vision API Key', onTap: () {
            _showVisionApiKeyDialog(context);
          }),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.folder_open_outlined, 'Manage Documents'),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.settings_outlined, 'More Settings', onTap: () {
            context.push('/more_settings');
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
          _buildListTile(context, Icons.thumb_up_outlined, 'Recommend AH Scanner'),
          Divider(color: dividerColor, height: 1),
          _buildListTile(context, Icons.help_outline, 'Help & Feedback'),
          Divider(color: dividerColor, height: 1),
          const _StorageStatWidget(),
        ],
      ),
    );
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
      leading: Icon(icon, color: theme.iconTheme.color?.withOpacity(0.7) ?? Colors.grey),
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(trailingText, style: TextStyle(color: Colors.teal, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: theme.iconTheme.color?.withOpacity(0.4) ?? Colors.grey, size: 18),
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
      leading: Icon(Icons.storage, color: theme.iconTheme.color?.withOpacity(0.7) ?? Colors.grey),
      title: Text('Local Storage Used', style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: Text(_usedSpace, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6), fontSize: 13)),
    );
  }
}
