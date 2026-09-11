import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

BridgeCommand cmd(String command, [Map<String, dynamic> params = const {}]) =>
    BridgeCommand(id: 1, command: command, params: params);

/// A two-screen app on the plain Navigator, which is what every Flutter app
/// has whether or not it uses a routing package.
Widget appWith(GlobalKey<NavigatorState> key, NavigatorObserver observer) {
  return MaterialApp(
    navigatorKey: key,
    navigatorObservers: [observer],
    initialRoute: '/',
    routes: {
      '/': (_) => const Scaffold(body: Text('Home')),
      '/settings': (_) => const Scaffold(body: Text('Settings')),
    },
  );
}

void main() {
  group('with no navigator configured', () {
    late SelfTestBridge bridge;

    setUp(() => bridge = SelfTestBridge(port: 0));
    tearDown(() => bridge.stop());

    test('the bridge has no navigator by default', () {
      expect(bridge.navigator, isNull);
    });

    // Every one of these used to answer {"success": true} while doing nothing,
    // because the call site was router?.go(...) and router was null. An agent
    // then asserted against a screen it had never left.
    for (final command in const [
      'navigate',
      'goBack',
      'reload',
      'restart',
      'getFlowGraph',
    ]) {
      test('$command returns an error rather than a false success', () async {
        final response = await bridge.dispatchForTest(
          cmd(command, {'route': '/settings'}),
        );

        expect(
          response.result,
          isA<Map<String, dynamic>>().having(
            (r) => r['error'],
            'error',
            allOf(
              contains('No BridgeNavigator is configured'),
              contains('NavigatorStateBridgeNavigator'),
            ),
          ),
          reason: 'it should say what to configure, not claim success',
        );
        expect(
          (response.result as Map)['success'],
          isNull,
          reason: 'nothing happened, so nothing succeeded',
        );
      });
    }
  });

  group('with the default NavigatorStateBridgeNavigator', () {
    late GlobalKey<NavigatorState> key;
    late NavigatorStateBridgeNavigator navigator;
    late SelfTestBridge bridge;

    setUp(() {
      key = GlobalKey<NavigatorState>();
      navigator = NavigatorStateBridgeNavigator(key);
      bridge = SelfTestBridge(port: 0, navigator: navigator);
    });

    tearDown(() => bridge.stop());

    testWidgets('navigate reaches the named route', (tester) async {
      await tester.pumpWidget(appWith(key, navigator.observer));
      expect(find.text('Home'), findsOneWidget);

      final response = await bridge.dispatchForTest(
        cmd('navigate', {'route': '/settings'}),
      );
      await tester.pumpAndSettle();

      expect(response.error, isNull);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('goBack returns to where it came from', (tester) async {
      await tester.pumpWidget(appWith(key, navigator.observer));

      await bridge.dispatchForTest(cmd('navigate', {'route': '/settings'}));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      await bridge.dispatchForTest(cmd('goBack'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('canPop reports whether there is anywhere to go back to', (
      tester,
    ) async {
      await tester.pumpWidget(appWith(key, navigator.observer));

      final atRoot = await bridge.dispatchForTest(cmd('canPop'));
      expect((atRoot.result as Map)['canPop'], isFalse);

      await bridge.dispatchForTest(cmd('navigate', {'route': '/settings'}));
      await tester.pumpAndSettle();

      final deeper = await bridge.dispatchForTest(cmd('canPop'));
      expect((deeper.result as Map)['canPop'], isTrue);
    });

    testWidgets('getFlowGraph reports the routes the observer saw', (
      tester,
    ) async {
      await tester.pumpWidget(appWith(key, navigator.observer));
      await bridge.dispatchForTest(cmd('navigate', {'route': '/settings'}));
      await tester.pumpAndSettle();

      final response = await bridge.dispatchForTest(cmd('getFlowGraph'));

      final routes = (response.result as Map)['routes'] as List;
      expect(routes.map((r) => (r as Map)['name']), contains('/settings'));
    });

    testWidgets('currentLocation follows the app', (tester) async {
      await tester.pumpWidget(appWith(key, navigator.observer));
      expect(navigator.currentLocation, '/');

      await navigator.goTo('/settings');
      await tester.pumpAndSettle();

      expect(navigator.currentLocation, '/settings');
      expect(navigator.canGoBack, isTrue);
    });
  });

  group('NavigatorStateBridgeNavigator without an attached key', () {
    test('says the key is not attached rather than doing nothing', () async {
      final navigator = NavigatorStateBridgeNavigator(
        GlobalKey<NavigatorState>(),
      );
      final bridge = SelfTestBridge(port: 0, navigator: navigator);

      final response = await bridge.dispatchForTest(
        cmd('navigate', {'route': '/settings'}),
      );

      expect(response.error, contains('not attached to a Navigator'));
      await bridge.stop();
    });
  });
}
