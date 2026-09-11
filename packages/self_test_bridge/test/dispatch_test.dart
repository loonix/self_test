import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

/// One harmless command from every group the dispatcher walks.
///
/// The command switch used to be one 866-line block. It is now fifteen group
/// dispatchers chained together, and the way that breaks is silently: a group
/// left out of the chain makes every command it owns answer "Unknown command"
/// while everything else still works. This is the test that would catch it.
const groupProbes = <String, Map<String, dynamic>>{
  'discovery': {'command': 'describeScreen'},
  'actions': {'command': 'tap'},
  'navigation': {'command': 'canPop'},
  'assertions': {'command': 'assertWidget'},
  // Deliberately not listGoldens (it reads a real directory, and real
  // dart:io inside testWidgets never completes, so the probe hangs) and not
  // recordStart (it arms a periodic timer the test then fails for leaking).
  // recordStop touches neither, and no other group claims it.
  'goldens': {'command': 'recordStop'},
  'network': {'command': 'networkLog'},
  'storage': {
    'command': 'filePicker',
    'params': {'files': <String>[]},
  },
  'device': {
    'command': 'resize',
    'params': {'width': 100, 'height': 100},
  },
  'mocks': {'command': 'channelLog'},
  'profiling': {'command': 'frameProfilingStop'},
  'memory': {'command': 'imageCacheStats'},
  'state': {'command': 'listStateProviders'},
  'time travel': {'command': 'timeTravelList'},
  'accessibility': {'command': 'semanticsCoverage'},
  'test recording': {'command': 'getRecordedSteps'},
};

void main() {
  late SelfTestBridge bridge;

  setUp(() => bridge = SelfTestBridge(port: 0));
  tearDown(() => bridge.stop());

  group('every command group is wired into the dispatcher', () {
    groupProbes.forEach((name, probe) {
      testWidgets('the $name group answers its own commands', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Hello'))),
        );

        final response = await bridge.dispatchForTest(
          BridgeCommand(
            id: 1,
            command: probe['command'] as String,
            params: (probe['params'] as Map<String, dynamic>?) ?? const {},
          ),
        );

        // Some of these fail for their own reasons with no arguments, which is
        // fine. What must not happen is the dispatcher walking past the group
        // that owns them.
        expect(
          response.error ?? '',
          isNot(contains('Unknown command')),
          reason: 'the $name group is missing from the dispatcher chain',
        );
      });
    });
  });

  testWidgets('an unknown command is still reported as unknown', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Hello'))),
    );

    final response = await bridge.dispatchForTest(
      BridgeCommand(id: 1, command: 'notACommand', params: const {}),
    );

    expect(response.error, contains('Unknown command: notACommand'));
  });

  testWidgets('the widget id path still works alongside locators', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Hello'))),
    );

    // No widget was ever registered under this id, so the legacy path should
    // say so rather than silently doing nothing.
    //
    // Through runAsync because the id path polls with a real
    // `Future.delayed` against a real `DateTime.now()` deadline. Under the
    // fake clock testWidgets installs, that delay never fires and the
    // deadline never passes, so the command would wait forever.
    final response = await tester.runAsync(
      () => bridge.dispatchForTest(
        BridgeCommand(
          id: 1,
          command: 'tap',
          params: const {'widgetId': 'never_registered', 'timeout': 50},
        ),
      ),
    );

    expect(response!.error, contains('never_registered'));
  });
}
