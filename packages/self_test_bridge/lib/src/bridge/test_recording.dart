part of '../bridge_service.dart';

/// Recording a session and generating test code.
extension _BridgeTestRecording on SelfTestBridge {
  /// The test recording commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _testRecordingCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case BridgeCommands.recordTestStart:
        final testName = params['testName'] as String;
        final description = params['description'] as String?;
        return _startTestRecording(testName, description: description);

      case BridgeCommands.recordTestStop:
        final format = params['format'] as String? ?? 'widget_test';
        return _stopTestRecording(format);

      case BridgeCommands.recordAddAssertion:
        final assertion = params['assertion'] as String;
        final expected = params['expected'];
        return _recordAssertion(_targetId(params), assertion, expected);

      case BridgeCommands.recordAddComment:
        final comment = params['comment'] as String;
        return _recordComment(comment);

      case BridgeCommands.getRecordedSteps:
        return _getRecordedSteps();

      case BridgeCommands.generateTestFromScenario:
        final scenario = params['scenario'] as Map<String, dynamic>;
        final format = params['format'] as String? ?? 'widget_test';
        return _generateTestFromScenario(scenario, format);

      // =====================================================================
      // PUSH NOTIFICATION MOCKING
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // WIDGET TEST GENERATION IMPLEMENTATIONS
  // ===========================================================================

  Map<String, dynamic> _startTestRecording(
    String testName, {
    String? description,
  }) {
    if (_isRecordingTest) {
      return {
        'error': 'A test recording is already in progress. Stop it first.',
      };
    }

    _currentTestId = 'test_${DateTime.now().millisecondsSinceEpoch}';
    _currentTestName = testName;
    _currentTestDescription = description;
    _recordedSteps.clear();
    _isRecordingTest = true;

    return {'recording': true, 'testId': _currentTestId};
  }

  Map<String, dynamic> _stopTestRecording(String format) {
    if (!_isRecordingTest) {
      return {'error': 'No test recording in progress'};
    }

    final testCode = _generateTestCode(format);
    final imports = _getTestImports(format);
    final interactionCount = _recordedSteps
        .where((s) => s.type == 'interaction')
        .length;
    final assertionCount = _recordedSteps
        .where((s) => s.type == 'assertion')
        .length;

    _isRecordingTest = false;
    _currentTestId = null;
    final testName = _currentTestName;
    _currentTestName = null;
    _currentTestDescription = null;

    return {
      'testCode': testCode,
      'imports': imports,
      'interactions': interactionCount,
      'assertions': assertionCount,
      'testName': testName,
    };
  }

  Map<String, dynamic> _recordAssertion(
    String widgetId,
    String assertion,
    dynamic expected,
  ) {
    if (!_isRecordingTest) {
      return {
        'error':
            'No test recording in progress. Start one with recordTestStart.',
      };
    }

    _recordedSteps.add(
      _RecordedStep(
        type: 'assertion',
        action: assertion,
        params: {'widgetId': widgetId, 'expected': expected},
        timestamp: DateTime.now(),
      ),
    );

    return {
      'added': true,
      'assertionIndex': _recordedSteps
          .where((s) => s.type == 'assertion')
          .length,
    };
  }

  Map<String, dynamic> _recordComment(String comment) {
    if (!_isRecordingTest) {
      return {
        'error':
            'No test recording in progress. Start one with recordTestStart.',
      };
    }

    _recordedSteps.add(
      _RecordedStep(
        type: 'comment',
        action: 'comment',
        params: {'comment': comment},
        timestamp: DateTime.now(),
        comment: comment,
      ),
    );

    return {'added': true};
  }

  Map<String, dynamic> _getRecordedSteps() {
    if (!_isRecordingTest) {
      return {'isRecording': false, 'steps': <Map<String, dynamic>>[]};
    }

    return {
      'isRecording': true,
      'testId': _currentTestId,
      'testName': _currentTestName,
      'steps': _recordedSteps.map((s) {
        return {
          'type': s.type,
          'action': s.action,
          'details': s.params,
          'timestamp': s.timestamp.millisecondsSinceEpoch,
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _generateTestFromScenario(
    Map<String, dynamic> scenario,
    String format,
  ) {
    final name = scenario['name'] as String? ?? 'test';
    final description = scenario['description'] as String?;
    final steps =
        (scenario['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final scenarioSteps = <_RecordedStep>[];
    for (final step in steps) {
      final action = step['action'] as String;
      final params = step['params'] as Map<String, dynamic>? ?? {};

      String type;
      if (action.startsWith('expect') || action == 'assertWidget') {
        type = 'assertion';
      } else {
        type = 'interaction';
      }

      scenarioSteps.add(
        _RecordedStep(
          type: type,
          action: action,
          params: params,
          timestamp: DateTime.now(),
        ),
      );
    }

    final testCode = _generateTestCodeFromSteps(
      scenarioSteps,
      name,
      description,
      format,
    );
    final imports = _getTestImports(format);

    return {'testCode': testCode, 'imports': imports};
  }

  void _recordInteractionStep(String action, Map<String, dynamic> params) {
    if (!_isRecordingTest) return;

    _recordedSteps.add(
      _RecordedStep(
        type: 'interaction',
        action: action,
        widgetId: params['widgetId'] as String?,
        params: Map<String, dynamic>.from(params),
        timestamp: DateTime.now(),
      ),
    );
  }

  List<String> _getTestImports(String format) {
    switch (format) {
      case 'integration_test':
        return [
          "import 'package:flutter_test/flutter_test.dart';",
          "import 'package:flutter/material.dart';",
          "import 'package:integration_test/integration_test.dart';",
        ];
      case 'patrol':
        return [
          "import 'package:patrol/patrol.dart';",
          "import 'package:flutter/material.dart';",
        ];
      case 'widget_test':
      default:
        return [
          "import 'package:flutter_test/flutter_test.dart';",
          "import 'package:flutter/material.dart';",
        ];
    }
  }

  String _generateTestCode(String format) {
    return _generateTestCodeFromSteps(
      _recordedSteps,
      _currentTestName ?? 'generated_test',
      _currentTestDescription,
      format,
    );
  }

  String _generateTestCodeFromSteps(
    List<_RecordedStep> steps,
    String testName,
    String? description,
    String format,
  ) {
    final buffer = StringBuffer();

    switch (format) {
      case 'integration_test':
        buffer.writeln("void main() {");
        buffer.writeln(
          "  IntegrationTestWidgetsFlutterBinding.ensureInitialized();",
        );
        buffer.writeln();
        buffer.writeln(
          "  testWidgets('$testName', (WidgetTester tester) async {",
        );
        break;
      case 'patrol':
        buffer.writeln("void main() {");
        buffer.writeln("  patrolTest('$testName', (\$) async {");
        break;
      case 'widget_test':
      default:
        buffer.writeln("void main() {");
        buffer.writeln(
          "  testWidgets('$testName', (WidgetTester tester) async {",
        );
    }

    if (description != null) {
      buffer.writeln("    // $description");
    }
    buffer.writeln("    // TODO: Replace MyApp() with your app widget");
    buffer.writeln("    await tester.pumpWidget(MyApp());");
    buffer.writeln("    await tester.pumpAndSettle();");
    buffer.writeln();

    for (final step in steps) {
      final code = _generateStepCode(step, format);
      if (code.isNotEmpty) {
        buffer.writeln(code);
      }
    }

    buffer.writeln("  });");
    buffer.writeln("}");

    return buffer.toString();
  }

  String _generateStepCode(_RecordedStep step, String format) {
    final params = step.params;
    final isPatrol = format == 'patrol';
    final tester = isPatrol ? '\$' : 'tester';

    switch (step.type) {
      case 'interaction':
        return _generateInteractionCode(step.action, params, tester, isPatrol);
      case 'assertion':
        return _generateAssertionCode(step.action, params);
      case 'comment':
        final comment = params['comment'] as String? ?? '';
        return "    // $comment";
      default:
        return "    // Unknown step type: ${step.type}";
    }
  }

  String _generateInteractionCode(
    String action,
    Map<String, dynamic> params,
    String tester,
    bool isPatrol,
  ) {
    final widgetId = params['widgetId'] as String?;

    switch (action) {
      case 'tap':
        if (widgetId != null) {
          return "    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // tap: missing widgetId";

      case 'type':
      case 'enterText':
        final text = params['text'] as String? ?? '';
        if (widgetId != null) {
          final escapedText = text.replaceAll("'", "\\'");
          return "    await $tester.enterText(find.byKey(Key('$widgetId')), '$escapedText');\n    await $tester.pumpAndSettle();";
        }
        return "    // type: missing widgetId";

      case 'clear':
        if (widgetId != null) {
          return "    await $tester.enterText(find.byKey(Key('$widgetId')), '');\n    await $tester.pumpAndSettle();";
        }
        return "    // clear: missing widgetId";

      case 'scroll':
        final direction = params['direction'] as String? ?? 'down';
        final delta = params['delta'] as num? ?? 300;
        final dx = direction == 'left'
            ? delta
            : (direction == 'right' ? -delta : 0);
        final dy = direction == 'up'
            ? delta
            : (direction == 'down' ? -delta : 0);
        if (widgetId != null) {
          return "    await $tester.drag(find.byKey(Key('$widgetId')), Offset($dx, $dy));\n    await $tester.pumpAndSettle();";
        }
        return "    await $tester.drag(find.byType(ListView), Offset($dx, $dy));\n    await $tester.pumpAndSettle();";

      case 'longPress':
        if (widgetId != null) {
          return "    await $tester.longPress(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // longPress: missing widgetId";

      case 'doubleTap':
        if (widgetId != null) {
          return "    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // doubleTap: missing widgetId";

      case 'navigate':
        final route = params['route'] as String? ?? '/';
        return "    // Navigate to: $route\n    // TODO: Implement navigation to '$route'";

      case 'goBack':
        return "    await $tester.pageBack();\n    await $tester.pumpAndSettle();";

      case 'toggle':
        if (widgetId != null) {
          return "    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // toggle: missing widgetId";

      case 'select':
        final value = params['value'] as String? ?? '';
        if (widgetId != null) {
          return "    // Select '$value' from dropdown\n    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();\n    await $tester.tap(find.text('$value').last);\n    await $tester.pumpAndSettle();";
        }
        return "    // select: missing widgetId";

      case 'wait':
        final condition = params['condition'] as String?;
        final duration = params['duration'] as int?;
        if (condition == 'duration' && duration != null) {
          return "    await $tester.pump(Duration(milliseconds: $duration));";
        }
        return "    await $tester.pumpAndSettle();";

      default:
        return "    // ${action}: ${params.entries.map((e) => '${e.key}=${e.value}').join(', ')}";
    }
  }

  String _generateAssertionCode(String assertion, Map<String, dynamic> params) {
    final widgetId = params['widgetId'] as String?;
    final expected = params['expected'];

    switch (assertion) {
      case 'toBeVisible':
        if (widgetId != null) {
          return "    expect(find.byKey(Key('$widgetId')), findsOneWidget);";
        }
        return "    // toBeVisible: missing widgetId";

      case 'toBeHidden':
        if (widgetId != null) {
          return "    expect(find.byKey(Key('$widgetId')), findsNothing);";
        }
        return "    // toBeHidden: missing widgetId";

      case 'toBeEnabled':
        if (widgetId != null) {
          return "    final widget = tester.widget(find.byKey(Key('$widgetId')));\n    expect((widget as dynamic).enabled, isTrue);";
        }
        return "    // toBeEnabled: missing widgetId";

      case 'toBeDisabled':
        if (widgetId != null) {
          return "    final widget = tester.widget(find.byKey(Key('$widgetId')));\n    expect((widget as dynamic).enabled, isFalse);";
        }
        return "    // toBeDisabled: missing widgetId";

      case 'toBeChecked':
        if (widgetId != null) {
          return "    final checkbox = tester.widget<Checkbox>(find.byKey(Key('$widgetId')));\n    expect(checkbox.value, isTrue);";
        }
        return "    // toBeChecked: missing widgetId";

      case 'toBeUnchecked':
        if (widgetId != null) {
          return "    final checkbox = tester.widget<Checkbox>(find.byKey(Key('$widgetId')));\n    expect(checkbox.value, isFalse);";
        }
        return "    // toBeUnchecked: missing widgetId";

      case 'toHaveText':
        if (expected != null) {
          final escapedText = expected.toString().replaceAll("'", "\\'");
          return "    expect(find.text('$escapedText'), findsOneWidget);";
        }
        return "    // toHaveText: missing expected value";

      case 'toContainText':
        if (expected != null) {
          final escapedText = expected.toString().replaceAll("'", "\\'");
          return "    expect(find.textContaining('$escapedText'), findsWidgets);";
        }
        return "    // toContainText: missing expected value";

      case 'toHaveValue':
        if (widgetId != null && expected != null) {
          return "    final textField = tester.widget<TextField>(find.byKey(Key('$widgetId')));\n    expect(textField.controller?.text, equals('$expected'));";
        }
        return "    // toHaveValue: missing widgetId or expected";

      case 'toBeFocused':
        if (widgetId != null) {
          return "    final focusNode = Focus.of(tester.element(find.byKey(Key('$widgetId'))));\n    expect(focusNode.hasFocus, isTrue);";
        }
        return "    // toBeFocused: missing widgetId";

      default:
        return "    // ${assertion}: ${params.entries.map((e) => '${e.key}=${e.value}').join(', ')}";
    }
  }
}
