import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

void main() {
  final manager = SelfTestManager();

  tearDown(manager.clearClock);

  group('a driven tap is a real pointer event', () {
    testWidgets('fires the app handler exactly once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('Press me'),
            ),
          ),
        ),
      );

      await manager.tap(const SelfTestLocator.text('Press me'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('a disabled button swallows it', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const ElevatedButton(onPressed: null, child: Text('Off')),
                ElevatedButton(
                  onPressed: () => taps++,
                  child: const Text('On'),
                ),
              ],
            ),
          ),
        ),
      );

      await manager.tap(const SelfTestLocator.text('Off'));
      await tester.pump();
      expect(taps, 0);

      await manager.tap(const SelfTestLocator.text('On'));
      await tester.pump();
      expect(taps, 1, reason: 'the enabled one still works');
    });

    testWidgets('a widget behind an overlay is not reachable', (tester) async {
      var buttonTaps = 0;
      var overlayTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: ElevatedButton(
                    onPressed: () => buttonTaps++,
                    child: const Text('Underneath'),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => overlayTaps++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await manager.tap(const SelfTestLocator.text('Underneath'));
      await tester.pump();

      expect(
        buttonTaps,
        0,
        reason:
            'hit testing is what makes this a real tap. Calling the '
            'registered onTap directly, which is what the old API did, would '
            'have reported a pass on a button the user cannot reach.',
      );
      expect(overlayTaps, 1, reason: 'the overlay got the tap, as it should');
    });

    testWidgets('refuses a widget that is in the tree with no size', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(child: Center(child: Text('Squashed'))),
          ),
        ),
      );

      expect(
        () => manager.tap(const SelfTestLocator.text('Squashed')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no size'),
          ),
        ),
      );
    });

    testWidgets('says what is on screen when the locator misses', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Only this'))),
      );

      await expectLater(
        manager.tap(const SelfTestLocator.text('Not here')),
        throwsA(isA<WidgetNotFoundError>()),
      );
    });
  });

  group('long press', () {
    testWidgets('holds the press when given a clock', (tester) async {
      var longPresses = 0;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onTap: () => taps++,
              onLongPress: () => longPresses++,
              child: const Text('Hold me'),
            ),
          ),
        ),
      );

      manager.useClock(tester.pump);
      await manager.longPress(const SelfTestLocator.text('Hold me'));
      await tester.pump();

      expect(longPresses, 1);
      expect(taps, 0, reason: 'a held press is not a tap');
    });

    testWidgets('refuses to degrade into a tap without one', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              onLongPress: () {},
              child: const Text('Hold me'),
            ),
          ),
        ),
      );

      await expectLater(
        manager.longPress(const SelfTestLocator.text('Hold me')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('useClock'),
          ),
        ),
      );
    });
  });

  group('text entry goes through the platform path', () {
    testWidgets('input formatters run, as they do for a real keyboard', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey('pin'),
              controller: controller,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ),
      );

      await manager.typeInto(const SelfTestLocator.key('pin'), 'a1b2c3');
      await tester.pump();

      expect(
        controller.text,
        '123',
        reason:
            'setting controller.text directly would have written a1b2c3 '
            'and passed a test the app fails',
      );
    });

    testWidgets('onChanged fires with the formatted value', (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(key: const ValueKey('name'), onChanged: seen.add),
          ),
        ),
      );

      await manager.typeInto(const SelfTestLocator.key('name'), 'Ada');
      await tester.pump();

      expect(seen, ['Ada']);
      expect(manager.readText(const SelfTestLocator.key('name')), 'Ada');
    });

    testWidgets('a form field validates what was typed', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: TextFormField(
                key: const ValueKey('email'),
                validator: (value) =>
                    value != null && value.contains('@') ? null : 'Bad email',
              ),
            ),
          ),
        ),
      );

      await manager.typeInto(const SelfTestLocator.key('email'), 'nope');
      await tester.pump();
      expect(formKey.currentState!.validate(), isFalse);

      await manager.typeInto(const SelfTestLocator.key('email'), 'a@b.com');
      await tester.pump();
      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('submitting fires the keyboard action', (tester) async {
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey('search'),
              onSubmitted: (value) => submitted = value,
            ),
          ),
        ),
      );

      await manager.typeInto(const SelfTestLocator.key('search'), 'flutter');
      await manager.submit(const SelfTestLocator.key('search'));
      await tester.pump();

      expect(submitted, 'flutter');
    });

    testWidgets('says so when the target is not a field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Just a label'))),
      );

      await expectLater(
        manager.typeInto(const SelfTestLocator.text('Just a label'), 'x'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('No text field'),
          ),
        ),
      );
    });
  });

  group('off screen is not the same as absent', () {
    testWidgets('refuses to tap a built but scrolled-away item', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('Item $i')),
              ],
            ),
          ),
        ),
      );

      await manager.scrollBy(
        const SelfTestLocator.type('ListView'),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();

      expect(manager.exists(const SelfTestLocator.text('Item 0')), isTrue);
      await expectLater(
        manager.tap(const SelfTestLocator.text('Item 0')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('outside the view'),
          ),
        ),
      );
    });
  });

  group('drag and scroll', () {
    testWidgets('a drag scrolls a list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('Item $i')),
              ],
            ),
          ),
        ),
      );

      expect(manager.isVisible(const SelfTestLocator.text('Item 0')), isTrue);

      await manager.dragFrom(
        const SelfTestLocator.type('ListView'),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // A drag carries velocity, so the list flings on and settles somewhere
      // past the drag distance. Asserting an exact item would be asserting
      // Flutter's scroll physics, which is not this package's job.
      expect(
        manager.isVisible(const SelfTestLocator.text('Item 0')),
        isFalse,
        reason: 'the list really moved',
      );
      final visible = manager
          .describeScreen()
          .map((snapshot) => snapshot.text)
          .whereType<String>()
          .where((text) => text.startsWith('Item '))
          .toList();
      expect(visible, isNotEmpty, reason: 'other items took its place');
    });

    testWidgets('a wheel scroll moves a list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('Item $i')),
              ],
            ),
          ),
        ),
      );

      // One item high, so Item 0 is just off the top edge and still inside
      // the list's cache extent. That is the gap between the two questions.
      await manager.scrollBy(
        const SelfTestLocator.type('ListView'),
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();

      expect(
        manager.isVisible(const SelfTestLocator.text('Item 0')),
        isFalse,
        reason: 'scrolled out of view',
      );
      expect(
        manager.exists(const SelfTestLocator.text('Item 0')),
        isTrue,
        reason:
            'but still built: a list keeps a cache of what just left, '
            'which is exactly why exists and isVisible are two questions',
      );
      expect(manager.isVisible(const SelfTestLocator.text('Item 2')), isTrue);
    });
  });
}
