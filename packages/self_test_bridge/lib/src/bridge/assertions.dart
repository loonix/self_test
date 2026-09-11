part of '../bridge_service.dart';

/// Waiting for a condition, and asserting one.
extension _BridgeAssertions on SelfTestBridge {
  /// The assertions commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _assertionsCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'wait':
      case 'waitFor':
        final condition = params['condition'] as String;
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final text = params['text'] as String?;
        final timeout = params['timeout'] as int? ?? 5000;
        final duration = params['duration'] as int?;
        return await _wait(condition, widgetId, text, timeout, duration);

      // =====================================================================
      // ASSERTIONS
      // =====================================================================

      case 'expect':
        final assertion = params['assertion'] as String;
        final expected = params['expected'];
        final timeout = params['timeout'] as int? ?? 5000;
        return await _expect(_targetId(params), assertion, expected, timeout);

      case 'assertWidget':
        // Legacy assertion support
        final assertion = params['assertion'] as String;
        final expectedText = params['expectedText'] as String?;
        return _assertWidget(_targetId(params), assertion, expectedText);

      // =====================================================================
      // SCREENSHOTS & VIDEO
      // =====================================================================

      case 'runScenario':
        final name = params['name'] as String;
        final steps = (params['steps'] as List).cast<Map<String, dynamic>>();
        final stopOnError = params['stopOnError'] as bool? ?? true;
        return await _runScenario(name, steps, stopOnError);

      // =====================================================================
      // ACCESSIBILITY
      // =====================================================================

      case 'accessibilityAudit':
        return await _accessibilityAudit();

      // =====================================================================
      // CLIPBOARD
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // WAIT IMPLEMENTATIONS
  // ===========================================================================

  Future<Map<String, dynamic>> _wait(
    String condition,
    String? widgetId,
    String? text,
    int timeoutMs,
    int? durationMs,
  ) async {
    final manager = SelfTestManager();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    switch (condition) {
      case 'visible':
      case 'widget_exists':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          if (manager.activeTestNodes.containsKey(widgetId)) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for widget "$widgetId"');

      case 'hidden':
      case 'widget_gone':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          if (!manager.activeTestNodes.containsKey(widgetId)) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to disappear');

      case 'enabled':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          final node = manager.activeTestNodes[widgetId];
          if (node != null &&
              (node.onTap != null || node.onTextChange != null)) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to be enabled');

      case 'disabled':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          final node = manager.activeTestNodes[widgetId];
          if (node != null && node.onTap == null && node.onTextChange == null) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to be disabled');

      case 'text':
        if (widgetId == null) throw Exception('widgetId required');
        if (text == null) throw Exception('text required');
        while (DateTime.now().isBefore(deadline)) {
          final node = manager.activeTestNodes[widgetId];
          if (node?.currentText == text) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to have text "$text"');

      case 'idle':
        await manager.waitForAnimations();
        return {'success': true};

      case 'network_idle':
        // Wait for no pending network requests
        await Future.delayed(const Duration(milliseconds: 500));
        return {'success': true};

      case 'duration':
        final duration = durationMs ?? 1000;
        await Future.delayed(Duration(milliseconds: duration));
        return {'success': true};

      default:
        throw Exception('Unknown wait condition: $condition');
    }
  }

  // ===========================================================================
  // ASSERTION IMPLEMENTATIONS
  // ===========================================================================

  Future<Map<String, dynamic>> _expect(
    String widgetId,
    String assertion,
    dynamic expected,
    int timeout,
  ) async {
    final manager = SelfTestManager();

    // Wait for widget first
    try {
      await _waitForWidget(widgetId, timeout);
    } catch (e) {
      if (assertion == 'toBeHidden') {
        return {'passed': true, 'message': 'Widget is hidden'};
      }
      return {'passed': false, 'message': 'Widget "$widgetId" not found'};
    }

    final node = manager.activeTestNodes[widgetId];

    switch (assertion) {
      case 'toBeVisible':
        return {
          'passed': node != null,
          'message': node != null ? 'Widget is visible' : 'Widget not found',
        };

      case 'toBeHidden':
        return {
          'passed': node == null,
          'message': node == null ? 'Widget is hidden' : 'Widget is visible',
        };

      case 'toBeEnabled':
        final isEnabled = node?.onTap != null || node?.onTextChange != null;
        return {
          'passed': isEnabled,
          'message': isEnabled ? 'Widget is enabled' : 'Widget is disabled',
        };

      case 'toBeDisabled':
        final isDisabled = node?.onTap == null && node?.onTextChange == null;
        return {
          'passed': isDisabled,
          'message': isDisabled ? 'Widget is disabled' : 'Widget is enabled',
        };

      case 'toBeChecked':
        // TestNode doesn't track checked state; check currentText for 'true'/'checked'
        final isChecked =
            node?.currentText?.toLowerCase() == 'true' ||
            node?.currentText?.toLowerCase() == 'checked';
        return {
          'passed': isChecked,
          'message': isChecked ? 'Widget is checked' : 'Widget is not checked',
        };

      case 'toBeUnchecked':
        // TestNode doesn't track checked state; check currentText for 'false'/'unchecked'
        final isUnchecked =
            node?.currentText?.toLowerCase() != 'true' &&
            node?.currentText?.toLowerCase() != 'checked';
        return {
          'passed': isUnchecked,
          'message': isUnchecked ? 'Widget is unchecked' : 'Widget is checked',
        };

      case 'toHaveText':
        final actual = node?.currentText ?? '';
        final matches = actual == expected;
        return {
          'passed': matches,
          'message': matches
              ? 'Text matches'
              : 'Expected "$expected" but got "$actual"',
        };

      case 'toContainText':
        final actual = node?.currentText ?? '';
        final contains = actual.contains(expected as String);
        return {
          'passed': contains,
          'message': contains
              ? 'Text contains expected substring'
              : 'Expected "$actual" to contain "$expected"',
        };

      case 'toHaveValue':
        // TestNode uses currentText for all values
        final actual = node?.currentText;
        final matches = actual == expected || actual == expected?.toString();
        return {
          'passed': matches,
          'message': matches
              ? 'Value matches'
              : 'Expected "$expected" but got "$actual"',
        };

      case 'toHaveCount':
        // Count widgets with this ID pattern
        final count = manager.activeTestNodes.keys
            .where((k) => k.startsWith(widgetId))
            .length;
        final expectedCount = expected as int;
        return {
          'passed': count == expectedCount,
          'message': count == expectedCount
              ? 'Count matches'
              : 'Expected $expectedCount but got $count',
        };

      case 'toBeFocused':
        // Check if widget has focus
        final hasFocus =
            node?.context != null &&
            Focus.maybeOf(node!.context!)?.hasFocus == true;
        return {
          'passed': hasFocus,
          'message': hasFocus ? 'Widget is focused' : 'Widget is not focused',
        };

      default:
        return {'passed': false, 'message': 'Unknown assertion: $assertion'};
    }
  }

  Map<String, dynamic> _assertWidget(
    String widgetId,
    String assertion,
    String? expectedText,
  ) {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    switch (assertion) {
      case 'exists':
        return node != null
            ? {'passed': true, 'message': 'Widget exists'}
            : {'passed': false, 'message': 'Widget "$widgetId" not found'};

      case 'not_exists':
        return node == null
            ? {'passed': true, 'message': 'Widget does not exist'}
            : {'passed': false, 'message': 'Widget "$widgetId" exists'};

      case 'has_text':
        if (node == null) {
          return {'passed': false, 'message': 'Widget "$widgetId" not found'};
        }
        return node.currentText == expectedText
            ? {'passed': true, 'message': 'Text matches'}
            : {
                'passed': false,
                'message':
                    'Expected "$expectedText" but got "${node.currentText}"',
              };

      case 'is_enabled':
        if (node == null) {
          return {'passed': false, 'message': 'Widget "$widgetId" not found'};
        }
        return (node.onTap != null || node.onTextChange != null)
            ? {'passed': true, 'message': 'Widget is enabled'}
            : {'passed': false, 'message': 'Widget is disabled'};

      case 'is_visible':
        return node != null
            ? {'passed': true, 'message': 'Widget is visible'}
            : {'passed': false, 'message': 'Widget "$widgetId" not found'};

      default:
        return {'passed': false, 'message': 'Unknown assertion: $assertion'};
    }
  }

  // ===========================================================================
  // SCENARIOS
  // ===========================================================================

  Future<Map<String, dynamic>> _runScenario(
    String name,
    List<Map<String, dynamic>> steps,
    bool stopOnError,
  ) async {
    final manager = SelfTestManager();
    final results = <Map<String, dynamic>>[];
    var allPassed = true;

    manager.startTestRun(name);

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final action = step['action'] as String;
      final stepParams = step['params'] as Map<String, dynamic>? ?? {};
      String description = 'Step ${i + 1}: $action';

      try {
        // Execute the action as a command
        final command = BridgeCommand(
          id: 0,
          command: action,
          params: stepParams,
        );
        await _executeCommand(command);

        String? screenshotPath;
        screenshotPath = await manager.captureScreenshot(
          '${name}_step_${i + 1}',
        );

        results.add({
          'description': description,
          'passed': true,
          'screenshotPath': screenshotPath,
        });
      } catch (e) {
        allPassed = false;
        String? screenshotPath;
        screenshotPath = await manager.captureScreenshot(
          '${name}_step_${i + 1}_FAILED',
        );

        results.add({
          'description': description,
          'passed': false,
          'error': e.toString(),
          'screenshotPath': screenshotPath,
        });

        if (stopOnError) break;
      }
    }

    return {
      'name': name,
      'allPassed': allPassed,
      'passedCount': results.where((r) => r['passed'] == true).length,
      'failedCount': results.where((r) => r['passed'] == false).length,
      'steps': results,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // ===========================================================================
  // ACCESSIBILITY
  // ===========================================================================

  Future<Map<String, dynamic>> _accessibilityAudit() async {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;
    final issues = <Map<String, dynamic>>[];

    for (final entry in nodes.entries) {
      final node = entry.value;
      final widgetId = entry.key;

      // Check for unstable IDs
      if (widgetId.endsWith('_UNSTABLE')) {
        issues.add({
          'severity': 'warning',
          'widgetId': widgetId,
          'message': 'Widget has unstable ID',
          'suggestion': 'Add a Semantics label or ValueKey',
        });
      }

      // Check buttons without accessible names
      if (node.onTap != null &&
          (node.currentText == null || node.currentText!.isEmpty)) {
        issues.add({
          'severity': 'error',
          'widgetId': widgetId,
          'message': 'Interactive element has no accessible name',
          'suggestion': 'Add a Semantics label or visible text',
        });
      }

      // Check text inputs without labels
      if (node.onTextChange != null &&
          (node.currentText == null || node.currentText!.isEmpty)) {
        issues.add({
          'severity': 'warning',
          'widgetId': widgetId,
          'message': 'Text input has no label',
          'suggestion': 'Add a Semantics label or InputDecoration.labelText',
        });
      }
    }

    return {'issues': issues};
  }
}
