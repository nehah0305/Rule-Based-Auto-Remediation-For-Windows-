// Widget tests for the QA-gap UI fixes: empty states, the horizontal scroll
// hint, and the screens that use them. Network calls fail fast under
// flutter_test's mocked HttpClient, which exercises exactly the empty-state
// fallback paths.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remediation_frontend/screens/approvals_screen.dart';
import 'package:remediation_frontend/screens/history_screen.dart';
import 'package:remediation_frontend/services/remediation_service.dart';
import 'package:remediation_frontend/widgets/empty_state.dart';
import 'package:remediation_frontend/widgets/scroll_hint.dart';

void main() {
  testWidgets('EmptyState renders icon, message and hint', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyState(icon: Icons.inbox_rounded, message: 'Nothing here', hint: 'A hint'),
      ),
    ));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('A hint'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
  });

  Widget hintHarness(ScrollController controller, {required double contentWidth}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 100,
            child: Stack(children: [
              SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: contentWidth, height: 100),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: HorizontalScrollHint(controller: controller),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  double hintOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.descendant(
          of: find.byType(HorizontalScrollHint),
          matching: find.byType(AnimatedOpacity)))
      .opacity;

  testWidgets('HorizontalScrollHint visible only while columns remain off-screen', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(hintHarness(controller, contentWidth: 900));
    await tester.pump();                                   // post-frame check
    await tester.pump(const Duration(milliseconds: 250));  // fade animation
    expect(hintOpacity(tester), 1.0,
        reason: 'hint must be visible while content overflows to the right');

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(hintOpacity(tester), 0.0,
        reason: 'hint must disappear once the user reaches the last column');
  });

  testWidgets('HorizontalScrollHint stays hidden when nothing overflows', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(hintHarness(controller, contentWidth: 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(hintOpacity(tester), 0.0);
  });

  testWidgets('ApprovalsScreen builds and falls back to EmptyState when API unavailable', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ApprovalsScreen())));
    await tester.pump();                         // kick off the async load
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No approval requests in this view.'), findsOneWidget);
  });

  testWidgets('HistoryScreen builds and shows EmptyState when API unavailable', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider(
          create: (_) => RemediationService(),
          child: const HistoryScreen(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No history found'), findsOneWidget);
  });
}
