import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

/// A plain app. No `SelfTestRoot`, no `SelfTestableWidget`, no annotations,
/// no generated code: exactly what a package the app has never heard of has
/// to work against.
Widget _plainApp() => MaterialApp(
  home: Scaffold(
    appBar: AppBar(title: const Text('Locators')),
    body: Column(
      children: [
        const Text('Welcome back'),
        ElevatedButton(
          key: const ValueKey('go'),
          onPressed: () {},
          child: const Text('Go'),
        ),
        const ElevatedButton(onPressed: null, child: Text('Off')),
        IconButton(
          tooltip: 'Delete',
          onPressed: () {},
          icon: const Icon(Icons.delete),
        ),
        const TextField(key: ValueKey('name')),
        Semantics(
          label: 'avatar',
          child: const SizedBox(width: 24, height: 24),
        ),
        const Text('Items: 3'),
      ],
    ),
  ),
);

void main() {
  group('SelfTestLocator as a value', () {
    test('survives a JSON round trip', () {
      final locators = [
        const SelfTestLocator.id('login'),
        const SelfTestLocator.key('go'),
        const SelfTestLocator.text('Go'),
        const SelfTestLocator.text('Items', exact: false),
        const SelfTestLocator.semantics('avatar'),
        const SelfTestLocator.type('Switch'),
        const SelfTestLocator.tooltip('Delete'),
        const SelfTestLocator.text('Row').at(3),
      ];

      for (final locator in locators) {
        expect(SelfTestLocator.fromJson(locator.toJson()), locator);
      }
    });

    test('rejects a strategy it cannot honour instead of guessing', () {
      expect(
        () => SelfTestLocator.fromJson({'by': 'xpath', 'value': '//button'}),
        throwsArgumentError,
      );
      expect(
        () => SelfTestLocator.fromJson({'value': 'Go'}),
        throwsArgumentError,
      );
      expect(
        () => SelfTestLocator.fromJson({'by': 'text', 'value': 7}),
        throwsArgumentError,
      );
    });

    test('refuses a negative index', () {
      expect(() => const SelfTestLocator.text('Go').at(-1), throwsRangeError);
    });

    test('describes itself readably', () {
      expect(
        const SelfTestLocator.text('Go', exact: false).at(2).toString(),
        'text: "Go" (contains, index: 2)',
      );
    });
  });

  group('ElementScanner on an app that knows nothing about self_test', () {
    const scanner = ElementScanner();

    testWidgets('finds a widget by the text it paints', (tester) async {
      await tester.pumpWidget(_plainApp());

      final found = scanner.resolve(const SelfTestLocator.text('Go'));

      expect(found.typeName, 'Text');
      expect(found.text, 'Go');
      expect(found.hasSize, isTrue);
    });

    testWidgets('matches a substring when asked to', (tester) async {
      await tester.pumpWidget(_plainApp());

      final found = scanner.resolve(
        const SelfTestLocator.text('Items', exact: false),
      );

      expect(found.text, 'Items: 3');
      expect(
        scanner.tryResolve(const SelfTestLocator.text('Items')),
        isNull,
        reason: 'an exact locator must not match a substring',
      );
    });

    testWidgets('finds a widget by ValueKey', (tester) async {
      await tester.pumpWidget(_plainApp());

      expect(
        scanner.resolve(const SelfTestLocator.key('go')).typeName,
        'ElevatedButton',
      );
    });

    testWidgets('finds an icon-only button by its tooltip', (tester) async {
      await tester.pumpWidget(_plainApp());

      expect(
        scanner.resolve(const SelfTestLocator.tooltip('Delete')).typeName,
        'IconButton',
      );
    });

    testWidgets('reads a tooltip as a semantics label too', (tester) async {
      await tester.pumpWidget(_plainApp());

      expect(
        scanner.resolve(const SelfTestLocator.semantics('Delete')).typeName,
        'IconButton',
      );
      expect(
        scanner.resolve(const SelfTestLocator.semantics('avatar')).typeName,
        'Semantics',
      );
    });

    testWidgets('finds widgets by type', (tester) async {
      await tester.pumpWidget(_plainApp());

      final buttons = scanner.findAll(
        const SelfTestLocator.type('ElevatedButton'),
      );

      expect(buttons, hasLength(2));
      expect(buttons.first.isEnabled, isTrue);
      expect(
        buttons.last.isEnabled,
        isFalse,
        reason: 'a null onPressed is a disabled button',
      );
    });

    testWidgets('index picks between duplicates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(children: [Text('Row'), Text('Row'), Text('Row')]),
          ),
        ),
      );

      expect(scanner.findAll(const SelfTestLocator.text('Row')), hasLength(3));
      final second = scanner.resolve(const SelfTestLocator.text('Row').at(1));
      final third = scanner.resolve(const SelfTestLocator.text('Row').at(2));
      expect(
        second.bounds.top,
        lessThan(third.bounds.top),
        reason: 'index follows tree order, which here is top to bottom',
      );
    });

    testWidgets('says what was on screen when it finds nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_plainApp());

      Object? thrown;
      try {
        scanner.resolve(const SelfTestLocator.text('Nope'));
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<WidgetNotFoundError>());
      final message = thrown.toString();
      expect(message, contains('No widget matches text: "Nope"'));
      expect(
        message,
        contains('Go'),
        reason: 'the failure has to list the widgets that were there',
      );
    });

    testWidgets('reports an index past the end as such', (tester) async {
      await tester.pumpWidget(_plainApp());

      expect(
        () => scanner.resolve(const SelfTestLocator.text('Go').at(4)),
        throwsA(
          isA<WidgetNotFoundError>().having(
            (e) => e.toString(),
            'message',
            contains('only 1 widget(s) match'),
          ),
        ),
      );
    });

    testWidgets('describes what can be acted on', (tester) async {
      await tester.pumpWidget(_plainApp());

      final screen = SelfTestManager().describeScreen();
      final types = screen.map((s) => s.typeName).toSet();

      expect(types, contains('ElevatedButton'));
      expect(types, contains('IconButton'));
      expect(types, contains('TextField'));
      expect(
        screen.where((s) => s.text == 'Welcome back'),
        isNotEmpty,
        reason: 'labels give an agent the context to choose',
      );
      expect(
        screen.every((s) => s.hasSize),
        isTrue,
        reason: 'a widget with no box is nothing an agent can act on',
      );
    });

    testWidgets('a snapshot serialises for the bridge', (tester) async {
      await tester.pumpWidget(_plainApp());

      final json = scanner
          .resolve(const SelfTestLocator.tooltip('Delete'))
          .toJson();

      expect(json['type'], 'IconButton');
      expect(json['tooltip'], 'Delete');
      expect(json['enabled'], isTrue);
      expect(json['interactive'], isTrue);
      expect((json['rect']! as Map)['w'], greaterThan(0));
    });
  });
}
