/// The VM service extensions the DevTools panel talks to.
///
/// The panel has always called `ext.selfTest.getNodes`, `ext.selfTest.setMode`
/// and `ext.selfTest.runCommand`. Nothing registered them, so the tab loaded
/// and every button in it reported an error. These are those three.
///
/// This is also a second way into the app that needs no WebSocket and no port:
/// anything that speaks to the VM service, which includes DevTools and
/// `dart:vm_service` clients, can drive the app through them. The release
/// guard covers them for the same reason it covers everything else.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../core/manager.dart';
import '../locator/locator.dart';

bool _registered = false;

/// Registers the extensions, once.
///
/// Called by `SelfTestRoot`. Safe to call again: `registerExtension` throws on
/// a duplicate name, and a hot restart re-runs everything.
void registerSelfTestServiceExtensions() {
  if (_registered) return;
  if (!SelfTestManager.isEnabled) return;
  _registered = true;

  developer.registerExtension('ext.selfTest.getNodes', handleGetNodes);
  developer.registerExtension('ext.selfTest.setMode', handleSetMode);
  developer.registerExtension('ext.selfTest.runCommand', handleRunCommand);
}

/// Undoes [registerSelfTestServiceExtensions] as far as it can.
///
/// The VM keeps the registration; this only lets a test register again in a
/// fresh isolate.
@visibleForTesting
void resetSelfTestServiceExtensions() {
  _registered = false;
}

/// Everything on screen, whether or not the app registered it.
///
/// The panel used to be able to list only widgets wrapped in
/// `SelfTestableWidget`, which on most apps is nothing at all.
@visibleForTesting
Future<developer.ServiceExtensionResponse> handleGetNodes(
  String method,
  Map<String, String> parameters,
) async {
  final manager = SelfTestManager();
  final nodes = manager
      .describeScreen()
      .map((snapshot) => snapshot.toJson())
      .toList();
  return _ok(method, {'nodes': nodes});
}

/// Turns self-test mode on or off from the panel.
@visibleForTesting
Future<developer.ServiceExtensionResponse> handleSetMode(
  String method,
  Map<String, String> parameters,
) async {
  final active = parameters['active'] == 'true';
  SelfTestManager()
    ..setSelfTestModeActive(active)
    ..restartWidgetTree();
  return _ok(method, {'active': active});
}

/// Runs one action against one widget.
///
/// The widget is named either by `id`, which is what the panel has always
/// sent, or by a locator: `by` plus `value`, and optionally `exact` and
/// `index`. The locator form is the one that works on a widget the app never
/// registered.
@visibleForTesting
Future<developer.ServiceExtensionResponse> handleRunCommand(
  String method,
  Map<String, String> parameters,
) async {
  final manager = SelfTestManager();
  final command = parameters['command'];
  if (command == null) {
    return _error(method, 'Missing "command".');
  }

  final SelfTestLocator locator;
  try {
    locator = _locatorFrom(parameters);
  } on ArgumentError catch (error) {
    return _error(method, error.message.toString());
  }

  try {
    switch (command) {
      case 'tap':
      case 'trigger':
        await manager.tap(locator);
      case 'doubleTap':
        await manager.doubleTap(locator);
      case 'longPress':
        await manager.longPress(locator);
      case 'type':
      case 'enterText':
        await manager.typeInto(locator, parameters['text'] ?? '');
      case 'submit':
        await manager.submit(locator);
      case 'readText':
        return _ok(method, {'text': manager.readText(locator)});
      case 'exists':
        return _ok(method, {'result': manager.exists(locator)});
      default:
        return _error(method, 'Unknown command "$command".');
    }
  } catch (error) {
    // The panel is a UI on the other side of a socket. An exception that
    // crosses it as a protocol error tells the user nothing, so the message
    // is carried instead.
    return _error(method, error.toString());
  }

  return _ok(method, {'success': true});
}

SelfTestLocator _locatorFrom(Map<String, String> parameters) {
  final by = parameters['by'];
  if (by == null) {
    final id = parameters['id'];
    if (id == null) {
      throw ArgumentError('Give either "id" or a locator ("by" and "value").');
    }
    return SelfTestLocator.id(id);
  }
  return SelfTestLocator.fromJson({
    'by': by,
    'value': parameters['value'] ?? '',
    if (parameters['exact'] != null) 'exact': parameters['exact'] == 'true',
    if (parameters['index'] != null)
      'index': int.tryParse(parameters['index']!) ?? 0,
  });
}

/// The panel reads `response.json['value']` and decodes it, so the payload
/// travels as a JSON string inside the result map.
developer.ServiceExtensionResponse _ok(
  String method,
  Map<String, dynamic> payload,
) {
  return developer.ServiceExtensionResponse.result(
    jsonEncode({
      'type': '_extensionType',
      'method': method,
      'value': jsonEncode(payload),
    }),
  );
}

developer.ServiceExtensionResponse _error(String method, String message) {
  return developer.ServiceExtensionResponse.error(
    developer.ServiceExtensionResponse.extensionError,
    jsonEncode({'method': method, 'error': message}),
  );
}
