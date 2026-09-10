import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_example/main.dart';

/// The loop the package is for: drive the app, keep what was driven, turn it
/// into a file a developer commits, and have that file pass.
///
/// Each half was tested on its own before this and the join was not, which is
/// how the recorder ended up storing only the value of a locator: replaying
/// `text: "Sign in"` then looked for a widget registered under the id
/// "Sign in", and nothing failed until someone tried it.
void main() {
  final manager = SelfTestManager();

  setUp(() async {
    manager.useRecordingStore(InMemoryRecordingStore());
    await manager.initializeRecordingStore();
    manager.setSelfTestModeActive(true);
  });

  tearDown(() async {
    manager.stopRecording();
    manager.setRecordingMode(RecordingMode.inactive);
    manager.setSelfTestModeActive(false);
    manager.clearClock();
    await manager.clearRecordings();
  });

  Future<void> driveTheLoginFlow(WidgetTester tester) async {
    await manager.enterText('username_field', 'ada');
    await tester.pumpAndSettle();
    await manager.enterText('password_field', 'lovelace');
    await tester.pumpAndSettle();
    await manager.trigger('login_button');
    await tester.pumpAndSettle();
    // A recording with no assertion produces a test that drives the app and
    // checks nothing, which passes on a screen that went blank.
    await manager.recordAssertion(
      const SelfTestLocator.text('Login successful!'),
    );
  }

  testWidgets('a recorded session keeps how each widget was addressed', (
    tester,
  ) async {
    await tester.pumpWidget(SelfTestRoot(child: const MyApp()));
    await tester.pumpAndSettle();

    await manager.startRecording('login flow');
    await tester.pumpAndSettle();
    await driveTheLoginFlow(tester);
    manager.stopRecording();

    final script = manager.getTestScripts().single;
    final steps = manager.getTestSteps(script.id);

    expect(steps.map((step) => step.action), [
      'enterText',
      'enterText',
      'trigger',
      'assertText',
    ]);
    expect(steps.map((step) => step.targetId), [
      'username_field',
      'password_field',
      'login_button',
      'Login successful!',
    ]);
    expect(steps.last.locator, const SelfTestLocator.text('Login successful!'));
    expect(
      steps.every((step) => step.locator != null),
      isTrue,
      reason: 'a step that does not know how it was addressed cannot replay',
    );
    expect(steps.first.value, 'ada');
  });

  testWidgets('the recorded session replays against a fresh app', (
    tester,
  ) async {
    await tester.pumpWidget(SelfTestRoot(child: const MyApp()));
    await tester.pumpAndSettle();
    await manager.startRecording('login flow');
    await tester.pumpAndSettle();
    await driveTheLoginFlow(tester);
    manager.stopRecording();
    final steps = manager.getTestSteps(manager.getTestScripts().single.id);

    // A new tree, with nothing carried over from the recording.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(SelfTestRoot(child: const MyApp()));
    await tester.pumpAndSettle();
    expect(
      manager.exists(const SelfTestLocator.text('Login successful!')),
      isFalse,
    );

    for (final step in steps) {
      await manager.replayStep(step);
      await tester.pumpAndSettle();
    }

    expect(
      manager.exists(const SelfTestLocator.text('Login successful!')),
      isTrue,
      reason: 'replaying the recording put the app in the same state',
    );
  });

  testWidgets('the committed generated test is what the recorder produces', (
    tester,
  ) async {
    await tester.pumpWidget(SelfTestRoot(child: const MyApp()));
    await tester.pumpAndSettle();
    await manager.startRecording('login flow');
    await tester.pumpAndSettle();
    await driveTheLoginFlow(tester);
    manager.stopRecording();

    final script = manager.getTestScripts().single;
    final generated = TestCodeGenerator().generateTestCode(
      script,
      manager.getTestSteps(script.id),
      appExpression: 'SelfTestRoot(child: const MyApp())',
      appImport: 'package:self_test_example/main.dart',
    );

    // test/, not integration_test/: `flutter test integration_test/x.dart`
    // asks for a connected device, so a generated test parked there is one CI
    // never runs, and a replay nobody replays proves nothing.
    final committed = File('test/generated_test.dart');
    expect(
      committed.existsSync(),
      isTrue,
      reason: 'the generated test is committed so CI runs it',
    );
    // Compared modulo formatting: the repo's formatter rewraps the committed
    // copy and adds a trailing comma wherever it breaks a call across lines,
    // so a byte comparison would fail on style rather than on content. What
    // this has to catch is the generator emitting different code.
    String normalise(String source) => source
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r',\s*\)'), ')')
        .replaceAll(RegExp(r'\(\s+'), '(')
        .trim();
    expect(
      normalise(generated),
      normalise(committed.readAsStringSync()),
      reason:
          'regenerate it with this test and commit the result. Generated '
          'code that no longer matches its source compiles, so nothing '
          'complains, and it lies.',
    );
  });
}
