import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test/src/devtools/service_extensions.dart';

/// The DevTools panel calls three VM service extensions. Nothing registered
/// them, so the tab loaded and every button in it reported an error, and the
/// only way to find that out was to open DevTools against a running app.
/// These tests call the handlers the panel calls.
Map<String, dynamic> payloadOf(ServiceExtensionResponse response) {
  final result = jsonDecode(response.result as String) as Map<String, dynamic>;
  return jsonDecode(result['value'] as String) as Map<String, dynamic>;
}

void main() {
  final manager = SelfTestManager();

  Widget app({VoidCallback? onPressed}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: onPressed ?? () {},
            child: const Text('Send'),
          ),
          const TextField(key: ValueKey('note')),
        ],
      ),
    ),
  );

  tearDown(() {
    SelfTestManager.debugSimulateReleaseBuild = null;
    SelfTestManager.resetReleaseBuildOptIn();
    resetSelfTestServiceExtensions();
  });

  testWidgets('getNodes lists what is on screen, registered or not', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    final nodes =
        payloadOf(
              await handleGetNodes('ext.selfTest.getNodes', const {}),
            )['nodes']
            as List<dynamic>;

    final types = nodes
        .map((node) => (node as Map<String, dynamic>)['type'])
        .toSet();
    expect(types, contains('ElevatedButton'));
    expect(types, contains('TextField'));
    expect(
      nodes.any((node) => (node as Map<String, dynamic>)['text'] == 'Send'),
      isTrue,
    );
  });

  testWidgets('runCommand taps by locator, with a real pointer event', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(app(onPressed: () => taps++));

    final response = await handleRunCommand('ext.selfTest.runCommand', const {
      'command': 'tap',
      'by': 'text',
      'value': 'Send',
    });
    await tester.pump();

    expect(taps, 1);
    expect(payloadOf(response)['success'], isTrue);
  });

  testWidgets('runCommand still accepts the id the panel used to send', (
    tester,
  ) async {
    var taps = 0;
    manager.setTestMode(true);
    addTearDown(() => manager.setTestMode(false));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelfTestableWidget(
            id: 'send',
            onTap: () => taps++,
            child: const Text('Send'),
          ),
        ),
      ),
    );

    await handleRunCommand('ext.selfTest.runCommand', const {
      'command': 'tap',
      'id': 'send',
    });
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('runCommand types into a field', (tester) async {
    await tester.pumpWidget(app());

    await handleRunCommand('ext.selfTest.runCommand', const {
      'command': 'type',
      'by': 'key',
      'value': 'note',
      'text': 'hello',
    });
    await tester.pump();

    expect(manager.readText(const SelfTestLocator.key('note')), 'hello');
  });

  testWidgets('a widget that is not there comes back as a readable error', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    final response = await handleRunCommand('ext.selfTest.runCommand', const {
      'command': 'tap',
      'by': 'text',
      'value': 'Nowhere',
    });

    expect(response.isError(), isTrue);
    final error =
        jsonDecode(response.errorDetail as String) as Map<String, dynamic>;
    expect(error['error'], contains('No widget matches'));
  });

  test('an unknown command is refused by name', () async {
    final response = await handleRunCommand('ext.selfTest.runCommand', const {
      'command': 'teleport',
      'id': 'send',
    });

    expect(response.isError(), isTrue);
    expect(response.errorDetail, contains('teleport'));
  });

  test('a command with no target says which two things it takes', () async {
    final response = await handleRunCommand('ext.selfTest.runCommand', const {
      'command': 'tap',
    });

    expect(response.isError(), isTrue);
    expect(response.errorDetail, contains('locator'));
  });

  testWidgets('setMode switches self-test mode on', (tester) async {
    await tester.pumpWidget(app());
    addTearDown(() => manager.setSelfTestModeActive(false));

    await handleSetMode('ext.selfTest.setMode', const {'active': 'true'});

    expect(manager.isSelfTestModeActive, isTrue);
  });

  testWidgets('a release build registers nothing at all', (tester) async {
    SelfTestManager.debugSimulateReleaseBuild = true;
    await tester.pumpWidget(app());

    // The gate is in the registration, and every handler is behind the same
    // guard as the rest of the package, so the panel sees an empty app rather
    // than a way into a shipped one.
    registerSelfTestServiceExtensions();
    final nodes =
        payloadOf(
              await handleGetNodes('ext.selfTest.getNodes', const {}),
            )['nodes']
            as List<dynamic>;

    expect(nodes, isEmpty);
  });
}
