import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

/// Everything this package does to an app is also what someone attacking it
/// would want to do: read the whole widget tree, tap anything, type anything,
/// photograph the screen. In debug that is the product. In the build that
/// reaches a user it is a remote control, and the bridge listens on a socket.
///
/// `kReleaseMode` is a compile-time constant and false in every test, so the
/// guard is checked through [SelfTestManager.debugSimulateReleaseBuild]. That
/// seam exists because the alternative is a security control nothing verifies.
void main() {
  final manager = SelfTestManager();

  setUp(() {
    SelfTestManager.debugSimulateReleaseBuild = null;
    SelfTestManager.resetReleaseBuildOptIn();
    manager.activeTestNodes.clear();
  });

  tearDown(() {
    SelfTestManager.debugSimulateReleaseBuild = null;
    SelfTestManager.resetReleaseBuildOptIn();
    manager.clearClock();
  });

  Widget app({VoidCallback? onPressed}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: onPressed ?? () {},
            child: const Text('Pay now'),
          ),
          const TextField(key: ValueKey('card')),
        ],
      ),
    ),
  );

  test('is on in a debug build, which is where it is meant to be used', () {
    expect(SelfTestManager.isEnabled, isTrue);
  });

  test('is off in a release build', () {
    SelfTestManager.debugSimulateReleaseBuild = true;

    expect(SelfTestManager.isEnabled, isFalse);
  });

  group('a release build is inert', () {
    testWidgets('refuses to tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(app(onPressed: () => taps++));
      SelfTestManager.debugSimulateReleaseBuild = true;

      await expectLater(
        manager.tap(const SelfTestLocator.text('Pay now')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disabled in release builds'),
          ),
        ),
      );
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('refuses to type', (tester) async {
      await tester.pumpWidget(app());
      SelfTestManager.debugSimulateReleaseBuild = true;

      await expectLater(
        manager.typeInto(const SelfTestLocator.key('card'), '4111'),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('refuses to drive by id, the old API included', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelfTestableWidget(
            id: 'pay',
            onTap: () {},
            child: const Text('Pay now'),
          ),
        ),
      );
      SelfTestManager.debugSimulateReleaseBuild = true;

      await expectLater(manager.trigger('pay'), throwsA(isA<StateError>()));
      await expectLater(
        manager.enterText('pay', 'x'),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('describes nothing, because reading the tree is disclosure', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      expect(manager.describeScreen(), isNotEmpty);

      SelfTestManager.debugSimulateReleaseBuild = true;

      expect(manager.describeScreen(), isEmpty);
      expect(manager.findAll(const SelfTestLocator.text('Pay now')), isEmpty);
      expect(manager.exists(const SelfTestLocator.text('Pay now')), isFalse);
      expect(
        () => manager.find(const SelfTestLocator.text('Pay now')),
        throwsA(isA<WidgetNotFoundError>()),
      );
    });

    testWidgets('refuses to photograph the screen', (tester) async {
      await tester.pumpWidget(app());
      SelfTestManager.debugSimulateReleaseBuild = true;

      await expectLater(
        manager.captureScreenshotBytes(),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('refuses to record', (tester) async {
      await tester.pumpWidget(app());
      SelfTestManager.debugSimulateReleaseBuild = true;

      await expectLater(
        manager.startRecording('session'),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('keeps no register of what could be driven', (tester) async {
      SelfTestManager.debugSimulateReleaseBuild = true;
      manager.setTestMode(true);
      addTearDown(() => manager.setTestMode(false));

      await tester.pumpWidget(
        MaterialApp(
          home: SelfTestableWidget(
            id: 'pay',
            onTap: () {},
            child: const Text('Pay now'),
          ),
        ),
      );

      expect(manager.activeTestNodes, isEmpty);
    });
  });

  group('opting in', () {
    testWidgets('a device farm can turn it back on deliberately', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(app(onPressed: () => taps++));
      SelfTestManager.debugSimulateReleaseBuild = true;
      SelfTestManager.enableInReleaseBuilds();

      expect(SelfTestManager.isEnabled, isTrue);
      await manager.tap(const SelfTestLocator.text('Pay now'));
      await tester.pump();

      expect(taps, 1);
    });

    test('takes a deliberate call, never a flag that could be flipped', () {
      SelfTestManager.debugSimulateReleaseBuild = true;
      expect(SelfTestManager.isEnabled, isFalse);

      SelfTestManager.enableInReleaseBuilds();
      expect(SelfTestManager.isEnabled, isTrue);

      SelfTestManager.resetReleaseBuildOptIn();
      expect(SelfTestManager.isEnabled, isFalse);
    });
  });
}
