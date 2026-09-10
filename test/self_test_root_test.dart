import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

void main() {
  // Every one of these calls pumpAndSettle. That is the point: the recording
  // controls are a live overlay, and while they were drawn into every debug
  // tree, pumpAndSettle on a widget wrapped in SelfTestRoot never returned.
  // Six tests in the example app hung for the full ten-minute timeout.

  setUp(() {
    // Nodes only register once the manager has been switched on, so the last
    // test here has to opt in. Also clears state the singleton carried over
    // from a previous test.
    SelfTestManager().setTestMode(true);
    SelfTestManager().activeTestNodes.clear();
  });

  Widget app({bool? showControls}) => MaterialApp(
        home: SelfTestRoot(
          showControls: showControls,
          child: const Scaffold(body: Text('app under test')),
        ),
      );

  testWidgets('by default pumpAndSettle returns under the test binding',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('app under test'), findsOneWidget);
  });

  testWidgets('by default the controls are not drawn in a test',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('TEST'), findsNothing);
  });

  testWidgets('showControls: false keeps the app clean', (tester) async {
    await tester.pumpWidget(app(showControls: false));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('app under test'), findsOneWidget);
  });

  testWidgets('showControls: true draws them, for a test that wants them',
      (tester) async {
    await tester.pumpWidget(app(showControls: true));
    // Deliberately pump rather than settle: with the controls up, settling is
    // exactly what does not terminate.
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('TEST'), findsOneWidget);
    expect(find.text('app under test'), findsOneWidget);
  });

  testWidgets('the child is still reachable through the wrapper',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SelfTestRoot(
          child: Scaffold(
            body: SelfTestableWidget(
              id: 'greet_btn',
              onTap: () {},
              child: const Text('hello'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(SelfTestManager().activeTestNodes.containsKey('greet_btn'), isTrue);
  });
}
