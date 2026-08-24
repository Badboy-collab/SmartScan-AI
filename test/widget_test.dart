import 'package:flutter_test/flutter_test.dart';
import 'package:ah_scanner/main.dart';

void main() {
  testWidgets('App loads test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AHScannerApp());
    expect(find.byType(AHScannerApp), findsOneWidget);
  });
}
