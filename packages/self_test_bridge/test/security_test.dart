import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

/// The bridge is a remote control for the app: it reads the widget tree, taps,
/// types, and photographs the screen. Until this test existed it listened on
/// every network interface with no authentication at all, which meant anyone
/// on the same wifi could drive a colleague's debug build.
void main() {
  late SelfTestBridge bridge;

  setUp(() {
    // Port 0 lets the operating system pick a free one, so two runs on the
    // same machine do not fight over 9999.
    bridge = SelfTestBridge(port: 0);
  });

  tearDown(() async {
    await bridge.stop();
    SelfTestManager.debugSimulateReleaseBuild = null;
    SelfTestManager.resetReleaseBuildOptIn();
  });

  Future<WebSocket> connect(String query) =>
      WebSocket.connect('ws://127.0.0.1:${bridge.boundPort}$query');

  group('the listening socket', () {
    test('binds to loopback, not to every interface', () async {
      expect(bridge.host, InternetAddress.loopbackIPv4);
      expect(bridge.host.isLoopback, isTrue);

      await bridge.start();

      expect(bridge.isRunning, isTrue);
      expect(bridge.boundPort, isNot(0));
    });

    test('takes a wider address only when asked', () {
      final open = SelfTestBridge(port: 0, host: InternetAddress.anyIPv4);
      expect(open.host.isLoopback, isFalse);
    });
  });

  group('the token', () {
    test('is generated per bridge and is not guessable by being empty', () {
      final first = SelfTestBridge(port: 0);
      final second = SelfTestBridge(port: 0);

      expect(first.token, hasLength(32));
      expect(first.token, isNot(second.token));
      expect(first.url, contains('token=${first.token}'));
    });

    test('a connection with no token is refused', () async {
      await bridge.start();

      await expectLater(connect(''), throwsA(isA<WebSocketException>()));
    });

    test('a connection with the wrong token is refused', () async {
      await bridge.start();

      await expectLater(
        connect('?token=${'0' * 32}'),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('a token of the right length but wrong value is refused', () async {
      await bridge.start();
      final nearMiss =
          bridge.token.substring(0, 31) +
          (bridge.token.endsWith('a') ? 'b' : 'a');

      await expectLater(
        connect('?token=$nearMiss'),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('the right token connects', () async {
      await bridge.start();

      final socket = await connect('?token=${bridge.token}');
      addTearDown(socket.close);

      expect(socket.readyState, WebSocket.open);
    });

    test('a supplied token is used as given', () async {
      final named = SelfTestBridge(port: 0, token: 'a-token-the-app-chose');
      addTearDown(named.stop);
      await named.start();

      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${named.boundPort}?token=a-token-the-app-chose',
      );
      addTearDown(socket.close);

      expect(socket.readyState, WebSocket.open);
    });
  });

  group('release builds', () {
    test('refuses to start', () async {
      SelfTestManager.debugSimulateReleaseBuild = true;

      await expectLater(
        bridge.start(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('refuses to start'),
          ),
        ),
      );
      expect(bridge.isRunning, isFalse);
    });

    test('starts when the app opts in deliberately', () async {
      SelfTestManager.debugSimulateReleaseBuild = true;
      final opted = SelfTestBridge(port: 0, allowInReleaseBuilds: true);
      addTearDown(opted.stop);

      await opted.start();

      expect(opted.isRunning, isTrue);
    });
  });
}
