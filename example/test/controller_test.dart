import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_example/example.dart';

// The controller is generated from the annotations in lib/example.dart:
//   dart run build_runner build
// Regenerating is part of CI, so a drift between the annotations and this
// test fails the build rather than rotting quietly.
import 'package:self_test_example/example.g.dart';

void main() {
  late ExampleStateTestController controller;

  setUp(() {
    SelfTestManager().setTestMode(true);
    controller = ExampleStateTestController();
  });

  testWidgets('the generated controller drives the app by id', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExampleWidget()));

    // Registration happens as the widgets build.
    controller.expectLoginBtnExists();
    controller.expectUsernameFieldExists();

    controller.enterUsernameField('daniel');
    await tester.pump();

    controller.expectUsernameFieldText('daniel');
    expect(find.text('Current username: daniel'), findsOneWidget);

    controller.tapLoginBtn();
    await tester.pump();
  });

  testWidgets('an assertion on a missing id fails loudly', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(controller.expectLoginBtnExists, throwsStateError);
    expect(
        () => controller.expectUsernameFieldText('daniel'), throwsStateError);
  });

  testWidgets('a wrong expected text reports the value it actually found',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExampleWidget()));
    controller.enterUsernameField('daniel');
    await tester.pump();

    expect(
      () => controller.expectUsernameFieldText('someone else'),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        allOf(contains('someone else'), contains('daniel')),
      )),
    );
  });
}
