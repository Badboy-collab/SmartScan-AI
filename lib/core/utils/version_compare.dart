/// Version comparison used by the update check.
///
/// Kept dependency-free (no Flutter, no packages) so it can be unit tested
/// without the app's native toolchain - see `test_logic/`.
///
/// `a` newer than `b` -> positive, equal -> 0, older -> negative.
/// Only the numeric `major.minor.patch` part is compared; a leading `v` and any
/// `+build` suffix are ignored.
int compareVersionStrings(String a, String b) {
  final left = _parts(a);
  final right = _parts(b);
  for (int i = 0; i < 3; i++) {
    final diff = left[i] - right[i];
    if (diff != 0) return diff;
  }
  return 0;
}

List<int> _parts(String raw) {
  final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
  final segments = cleaned.split('.');
  return List<int>.generate(3, (index) {
    if (index >= segments.length) return 0;
    final match = RegExp(r'\d+').firstMatch(segments[index]);
    return match == null ? 0 : (int.tryParse(match.group(0)!) ?? 0);
  });
}
