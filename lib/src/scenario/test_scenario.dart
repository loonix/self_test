import '../core/manager.dart';

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
          step: step,
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
          step: step,
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
  factory TestStep.enterText(String widgetId, String text,
      {String? description}) {
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

  /// Count of passed steps - alias for passedSteps
  int get passedCount => passedSteps;

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
  final TestStep? step;
  final String? screenshotPath;

  const StepResult({
    required this.index,
    required this.action,
    required this.success,
    this.error,
    required this.duration,
    this.step,
    this.screenshotPath,
  });

  /// Convenience getter - alias for success
  bool get passed => success;

  Map<String, dynamic> toJson() => {
        'index': index,
        'action': action,
        'success': success,
        if (error != null) 'error': error,
        'durationMs': duration.inMilliseconds,
        if (screenshotPath != null) 'screenshotPath': screenshotPath,
      };
}
