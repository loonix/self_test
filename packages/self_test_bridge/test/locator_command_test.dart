import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

/// A screen written by someone who never heard of this package: no
/// `SelfTestRoot`, no `SelfTestableWidget`, no ids. Locators are the reason the
/// bridge can drive it at all, so the tests use exactly that.
class PlainScreen extends StatefulWidget {
  const PlainScreen({super.key});

  @override
  State<PlainScreen> createState() => _PlainScreenState();
}

class _PlainScreenState extends State<PlainScreen> {
  final _email = TextEditingController();
  int taps = 0;
  String message = 'Nothing yet';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            ElevatedButton(
              onPressed: () => setState(() {
                taps++;
                message = 'Signed in as ${_email.text}';
              }),
              child: const Text('Sign in'),
            ),
            Text(message),
            const Tooltip(
              message: 'Remove this row',
              child: Icon(Icons.delete),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builds the command the socket would have parsed.
BridgeCommand cmd(String command, [Map<String, dynamic> params = const {}]) =>
    BridgeCommand(id: 1, command: command, params: params);

Map<String, dynamic> textLocator(String value, {bool? exact, int? index}) => {
  'by': 'text',
  'value': value,
  if (exact != null) 'exact': exact,
  if (index != null) 'index': index,
};

void main() {
  late SelfTestBridge bridge;

  setUp(() => bridge = SelfTestBridge(port: 0));

  tearDown(() async {
    await bridge.stop();
    SelfTestManager().clearClock();
  });

  group('actions driven by locator', () {
    testWidgets('a locator-driven tap actually taps', (tester) async {
      await tester.pumpWidget(const PlainScreen());
      final state = tester.state<_PlainScreenState>(find.byType(PlainScreen));

      final response = await bridge.dispatchForTest(
        cmd('tap', {'locator': textLocator('Sign in')}),
      );

      expect(response.error, isNull, reason: 'the command should have run');
      expect(response.result, {'success': true});
      expect(
        state.taps,
        1,
        reason:
            'the bridge answers only once the tap has happened, not before. '
            'The manager methods are async and the dispatcher used to drop '
            'their futures.',
      );
    });

    testWidgets('a locator beats a widgetId when both are sent', (
      tester,
    ) async {
      await tester.pumpWidget(const PlainScreen());
      final state = tester.state<_PlainScreenState>(find.byType(PlainScreen));

      // The widgetId names a widget that was never registered, so taking that
      // path would fail. Taking the locator path taps the button.
      final response = await bridge.dispatchForTest(
        cmd('tap', {
          'widgetId': 'never_registered',
          'locator': textLocator('Sign in'),
        }),
      );

      expect(response.error, isNull);
      expect(state.taps, 1);
    });

    testWidgets('type by locator enters text the app really reads', (
      tester,
    ) async {
      await tester.pumpWidget(const PlainScreen());
      final state = tester.state<_PlainScreenState>(find.byType(PlainScreen));

      await bridge.dispatchForTest(
        cmd('type', {
          'locator': textLocator('Email'),
          'text': 'ada@example.com',
        }),
      );
      await bridge.dispatchForTest(
        cmd('tap', {'locator': textLocator('Sign in')}),
      );

      expect(state.message, 'Signed in as ada@example.com');
    });

    testWidgets('type with submit fires the field action', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('type', {
          'locator': textLocator('Email'),
          'text': 'ada',
          'submit': true,
        }),
      );

      expect(response.error, isNull);
    });

    testWidgets('clear by locator empties the field', (tester) async {
      await tester.pumpWidget(const PlainScreen());
      // The field itself, not the label the locator is aimed at: a locator on
      // 'Email' resolves the label, and typeInto walks from there to the field
      // beside it.
      String fieldText() =>
          tester.widget<TextField>(find.byType(TextField)).controller!.text;

      await bridge.dispatchForTest(
        cmd('type', {'locator': textLocator('Email'), 'text': 'ada'}),
      );
      expect(fieldText(), 'ada');

      await bridge.dispatchForTest(
        cmd('clear', {'locator': textLocator('Email')}),
      );
      expect(fieldText(), isEmpty);
    });
  });

  group('queries driven by locator', () {
    testWidgets('describeScreen returns the widgets on screen', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(cmd('describeScreen'));

      expect(response.error, isNull);
      final widgets = (response.result as Map)['widgets'] as List;
      expect(widgets, isNotEmpty);

      // The shape is WidgetSnapshot.toJson, which the MCP server is built
      // against: type, enabled, interactive, onScreen and a rect.
      final first = widgets.first as Map<String, dynamic>;
      expect(first, containsPair('type', isA<String>()));
      expect(first, containsPair('enabled', isA<bool>()));
      expect(first, containsPair('interactive', isA<bool>()));
      expect(first, containsPair('onScreen', isA<bool>()));
      expect(first['rect'], isA<Map<String, dynamic>>());

      final texts = widgets
          .map((w) => (w as Map<String, dynamic>)['text'])
          .toList();
      expect(texts, contains('Sign in'));
    });

    testWidgets('find returns the matching widget, or null', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final hit = await bridge.dispatchForTest(
        cmd('find', {'locator': textLocator('Sign in')}),
      );
      final widget = (hit.result as Map)['widget'] as Map<String, dynamic>;
      expect(widget['text'], 'Sign in');

      final miss = await bridge.dispatchForTest(
        cmd('find', {'locator': textLocator('Not on this screen')}),
      );
      expect((miss.result as Map)['widget'], isNull);
    });

    testWidgets('exists and isVisible answer separately', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final exists = await bridge.dispatchForTest(
        cmd('exists', {'locator': textLocator('Sign in')}),
      );
      expect((exists.result as Map)['result'], isTrue);

      final missing = await bridge.dispatchForTest(
        cmd('exists', {'locator': textLocator('Sign out')}),
      );
      expect((missing.result as Map)['result'], isFalse);

      final visible = await bridge.dispatchForTest(
        cmd('isVisible', {'locator': textLocator('Sign in')}),
      );
      expect((visible.result as Map)['result'], isTrue);
    });

    testWidgets('readText reads the text a widget is showing', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('readText', {'locator': textLocator('Nothing yet')}),
      );
      expect((response.result as Map)['text'], 'Nothing yet');
    });

    testWidgets('a tooltip locator reaches an icon with no text', (
      tester,
    ) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('exists', {
          'locator': {'by': 'tooltip', 'value': 'Remove this row'},
        }),
      );
      expect((response.result as Map)['result'], isTrue);
    });
  });

  group('a malformed locator', () {
    testWidgets('is refused when it is not an object', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('tap', {'locator': 'Sign in'}),
      );

      expect(response.result, isNull);
      expect(response.error, contains('must be an object'));
    });

    testWidgets('is refused when "by" names an unknown strategy', (
      tester,
    ) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('exists', {
          'locator': {'by': 'colour', 'value': 'red'},
        }),
      );

      expect(response.error, contains('Unknown locator strategy'));
      expect(
        response.error,
        contains('semanticsLabel'),
        reason: 'the error lists what it could have asked for',
      );
    });

    testWidgets('is refused when "by" is missing', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('exists', {
          'locator': {'value': 'Sign in'},
        }),
      );

      expect(response.error, contains('missing "by"'));
    });

    testWidgets('is refused when "value" is not a string', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('exists', {
          'locator': {'by': 'text', 'value': 42},
        }),
      );

      expect(response.error, contains('must be a String'));
    });

    testWidgets('is refused when "index" is negative', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('exists', {'locator': textLocator('Sign in', index: -1)}),
      );

      expect(response.error, contains('0 or more'));
    });

    testWidgets('is refused when "exact" is not a boolean', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('exists', {
          'locator': {'by': 'text', 'value': 'Sign in', 'exact': 'yes'},
        }),
      );

      expect(response.error, contains('true or false'));
    });

    testWidgets('a command that needs a locator says so when none is sent', (
      tester,
    ) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(cmd('exists'));

      expect(response.error, contains('needs a "locator"'));
    });

    testWidgets('no locator and no widgetId is refused, not guessed at', (
      tester,
    ) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(cmd('focus'));

      expect(response.error, contains('"locator"'));
      expect(response.error, contains('widgetId'));
    });
  });

  group('the dispatcher itself', () {
    testWidgets('names the command it does not know', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(cmd('teleport'));

      expect(response.error, contains('Unknown command: teleport'));
    });

    testWidgets('answers with the id it was asked under', (tester) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        BridgeCommand(id: 77, command: 'describeScreen', params: const {}),
      );

      expect(response.id, 77);
    });

    testWidgets('turns a thrown error into a response, not a crash', (
      tester,
    ) async {
      await tester.pumpWidget(const PlainScreen());

      final response = await bridge.dispatchForTest(
        cmd('tap', {'locator': textLocator('No such button')}),
      );

      expect(response.error, isNotNull);
      expect(response.result, isNull);
    });
  });
}
