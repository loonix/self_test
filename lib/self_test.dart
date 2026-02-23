library self_test;

export 'annotations.dart';

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Represents a testable node in the widget tree.
class TestNode {
  final String id;
  final VoidCallback? onTap;
  final ValueSetter<String>? onTextChange;
  final BuildContext? context;
  String? currentText; // For text assertions

  TestNode({
    required this.id,
    this.onTap,
    this.onTextChange,
    this.context,
    this.currentText,
  });
}

/// Singleton manager for self-testing functionality.
class SelfTestManager {
  static final SelfTestManager _instance = SelfTestManager._internal();
  factory SelfTestManager() => _instance;
  SelfTestManager._internal();

  final Map<String, TestNode> _activeTestNodes = {};
  bool _isSelfTestModeActive = false;
  bool _isTestMode = false; // For testing environments
  GlobalKey<State>? rootKey;
  int _rebuildCounter = 0; // Counter to force rebuilds

  /// Gets the current self-test mode status.
  bool get isSelfTestModeActive => _isSelfTestModeActive;

  /// Sets the self-test mode status.
  void setSelfTestModeActive(bool value) {
    _isSelfTestModeActive = value;
  }

  /// Gets the test mode status (for testing environments).
  bool get isTestMode => _isTestMode;

  /// Sets the test mode status.
  void setTestMode(bool value) {
    _isTestMode = value;
  }

  /// Gets the rebuild counter for forcing widget tree rebuilds.
  int get rebuildCounter => _rebuildCounter;

  /// Restarts the widget tree by setting state on the root key.
  void restartWidgetTree() {
    _rebuildCounter++;
    debugPrint('[SelfTest] Restarting widget tree (rebuild counter: $_rebuildCounter, rootKey: $rootKey)');
    if (rootKey?.currentState != null) {
      debugPrint('[SelfTest] Calling setState on root key');
      (rootKey!.currentState as dynamic).setState(() {});
    } else {
      debugPrint('[SelfTest] WARNING: rootKey is null or currentState is null (rootKey: $rootKey)');
      // Try to find and set the root key if it exists
      if (rootKey == null) {
        debugPrint('[SelfTest] Attempting to set root key');
        rootKey = GlobalKey<State>(debugLabel: 'SelfTestRoot');
      }
    }
  }

  /// Gets the active test nodes (for testing purposes).
  Map<String, TestNode> get activeTestNodes => _activeTestNodes;

  /// Registers a test node.
  void registerTestNode(TestNode node) {
    _activeTestNodes[node.id] = node;
    debugPrint('[SelfTest] Registered TestNode: "${node.id}" (tap: ${node.onTap != null}, text: ${node.onTextChange != null})');
  }

  /// Unregisters a test node.
  void unregisterTestNode(String id) {
    _activeTestNodes.remove(id);
    debugPrint('[SelfTest] Unregistered TestNode: "$id"');
  }

  /// Triggers the tap action for the given id.
  void trigger(String id) {
    debugPrint('[SelfTest] Looking for TestNode: "$id" to trigger tap');
    debugPrint('[SelfTest] Active nodes: ${_activeTestNodes.keys.toList()}');
    final node = _activeTestNodes[id];
    if (node != null && node.onTap != null) {
      debugPrint('[SelfTest] Found TestNode "$id", triggering tap');
      node.onTap!();
    } else {
      debugPrint('[SelfTest] ERROR: TestNode "$id" not found or has no tap callback');
      throw Exception('TestNode with id "$id" not found or has no tap callback.');
    }
  }

  /// Enters text for the given id.
  void enterText(String id, String text) {
    debugPrint('[SelfTest] Looking for TestNode: "$id" to enter text: "$text"');
    debugPrint('[SelfTest] Active nodes: ${_activeTestNodes.keys.toList()}');
    final node = _activeTestNodes[id];
    if (node != null && node.onTextChange != null) {
      debugPrint('[SelfTest] Found TestNode "$id", entering text');
      node.onTextChange!(text);
      node.currentText = text; // Update current text for assertions
    } else {
      debugPrint('[SelfTest] ERROR: TestNode "$id" not found or has no text change callback');
      throw Exception('TestNode with id "$id" not found or has no text change callback.');
    }
  }

  /// Waits for animations to complete (simulates pumpAndSettle).
  Future<void> waitForAnimations() async {
    // Simple delay; in real implementation, might need more sophisticated logic
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Captures a screenshot (stub implementation).
  Future<String?> captureScreenshot([String? name]) async {
    // Stub - in real implementation would capture actual screenshot
    return null;
  }

  /// Sets the screenshot directory.
  Future<void> setScreenshotDirectory(String? path) async {
    // Stub implementation
  }

  /// Starts a test run.
  void startTestRun(String name) {
    // Stub implementation
  }
}

/// A wrapper widget that makes a child widget testable in self-test mode.
class SelfTestableWidget extends StatefulWidget {
  final String id;
  final Widget child;
  final VoidCallback? onTap;
  final ValueSetter<String>? onTextChange;

  const SelfTestableWidget({
    super.key,
    required this.id,
    required this.child,
    this.onTap,
    this.onTextChange,
  });

  @override
  State<SelfTestableWidget> createState() => _SelfTestableWidgetState();
}

class _SelfTestableWidgetState extends State<SelfTestableWidget> {
  bool _wasRegistered = false;

  @override
  void initState() {
    super.initState();
    _updateRegistration();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint('[SelfTest] SelfTestableWidget "${widget.id}" didChangeDependencies called');
    _updateRegistration();
  }

  @override
  void didUpdateWidget(SelfTestableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      // ID changed, need to unregister old and register new
      _unregisterIfNeeded();
      _updateRegistration();
    }
  }

  void _updateRegistration() {
    final manager = SelfTestManager();
    final shouldBeRegistered = ((kDebugMode || kProfileMode) && manager.isSelfTestModeActive) || manager.isTestMode;

    if (shouldBeRegistered && !_wasRegistered) {
      debugPrint('[SelfTest] SelfTestableWidget "${widget.id}" registering (mode active: ${manager.isSelfTestModeActive}, test mode: ${manager.isTestMode})');
      final node = TestNode(
        id: widget.id,
        onTap: widget.onTap,
        onTextChange: widget.onTextChange,
        context: context,
      );
      manager.registerTestNode(node);
      _wasRegistered = true;
    } else if (!shouldBeRegistered && _wasRegistered) {
      debugPrint('[SelfTest] SelfTestableWidget "${widget.id}" unregistering due to mode change');
      manager.unregisterTestNode(widget.id);
      _wasRegistered = false;
    }
  }

  void _unregisterIfNeeded() {
    if (_wasRegistered) {
      debugPrint('[SelfTest] SelfTestableWidget "${widget.id}" unregistering');
      SelfTestManager().unregisterTestNode(widget.id);
      _wasRegistered = false;
    }
  }

  @override
  void dispose() {
    _unregisterIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A wrapper widget for the root of the app to enable programmatic restart.
class SelfTestRoot extends StatefulWidget {
  final Widget child;

  SelfTestRoot({Key? key, required this.child}) : super(key: key ?? (SelfTestManager().rootKey ?? GlobalKey<State>(debugLabel: 'SelfTestRoot'))) {
    // Ensure the manager has a root key
    SelfTestManager().rootKey ??= GlobalKey<State>(debugLabel: 'SelfTestRoot');
  }

  @override
  State<SelfTestRoot> createState() => _SelfTestRootState();
}

class _SelfTestRootState extends State<SelfTestRoot> {
  @override
  void initState() {
    super.initState();
    debugPrint('[SelfTest] SelfTestRoot initState called');
    debugPrint('[SelfTest] SelfTestRoot key: ${widget.key}, manager rootKey: ${SelfTestManager().rootKey}');
    // Ensure the manager's rootKey points to this state
    SelfTestManager().rootKey = widget.key as GlobalKey<State>?;
  }

  @override
  Widget build(BuildContext context) {
    // Force rebuild when self-test mode changes or restart is called
    final manager = SelfTestManager();
    debugPrint('[SelfTest] SelfTestRoot building with key: ${manager.isSelfTestModeActive}_${manager.isTestMode}_${manager.rebuildCounter}');
    return KeyedSubtree(
      key: ValueKey('${manager.isSelfTestModeActive}_${manager.isTestMode}_${manager.rebuildCounter}'),
      child: widget.child,
    );
  }
}

/// Screenshot boundary widget for capturing screenshots during tests.
class ScreenshotBoundary extends StatelessWidget {
  final Widget child;
  
  const ScreenshotBoundary({super.key, required this.child});
  
  @override
  Widget build(BuildContext context) => child;
}

/// Widget catalog for discovering widgets in the app.
class WidgetCatalog {
  static Map<String, dynamic> exportCatalog() => {};
  static Map<String, dynamic> exportByScreen() => {};
}

/// Flow discovery for navigation analysis.
class FlowDiscovery {
  static Map<String, dynamic> exportMetadata(dynamic router) => {};
}

/// A test scenario definition.
class TestScenario {
  final String name;
  final String? description;
  final List<TestStep> steps;

  const TestScenario({
    required this.name,
    this.description,
    required this.steps,
  });

  factory TestScenario.fromJson(Map<String, dynamic> json) {
    return TestScenario(
      name: json['name'] as String,
      description: json['description'] as String?,
      steps: (json['steps'] as List<dynamic>)
          .map((e) => TestStep.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Runs the test scenario.
  Future<TestScenarioResult> run() async {
    final results = <StepResult>[];
    int passedSteps = 0;

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final stopwatch = Stopwatch()..start();
      // Use actionType for built-in steps, or description for custom actions
      final actionName = step.actionType ?? step.description ?? 'custom';
      try {
        await _executeStep(step);
        stopwatch.stop();
        results.add(StepResult(
          index: i,
          action: actionName,
          success: true,
          duration: stopwatch.elapsed,
        ));
        passedSteps++;
      } catch (e) {
        stopwatch.stop();
        results.add(StepResult(
          index: i,
          action: actionName,
          success: false,
          error: e.toString(),
          duration: stopwatch.elapsed,
        ));
        return TestScenarioResult(
          success: false,
          passedSteps: passedSteps,
          totalSteps: steps.length,
          error: e.toString(),
          failedAtStep: i,
          stepResults: results,
        );
      }
    }

    return TestScenarioResult(
      success: true,
      passedSteps: passedSteps,
      totalSteps: steps.length,
      stepResults: results,
    );
  }

  Future<void> _executeStep(TestStep step) async {
    final manager = SelfTestManager();

    // Handle custom action callback first
    if (step.action != null) {
      await step.action!();
      if (step.captureScreenshot) {
        await manager.captureScreenshot(step.description);
      }
      await manager.waitForAnimations();
      return;
    }

    // Handle built-in action types
    switch (step.actionType) {
      case 'tap':
        manager.trigger(step.params['widgetId'] as String);
        break;
      case 'enterText':
        manager.enterText(
          step.params['widgetId'] as String,
          step.params['text'] as String,
        );
        break;
      case 'wait':
        await Future.delayed(Duration(
          milliseconds: (step.params['milliseconds'] as int?) ?? 100,
        ));
        break;
      case 'screenshot':
        await manager.captureScreenshot(step.params['name'] as String?);
        break;
      default:
        throw Exception('Unknown action type: ${step.actionType}');
    }
    await manager.waitForAnimations();
  }
}

/// A single test step in a scenario.
class TestStep {
  /// Action type for built-in actions ('tap', 'enterText', 'wait', 'screenshot')
  final String? actionType;
  final Map<String, dynamic> params;
  final String? description;
  /// Custom action callback for complex steps
  final Future<void> Function()? action;
  final bool captureScreenshot;

  const TestStep({
    this.actionType,
    this.params = const {},
    this.description,
    this.action,
    this.captureScreenshot = false,
  });

  factory TestStep.fromJson(Map<String, dynamic> json) {
    return TestStep(
      actionType: json['action'] as String,
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      description: json['description'] as String?,
    );
  }

  /// Factory constructor for screenshot step
  factory TestStep.screenshot(String name) {
    return TestStep(
      actionType: 'screenshot',
      params: {'name': name},
      description: 'Capture screenshot: $name',
    );
  }

  /// Factory constructor for wait step
  factory TestStep.wait(Duration duration, {String? description}) {
    return TestStep(
      actionType: 'wait',
      params: {'milliseconds': duration.inMilliseconds},
      description: description ?? 'Wait for ${duration.inMilliseconds}ms',
    );
  }

  /// Factory constructor for enterText step
  factory TestStep.enterText(String widgetId, String text, {String? description}) {
    return TestStep(
      actionType: 'enterText',
      params: {'widgetId': widgetId, 'text': text},
      description: description ?? 'Enter text in $widgetId',
    );
  }

  /// Factory constructor for tap step
  factory TestStep.tap(String widgetId, {String? description}) {
    return TestStep(
      actionType: 'tap',
      params: {'widgetId': widgetId},
      description: description ?? 'Tap on $widgetId',
    );
  }
}

/// Result of running a test scenario.
class TestScenarioResult {
  final bool success;
  final int passedSteps;
  final int totalSteps;
  final String? error;
  final int? failedAtStep;
  final List<StepResult> stepResults;

  const TestScenarioResult({
    required this.success,
    required this.passedSteps,
    required this.totalSteps,
    this.error,
    this.failedAtStep,
    required this.stepResults,
  });

  /// Convenience getter - alias for success
  bool get allPassed => success;

  /// Convenience getter - alias for stepResults
  List<StepResult> get steps => stepResults;

  /// Count of failed steps
  int get failedCount => totalSteps - passedSteps;

  Map<String, dynamic> toJson() => {
    'success': success,
    'passedSteps': passedSteps,
    'totalSteps': totalSteps,
    if (error != null) 'error': error,
    if (failedAtStep != null) 'failedAtStep': failedAtStep,
    'stepResults': stepResults.map((r) => r.toJson()).toList(),
  };
}

/// Result of a single step.
class StepResult {
  final int index;
  final String action;
  final bool success;
  final String? error;
  final Duration duration;
  
  const StepResult({
    required this.index,
    required this.action,
    required this.success,
    this.error,
    required this.duration,
  });
  
  Map<String, dynamic> toJson() => {
    'index': index,
    'action': action,
    'success': success,
    if (error != null) 'error': error,
    'durationMs': duration.inMilliseconds,
  };
}
