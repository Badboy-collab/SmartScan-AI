/// Product naming contract for scanned documents.
///
/// Format: `AH Scaner DD.MM.YY H:MM` (for example `AH Scaner 20.08.26 1:16`).
///
/// The single "n" in "Scaner" is intentional: the document prefix is a fixed
/// product-string and is NOT the app name. The app itself is named
/// "AH Scanner" (see android/app/src/main/res/values/strings.xml).
String defaultDocumentName([DateTime? at]) {
  final now = at ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final year = two(now.year % 100);
  final hour = now.hour.toString();
  final minute = two(now.minute);
  return 'AH Scaner ${two(now.day)}.${two(now.month)}.$year $hour:$minute';
}
