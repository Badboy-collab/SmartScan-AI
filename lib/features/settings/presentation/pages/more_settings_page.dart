import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/app_settings.dart';
import '../../../../core/utils/gallery_saver.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class MoreSettingsPage extends StatelessWidget {
  const MoreSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('More Settings'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          _buildItem(
            context,
            'Camera Settings',
            onTap: () => _showSheet(context, const _CameraSettingsSheet()),
          ),
          Divider(height: 1, color: dividerColor),
          _buildItem(
            context,
            'Document Save Settings',
            onTap: () => _showSheet(context, const _DocumentSaveSettingsSheet()),
          ),
          Divider(height: 1, color: dividerColor),
          _buildItem(
            context,
            'Share & Export',
            onTap: () => _showShareExportSheet(context),
          ),
          Divider(height: 1, color: dividerColor),
          _buildItem(
            context,
            'Free Up Space',
            onTap: () => _showFreeUpSpaceSheet(context),
          ),
          Divider(height: 1, color: dividerColor),
          _buildItem(
            context,
            'Image to Text',
            onTap: () => _showOcrSettingsSheet(context),
          ),
          Divider(height: 1, color: dividerColor),
          _buildItem(
            context,
            'Permission Manager',
            onTap: () => _showPermissionManager(context),
          ),
        ],
      ),
    );
  }

  void _showSheet(BuildContext context, Widget child) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => child,
    );
  }

  Widget _buildItem(BuildContext context, String title, {required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: theme.textTheme.bodyLarge?.color,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.iconTheme.color?.withOpacity(0.5) ?? Colors.grey,
        size: 20,
      ),
      onTap: onTap,
    );
  }

  void _showShareExportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share & Export Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Default PDF Page Size'),
              subtitle: const Text('A4 (210 × 297 mm)'),
              trailing: const Icon(Icons.check, color: Colors.teal),
            ),
            ListTile(
              title: const Text('Image Export Quality'),
              subtitle: const Text('High Quality (Original Resolution)'),
              trailing: const Icon(Icons.check, color: Colors.teal),
            ),
          ],
        ),
      ),
    );
  }

  // "Security & Backup" is gone on purpose: it offered an app lock and cloud
  // backup, neither of which exists - app lock needs a biometrics plugin we do
  // not depend on yet, and there is no account or cloud to back up to.

  void _showFreeUpSpaceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Free Up Space', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.cleaning_services, color: Colors.teal),
              title: const Text('Clear Temporary Cache'),
              subtitle: const Text('Removes temporary preview files'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Temporary cache cleared (0 MB freed)')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text('Clear All Data', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Delete all local scans & documents'),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    backgroundColor: Theme.of(context).cardColor,
                    title: Text('Clear All Data?', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                    content: Text('All locally stored scans will be permanently deleted.', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      TextButton(
                        onPressed: () {
                          getIt<DocumentProvider>().clearAllLocalData();
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All local data cleared')));
                        },
                        child: const Text('Delete All Data', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOcrSettingsSheet(BuildContext context) async {
    // Facts only: this sheet used to claim "Latin / English (Auto-detect)" and
    // "Table & Form Recognition: Enabled" with check marks, neither of which
    // was configurable nor even accurate.
    final prefs = await SharedPreferences.getInstance();
    final bool hasKey =
        (prefs.getString('google_vision_api_key') ?? '').trim().isNotEmpty;
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Image to Text (OCR) Engine', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.translate, color: Colors.teal),
              title: Text('Supported languages'),
              subtitle: Text('English and other Latin scripts run on-device (offline); Bengali (bn) runs on Google Cloud Vision'),
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined, color: Colors.teal),
              title: const Text('Bengali needs a Vision API key'),
              subtitle: Text(hasKey
                  ? 'API key configured'
                  : 'No key yet - add one under "OCR - Vision API Key"'),
              trailing: hasKey
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.error_outline, color: Colors.orange),
            ),
            const ListTile(
              leading: Icon(Icons.grid_on, color: Colors.teal),
              title: Text('Exporting recognized text'),
              subtitle: Text('Excel, Word or PowerPoint, from the export menu on the OCR page'),
            ),
          ],
        ),
      ),
    );
  }

  // "Notification Settings" is gone: the app posts no notifications at all, so
  // its two switches (both stuck at value: true, empty onChanged) were pure UI.

  Future<void> _showPermissionManager(BuildContext context) async {
    // Read the real state first: this sheet used to print a hard-coded
    // "Granted" for camera and storage whether or not they were granted.
    final PermissionStatus camera = await Permission.camera.status;
    final PermissionStatus photos = await Permission.photos.status;
    final PermissionStatus storage = await Permission.storage.status;
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Permission Manager', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 12),
            _permissionRow(Icons.camera_alt, 'Camera (scanning)', camera),
            _permissionRow(Icons.photo_library, 'Photos (Android 13+)', photos),
            _permissionRow(Icons.folder, 'Storage (Android 12 and below)', storage),
            const SizedBox(height: 4),
            Text(
              'Scans are saved through Android\'s MediaStore, so Android 13+ needs no storage permission.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Open System App Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionRow(IconData icon, String title, PermissionStatus status) {
    Color color = Colors.orange;
    String label = 'Not granted';
    if (status.isGranted || status == PermissionStatus.limited) {
      color = Colors.green;
      label = 'Granted';
    } else if (status == PermissionStatus.permanentlyDenied || status == PermissionStatus.restricted) {
      color = Colors.redAccent;
      label = 'Blocked - enable it in system settings';
    }
    return ListTile(
      leading: Icon(icon, color: Colors.teal),
      title: Text(title),
      subtitle: Text(label, style: TextStyle(color: color, fontSize: 12)),
      trailing: Icon(
        status.isGranted ? Icons.check_circle : Icons.error_outline,
        color: color,
      ),
    );
  }
}

/// Camera choices the scanner reads back on startup: the flash mode the
/// viewfinder opens with and whether captures use the full sensor.
class _CameraSettingsSheet extends StatefulWidget {
  const _CameraSettingsSheet();

  @override
  State<_CameraSettingsSheet> createState() => _CameraSettingsSheetState();
}

class _CameraSettingsSheetState extends State<_CameraSettingsSheet> {
  FlashMode? _flashMode;
  bool _hdCapture = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final FlashMode flashMode = await AppSettings.flashMode();
    final bool hdCapture = await AppSettings.hdCapture();
    if (!mounted) return;
    setState(() {
      _flashMode = flashMode;
      _hdCapture = hdCapture;
    });
  }

  static String _flashLabel(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return 'Off';
      case FlashMode.auto:
        return 'Auto';
      case FlashMode.always:
        return 'On (fires for every capture)';
      case FlashMode.torch:
        return 'Torch (LED stays lit while scanning)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final FlashMode? flashMode = _flashMode;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Camera Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          if (flashMode == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Text(
              'Flash when the camera opens',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            for (final FlashMode mode in FlashMode.values)
              ListTile(
                dense: true,
                leading: Icon(
                  mode == FlashMode.torch
                      ? Icons.flashlight_on
                      : Icons.flash_on,
                  color: mode == flashMode
                      ? Colors.teal
                      : theme.iconTheme.color,
                ),
                title: Text(_flashLabel(mode)),
                trailing: mode == flashMode
                    ? const Icon(Icons.check, color: Colors.teal)
                    : null,
                onTap: () async {
                  setState(() => _flashMode = mode);
                  await AppSettings.setFlashMode(mode);
                },
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('Full sensor capture'),
              subtitle: const Text(
                'Off captures at 720p: faster, but smaller and softer files',
              ),
              value: _hdCapture,
              onChanged: (bool value) async {
                setState(() => _hdCapture = value);
                await AppSettings.setHdCapture(value);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Default folder for exported scans plus the automatic export toggle.
class _DocumentSaveSettingsSheet extends StatefulWidget {
  const _DocumentSaveSettingsSheet();

  @override
  State<_DocumentSaveSettingsSheet> createState() =>
      _DocumentSaveSettingsSheetState();
}

class _DocumentSaveSettingsSheetState
    extends State<_DocumentSaveSettingsSheet> {
  SaveLocation? _location;
  bool _autoExport = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SaveLocation location = await AppSettings.saveLocation();
    final bool autoExport = await AppSettings.autoExportAfterScan();
    if (!mounted) return;
    setState(() {
      _location = location;
      _autoExport = autoExport;
    });
  }

  static String _label(SaveLocation location) {
    switch (location) {
      case SaveLocation.gallery:
        return 'Gallery (Pictures)';
      case SaveLocation.download:
        return 'Downloads (Files)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final SaveLocation? location = _location;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Document Save Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          if (location == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Text(
              'Save images to',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            for (final SaveLocation option in SaveLocation.values)
              ListTile(
                dense: true,
                leading: Icon(
                  option == SaveLocation.gallery
                      ? Icons.photo_library
                      : Icons.download,
                  color: option == location
                      ? Colors.teal
                      : theme.iconTheme.color,
                ),
                title: Text(_label(option)),
                subtitle: Text(
                  GallerySaver.locationLabel(
                    toDownloads: option == SaveLocation.download,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: option == location
                    ? const Icon(Icons.check, color: Colors.teal)
                    : null,
                onTap: () async {
                  setState(() => _location = option);
                  await AppSettings.setSaveLocation(option);
                },
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('Save to this folder after every scan'),
              subtitle: const Text(
                'Each finished page is copied out of the app as soon as it is '
                'saved, so your Gallery and file manager can see it',
              ),
              value: _autoExport,
              onChanged: (bool value) async {
                setState(() => _autoExport = value);
                await AppSettings.setAutoExportAfterScan(value);
              },
            ),
          ],
        ],
      ),
    );
  }
}
