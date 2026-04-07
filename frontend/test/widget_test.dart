import 'package:flutter_test/flutter_test.dart';
import 'package:remediation_frontend/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RemediationApp());
    await tester.pump(const Duration(seconds: 1));
  });
}
