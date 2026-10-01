import 'package:flutter/services.dart';

/// Method channel shared with `MainActivity` (the same one used for gallery
/// saves). Reusing it keeps the plugin surface at zero extra dependencies.
const MethodChannel appPlatformChannel =
    MethodChannel('ah_scanner/media_store');

/// Hands a URL to Android (`ACTION_VIEW`), i.e. the browser or the store page.
///
/// Returns `false` when nothing can handle the link — callers should surface a
/// message instead of failing silently.
Future<bool> openExternalUrl(String url) async {
  if (url.trim().isEmpty) return false;
  try {
    final opened = await appPlatformChannel
        .invokeMethod<bool>('openUrl', {'url': url});
    return opened ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
