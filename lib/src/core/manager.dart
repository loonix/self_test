import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../gestures/pointer_driver.dart';
import '../gestures/text_input_driver.dart';
import '../locator/element_scanner.dart';
import '../locator/locator.dart';
import '../models.dart';
import '../persistence/recording_store.dart';
import '../screenshot/screenshot_writer.dart';
import 'recording_mode.dart';
import 'test_binding.dart';
import 'test_node.dart';

// Forward declaration for SelfTestableWidget to avoid circular imports
// The actual type is defined in widgets/self_testable_widget.dart
typedef RecordingBuilder =
    Widget Function(Widget child, dynamic selfTestableWidget);

/// Singleton manager for self-testing functionality.
class SelfTestManager {
  static final SelfTestManager _instance = SelfTestManager._internal();

  factory SelfTestManager() => _instance;
  SelfTestManager._internal() {
    // Built-in builders are registered by self_test.dart after imports are resolved
  }

  RecordingStore _store = InMemoryRecordingStore();

  /// The store recordings are written to. In-memory by default.
  RecordingStore get recordingStore => _store;

  /// Replaces the recording store, for an app that wants recordings to
  /// survive a restart. Call before [startRecording].
  void useRecordingStore(RecordingStore store) {
    _store = store;
  }

  static final Map<String, TestNode> _activeTestNodes = {};
  bool _isSelfTestModeActive = false;
  bool _isTestMode = false; // For testing environments
  GlobalKey<State>? rootKey;
  int _rebuildCounter = 0; // Counter to force rebuilds

  // Recording functionality
  bool _isRecordingModeActive = false;
  int? _currentScriptId;

  // UI functionality
  RecordingMode _recordingMode = RecordingMode.inactive;
  TestScript? _currentViewingScript;

  // Widget builder registry for extensibility
  final Map<Type, RecordingBuilder> _recordingBuilders = {};

  /// Helper function to print formatted warnings with color and clear formatting.
  static void printWarning(String message) {
    debugPrint('\x1B[33m######## START WARNING ########\x1B[0m');
    debugPrint('\x1B[33m$message\x1B[0m');
    debugPrint('\x1B[33m######## END WARNING ########\x1B[0m');
  }

  /// Helper function to print formatted errors with color and clear formatting.
  static void printError(String message) {
    debugPrint('\x1B[31m######## START ERROR ########\x1B[0m');
    debugPrint('\x1B[31m$message\x1B[0m');
    debugPrint('\x1B[31m######## END ERROR ########\x1B[0m');
  }

  /// Enable/disable verbose logging for debugging
  static bool _verboseLogging = false;

  /// Whether verbose logging is enabled.
  static bool get verboseLogging => _verboseLogging;

  /// Set verbose logging mode (useful for debugging widget lifecycle issues)
  static void setVerboseLogging(bool enabled) {
    _verboseLogging = enabled;
  }

  /// Registers a custom recording builder for a specific widget type.
  /// This allows developers to extend support for custom or third-party widgets.
  void registerRecordingBuilder<T extends Widget>(RecordingBuilder builder) {
    _recordingBuilders[T] = builder;
    debugPrint('[SelfTest] Registered recording builder for ${T.toString()}');
  }

  /// Gets the registered recording builder for a widget type, if any.
  RecordingBuilder? getRecordingBuilder(Type widgetType) {
    return _recordingBuilders[widgetType];
  }

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

  /// Gets the recording mode.
  RecordingMode get recordingMode => _recordingMode;

  /// Sets the recording mode and restarts the widget tree.
  void setRecordingMode(RecordingMode mode) {
    _recordingMode = mode;
    restartWidgetTree();
  }

  /// Gets the current viewing script.
  TestScript? get currentViewingScript => _currentViewingScript;

  /// Sets the current viewing script.
  void setCurrentViewingScript(TestScript? script) {
    _currentViewingScript = script;
  }

  /// Adds an assertion for the given id.
  Future<void> addAssertion(String id) async {
    try {
      debugPrint('[SelfTest] Adding assertion for node: "$id"');
      final node = _activeTestNodes[id];
      if (node != null) {
        final value = node.currentText ?? '';
        await _recordUserAction('assertText', id, value);
        debugPrint(
          '[SelfTest] Added assertion: assertText on "$id" with value "$value"',
        );
      } else {
        printWarning('Node "$id" not found for assertion');
      }
      setRecordingMode(RecordingMode.viewing);
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR adding assertion for "$id": $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      setRecordingMode(RecordingMode.viewing); // Ensure we exit asserting mode
      rethrow;
    }
  }

  /// Gets the rebuild counter for forcing widget tree rebuilds.
  int get rebuildCounter => _rebuildCounter;

  /// Restarts the widget tree by setting state on the root key.
  void restartWidgetTree() {
    _rebuildCounter++;
    debugPrint(
      '[SelfTest] Restarting widget tree (rebuild counter: $_rebuildCounter, rootKey: $rootKey)',
    );
    if (rootKey?.currentState != null) {
      debugPrint('[SelfTest] Calling setState on root key');
      (rootKey!.currentState as dynamic).setState(() {});
    } else {
      printWarning(
        'rootKey is null or currentState is null (rootKey: $rootKey)',
      );
      // Try to find and set the root key if it exists
      if (rootKey == null) {
        debugPrint('[SelfTest] Attempting to set root key');
        rootKey = GlobalKey<State>(debugLabel: 'SelfTestRoot');
      }
    }
  }

  /// Prepares the recording store.
  Future<void> initializeRecordingStore() async {
    await _store.initialize();
  }

  @Deprecated(
    'Renamed to initializeRecordingStore; there is no database any more. '
    'Will be removed in 0.3.0.',
  )
  Future<void> initializeDatabase() => initializeRecordingStore();

  /// Gets the active test nodes (for testing purposes).
  Map<String, TestNode> get activeTestNodes => _activeTestNodes;

  /// Every registered node and its callbacks, keyed by id. Used by the
  /// WebSocket bridge to answer a discovery request.
  Map<String, Map<String, dynamic>> getRegisteredWidgets() {
    final result = <String, Map<String, dynamic>>{};
    for (final entry in _activeTestNodes.entries) {
      result[entry.key] = {
        'onTap': entry.value.onTap,
        'onTextChange': entry.value.onTextChange,
      };
    }
    return result;
  }

  /// Describes a single registered node, or null when [id] is not registered.
  Map<String, dynamic>? getWidgetInfo(String id) {
    final node = _activeTestNodes[id];
    if (node == null) return null;

    return {
      'id': node.id,
      'type': node.onTextChange != null ? 'textField' : 'button',
      'hasCallback': node.onTap != null || node.onTextChange != null,
      'currentText': node.currentText,
    };
  }

  /// Registers a test node.
  void registerTestNode(TestNode node) {
    _activeTestNodes[node.id] = node;
    debugPrint(
      '[SelfTest] Registered TestNode: "${node.id}" (tap: ${node.onTap != null}, text: ${node.onTextChange != null})',
    );
  }

  /// Unregisters a test node.
  void unregisterTestNode(String id) {
    _activeTestNodes.remove(id);
    if (_verboseLogging) {
      debugPrint('[SelfTest] Unregistered TestNode: "$id"');
    }
  }

  /// Starts recording a new test script.
  Future<void> startRecording(String name) async {
    try {
      debugPrint('[SelfTest] Starting recording for script: "$name"');
      final script = await _store.createScript(name);
      _currentScriptId = script.id;
      _isRecordingModeActive = true;
      setRecordingMode(RecordingMode.recording);
      debugPrint(
        '[SelfTest] Started recording script: "$name" (id: ${script.id})',
      );
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR starting recording: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Stops the current recording.
  void stopRecording() {
    _isRecordingModeActive = false;
    _currentScriptId = null;
    debugPrint('[SelfTest] Stopped recording');
  }

  /// Records a user action during recording.
  Future<void> _recordUserAction(
    String action,
    String targetId, [
    String? value,
  ]) async {
    try {
      if (!_isRecordingModeActive || _currentScriptId == null) {
        debugPrint(
          '[SelfTest] Not recording, skipping action: $action on $targetId',
        );
        return;
      }
      await _store.recordStep(
        scriptId: _currentScriptId!,
        action: action,
        targetId: targetId,
        value: value,
      );
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR recording action: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Deletes a test script and all its steps.
  Future<void> deleteTestScript(int scriptId) async {
    await _store.deleteScript(scriptId);
  }

  /// Clears all recorded scripts and steps.
  Future<void> clearRecordings() async {
    await _store.clear();
  }

  @Deprecated(
    'Renamed to clearRecordings; there is no database any more. '
    'Will be removed in 0.3.0.',
  )
  Future<void> clearDatabase() => clearRecordings();

  /// Gets all test scripts.
  List<TestScript> getTestScripts() {
    return _store.getScripts();
  }

  /// Gets all test scripts (async version that initializes DB if needed).
  Future<List<TestScript>> getTestScriptsAsync() async {
    return _store.getScriptsAsync();
  }

  /// Gets test steps for a specific script.
  List<RecordedStep> getTestSteps(int scriptId) {
    return _store.getSteps(scriptId);
  }

  // ---------------------------------------------------------------------------
  // Locating and driving any widget
  // ---------------------------------------------------------------------------

  final ElementScanner _scanner = const ElementScanner();
  final TextInputDriver _textInput = const TextInputDriver();
  ClockAdvance? _clock;
  int _drivingDepth = 0;

  /// Registers how to wait for the framework to settle.
  ///
  /// In a widget test this is `tester.pump`: the test owns the clock, so a
  /// real `Future.delayed` inside a `testWidgets` body never completes. In a
  /// real app leave it unset.
  void useClock(ClockAdvance advance) {
    _clock = advance;
  }

  /// Forgets the clock registered by [useClock]. Call it in `tearDown`, or the
  /// next test inherits a `pump` bound to a finished tester.
  void clearClock() {
    _clock = null;
  }

  PointerDriver get _pointer => PointerDriver(advance: _clock);

  /// The widget [locator] points at.
  ///
  /// Throws [WidgetNotFoundError], which lists what was on screen instead.
  WidgetSnapshot find(SelfTestLocator locator) => _scanner.resolve(locator);

  /// Every widget [locator] matches, in tree order. Empty when none do.
  List<WidgetSnapshot> findAll(SelfTestLocator locator) =>
      _scanner.findAll(locator);

  /// Whether [locator] matches anything in the widget tree right now.
  ///
  /// A list keeps items built after they scroll out of view, so this can be
  /// true for something the user cannot see. Ask [isVisible] for that.
  bool exists(SelfTestLocator locator) => _scanner.tryResolve(locator) != null;

  /// Whether [locator] matches something the user can actually see.
  bool isVisible(SelfTestLocator locator) =>
      _scanner.tryResolve(locator)?.isOnScreen ?? false;

  /// Everything on screen that can be acted on, plus the labels around it.
  ///
  /// This is what an agent asks for before deciding what to do, and what the
  /// bridge answers a discovery request with. It needs no registration: the
  /// widgets are read straight off the element tree.
  List<WidgetSnapshot> describeScreen() => _scanner.describeInteractive();

  /// Taps the widget [locator] points at, with a real pointer event.
  ///
  /// Hit testing runs, so a widget behind a dialog is not reachable and a
  /// disabled button swallows the tap, exactly as for a finger. Pump after
  /// this in a test: the framework has to rebuild before the effect is
  /// visible.
  Future<void> tap(SelfTestLocator locator) async {
    final target = _requireTappable(locator);
    await _drive(locator, 'trigger', null, () => _pointer.tap(target.center));
  }

  /// Two quick taps on the widget [locator] points at.
  Future<void> doubleTap(SelfTestLocator locator) async {
    final target = _requireTappable(locator);
    await _drive(
      locator,
      'doubleTap',
      null,
      () => _pointer.doubleTap(target.center),
    );
  }

  /// Presses and holds the widget [locator] points at.
  ///
  /// Under `flutter_test` this needs [useClock]; without it the press cannot
  /// be held and the driver says so rather than degrading to a tap.
  Future<void> longPress(
    SelfTestLocator locator, {
    Duration hold = const Duration(milliseconds: 600),
  }) async {
    final target = _requireTappable(locator);
    await _drive(
      locator,
      'longPress',
      null,
      () => _pointer.longPress(target.center, hold: hold),
    );
  }

  /// Drags from the centre of the widget [locator] points at by [offset].
  Future<void> dragFrom(
    SelfTestLocator locator,
    Offset offset, {
    int steps = 10,
    Duration duration = const Duration(milliseconds: 300),
  }) async {
    final target = _requireTappable(locator);
    await _drive(
      locator,
      'drag',
      '${offset.dx},${offset.dy}',
      () => _pointer.drag(
        target.center,
        target.center + offset,
        steps: steps,
        duration: duration,
      ),
    );
  }

  /// Sends a wheel or trackpad scroll over the widget [locator] points at.
  Future<void> scrollBy(SelfTestLocator locator, Offset delta) async {
    final target = _requireTappable(locator);
    await _drive(locator, 'scroll', '${delta.dx},${delta.dy}', () async {
      _pointer.scroll(target.center, delta);
    });
  }

  /// Types [text] into the field [locator] points at, through the same path
  /// the soft keyboard uses.
  Future<void> typeInto(SelfTestLocator locator, String text) async {
    final target = _scanner.resolve(locator);
    await _drive(locator, 'enterText', text, () async {
      _textInput.enterText(target.element, text);
    });
    final node = _activeTestNodes[target.id ?? locator.value];
    if (node != null) node.currentText = text;
  }

  /// Fires the keyboard action of the field [locator] points at.
  Future<void> submit(SelfTestLocator locator) async {
    final target = _scanner.resolve(locator);
    await _drive(locator, 'submit', null, () async {
      _textInput.submit(target.element);
    });
  }

  /// The text the widget [locator] points at is showing, or null when it
  /// shows none.
  String? readText(SelfTestLocator locator) {
    final target = _scanner.tryResolve(locator);
    if (target == null) return null;
    return target.text ?? _textInput.textOf(target.element);
  }

  WidgetSnapshot _requireTappable(SelfTestLocator locator) {
    final target = _scanner.resolve(locator);
    if (!target.hasSize) {
      throw StateError(
        'Widget $locator is in the tree but has no size, so there is nothing '
        'to tap. It is probably inside a collapsed or unbuilt parent.',
      );
    }
    if (!target.isOnScreen) {
      throw StateError(
        'Widget $locator is in the tree at ${target.bounds} but outside the '
        'view, so a tap at its centre would land on whatever is drawn there '
        'instead. Scroll it into view first.',
      );
    }
    return target;
  }

  /// Records the step, runs the gesture, and keeps the recorder from writing
  /// the same action twice.
  ///
  /// A driven gesture reaches the app's real handler, which for a widget
  /// wrapped in `SelfTestableWidget` calls back into [recordTap]. Without the
  /// depth guard, one drive would record two steps.
  Future<void> _drive(
    SelfTestLocator locator,
    String action,
    String? value,
    Future<void> Function() gesture,
  ) async {
    if (_isRecordingModeActive) {
      await _recordUserAction(action, locator.value, value);
    }
    _drivingDepth++;
    try {
      await gesture();
    } finally {
      _drivingDepth--;
    }
  }

  /// Records a tap the user just made on a registered widget.
  ///
  /// Called by the recording wrappers. It records and returns: it does not
  /// perform the tap, because the tap already happened.
  Future<void> recordTap(String id) async {
    if (_drivingDepth > 0) return;
    if (!_isRecordingModeActive) return;
    await _recordUserAction('trigger', id);
  }

  /// Records a text change the user just made on a registered widget.
  Future<void> recordTextChange(String id, String value) async {
    _activeTestNodes[id]?.currentText = value;
    if (_drivingDepth > 0) return;
    if (!_isRecordingModeActive) return;
    await _recordUserAction('enterText', id, value);
  }

  /// Taps the widget registered under [id].
  ///
  /// Kept for scripts and bridges written against the old API. It now sends a
  /// real pointer event when the widget is on screen, and only falls back to
  /// invoking the registered `onTap` when it is not, which is the case for a
  /// node registered without a laid-out widget behind it.
  Future<void> trigger(String id) async {
    final target = _scanner.tryResolve(SelfTestLocator.id(id));
    if (target != null && target.hasSize) {
      await _drive(
        SelfTestLocator.id(id),
        'trigger',
        null,
        () => _pointer.tap(target.center),
      );
      return;
    }

    final node = _activeTestNodes[id];
    if (node?.onTap == null) {
      printError('TestNode "$id" not found or has no tap callback');
      throw Exception(
        'TestNode with id "$id" not found or has no tap callback.',
      );
    }
    printWarning(
      'Widget "$id" is registered but not on screen, so the tap could not be '
      'a real pointer event. Calling its onTap callback directly.',
    );
    if (_isRecordingModeActive) {
      await _recordUserAction('trigger', id);
    }
    _drivingDepth++;
    try {
      node!.onTap!();
    } finally {
      _drivingDepth--;
    }
  }

  /// Enters text into the field registered under [id].
  ///
  /// Like [trigger], this now goes through the real text input path when the
  /// field is on screen, and falls back to the registered `onTextChange`
  /// callback when it is not.
  Future<void> enterText(String id, String text) async {
    final target = _scanner.tryResolve(SelfTestLocator.id(id));
    if (target != null && target.hasSize) {
      try {
        await _drive(SelfTestLocator.id(id), 'enterText', text, () async {
          _textInput.enterText(target.element, text);
        });
        _activeTestNodes[id]?.currentText = text;
        return;
      } on StateError {
        // Registered, on screen, but not a text field. The callback below is
        // the app telling us what it wants done instead.
      }
    }

    final node = _activeTestNodes[id];
    if (node?.onTextChange == null) {
      printError('TestNode "$id" not found or has no text change callback');
      throw Exception(
        'TestNode with id "$id" not found or has no text change callback.',
      );
    }
    if (_isRecordingModeActive) {
      await _recordUserAction('enterText', id, text);
    }
    _drivingDepth++;
    try {
      node!.onTextChange!(text);
    } finally {
      _drivingDepth--;
    }
    node.currentText = text;
  }

  /// Runs a recorded test script by executing its steps.
  Future<void> runTestScript(int scriptId) async {
    // Activate test mode to register widgets
    setTestMode(true);
    restartWidgetTree();
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      debugPrint('[SelfTest] Running test script: $scriptId');
      final steps = getTestSteps(scriptId);
      if (steps.isEmpty) {
        debugPrint('[SelfTest] No steps found for script $scriptId');
        return;
      }

      // Show running indicator
      setRecordingMode(
        RecordingMode.recording,
      ); // Reuse recording mode for visual feedback

      for (final step in steps) {
        debugPrint(
          '[SelfTest] Executing step: ${step.action} on ${step.targetId}',
        );
        switch (step.action) {
          case 'trigger':
            await trigger(step.targetId);
            break;
          case 'enterText':
            if (step.value != null) {
              await enterText(step.targetId, step.value!);
            }
            break;
          case 'assertText':
            final node = _activeTestNodes[step.targetId];
            if (node == null) {
              debugPrint(
                '[SelfTest] ASSERTION FAILED: Widget "${step.targetId}" not found',
              );
              throw AssertionError(
                'Assertion failed: Widget "${step.targetId}" not found for text assertion',
              );
            }
            if (node.currentText != step.value) {
              debugPrint(
                '[SelfTest] ASSERTION FAILED: Expected "${step.value}" but got "${node.currentText}"',
              );
              throw AssertionError(
                'Assertion failed: Expected "${step.value}" but got "${node.currentText}" for widget "${step.targetId}"',
              );
            }
            debugPrint(
              '[SelfTest] ASSERTION PASSED: "${step.targetId}" has text "${step.value}"',
            );
            break;
          case 'assertExists':
            if (!_activeTestNodes.containsKey(step.targetId)) {
              debugPrint(
                '[SelfTest] ASSERTION FAILED: Widget "${step.targetId}" does not exist',
              );
              throw AssertionError(
                'Assertion failed: Widget "${step.targetId}" does not exist',
              );
            }
            debugPrint(
              '[SelfTest] ASSERTION PASSED: "${step.targetId}" exists',
            );
            break;
          default:
            debugPrint('[SelfTest] Unknown action: ${step.action}');
        }
        await waitForAnimations();
      }

      // Hide running indicator
      setRecordingMode(RecordingMode.viewing);
      debugPrint('[SelfTest] Test script $scriptId completed');
    } catch (e, stackTrace) {
      // Hide running indicator on error
      setRecordingMode(RecordingMode.viewing);
      debugPrint('[SelfTest] ERROR running test script $scriptId: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    } finally {
      // Deactivate test mode
      setTestMode(false);
      restartWidgetTree();
    }
  }

  /// Gives the UI a moment to settle after an action.
  ///
  /// Under `flutter_test` this returns without waiting. A real
  /// `Future.delayed` never completes inside a `testWidgets` body: the test
  /// owns the clock and only `pump` advances it, so awaiting one deadlocks
  /// until the ten-minute timeout. Three tests in the example app died that
  /// way. In a test, pump yourself after the action; that is the point of
  /// having the clock.
  Future<void> waitForAnimations() async {
    const settle = Duration(milliseconds: 100);
    final clock = _clock;
    if (clock != null) {
      await clock(settle);
      return;
    }
    if (isRunningUnderTest) return;
    await Future.delayed(settle);
  }

  /// Scrolls to make the specified element visible (if needed).
  /// This is a utility method to ensure elements are accessible before interaction.
  Future<void> ensureVisible(String id) async {
    debugPrint('[SelfTest] ensureVisible called for id: "$id"');
    final node = _activeTestNodes[id];
    debugPrint(
      '[SelfTest] Found node: ${node != null}, context: ${node?.context != null}',
    );
    if (node != null && node.context != null) {
      debugPrint('[SelfTest] Attempting to scroll to "$id"');
      try {
        // Use ScrollController-based scrolling for better reliability
        ScrollController? scrollController;
        try {
          scrollController = PrimaryScrollController.of(node.context!);
          // For list items, estimate position based on item index
          final parts = id.split('_');
          final itemIndex = parts.length > 1
              ? int.tryParse(parts.last) ?? 0
              : 0;
          final estimatedPosition =
              itemIndex * 72.0; // Rough estimate of item height
          final clampedPosition = estimatedPosition.clamp(
            0.0,
            scrollController.position.maxScrollExtent,
          );
          debugPrint(
            '[SelfTest] Scrolling to estimated position $clampedPosition for item $itemIndex',
          );
          await scrollController.animateTo(
            clampedPosition,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          debugPrint('[SelfTest] Scrolling completed for "$id"');
        } catch (e2) {
          debugPrint(
            '[SelfTest] ScrollController approach failed for "$id": $e2',
          );
          // Final fallback
          try {
            await Scrollable.ensureVisible(
              node.context!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ).timeout(
              const Duration(seconds: 2),
              onTimeout: () {
                debugPrint(
                  '[SelfTest] Scrollable.ensureVisible timed out for "$id"',
                );
              },
            );
          } catch (e3) {
            debugPrint(
              '[SelfTest] All scrolling approaches failed for "$id": $e3',
            );
          }
        }
      } catch (e) {
        debugPrint('[SelfTest] ERROR in ensureVisible("$id"): $e');
      }
      await waitForAnimations();
    } else {
      debugPrint('[SelfTest] WARNING: Node "$id" not found or has no context');
    }
  }
  // ---------------------------------------------------------------------------
  // Screenshots
  // ---------------------------------------------------------------------------

  final ScreenshotWriter _screenshotWriter = const ScreenshotWriter();
  GlobalKey? _screenshotKey;
  String? _screenshotDirectory;

  /// The boundary [ScreenshotBoundary] registered, if any.
  GlobalKey? get screenshotKey => _screenshotKey;

  /// Registers the repaint boundary to photograph. Called by
  /// [ScreenshotBoundary]; an app can call it directly with its own key.
  void setScreenshotKey(GlobalKey key) {
    _screenshotKey = key;
  }

  /// Forgets [key] if it is the registered one. Called when a
  /// [ScreenshotBoundary] is disposed, so a stale key never outlives its tree.
  void clearScreenshotKey(GlobalKey key) {
    if (_screenshotKey == key) {
      _screenshotKey = null;
    }
  }

  /// Where screenshots are written. Defaults to the system temp directory.
  String? get screenshotDirectory => _screenshotDirectory;

  /// Sets the screenshot directory. Passing null restores the default.
  Future<void> setScreenshotDirectory(String? path) async {
    _screenshotDirectory = path;
  }

  /// Captures the subtree under the registered [ScreenshotBoundary] and
  /// returns the PNG bytes, or null when there is nothing to photograph.
  ///
  /// With no boundary registered it falls back to the first
  /// [RenderRepaintBoundary] found in the render tree, which is what the app
  /// root usually is. The fallback is best effort: wrap the app in a
  /// [ScreenshotBoundary] to make the target explicit.
  Future<Uint8List?> captureScreenshotBytes({double pixelRatio = 3.0}) async {
    final boundary = _findScreenshotBoundary();
    if (boundary == null) {
      printWarning(
        'No RenderRepaintBoundary to capture. Wrap the app in a ScreenshotBoundary.',
      );
      return null;
    }

    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        printError('Screenshot could not be encoded as PNG');
        return null;
      }
      return byteData.buffer.asUint8List();
    } catch (e, stackTrace) {
      printError('Screenshot capture failed: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      return null;
    }
  }

  RenderRepaintBoundary? _findScreenshotBoundary() {
    final keyed = _screenshotKey?.currentContext?.findRenderObject();
    if (keyed is RenderRepaintBoundary) return keyed;

    final root = WidgetsBinding.instance.rootElement?.findRenderObject();
    if (root is RenderRepaintBoundary) return root;

    RenderRepaintBoundary? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderRepaintBoundary) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    root?.visitChildren(visit);
    return found;
  }

  /// Captures a screenshot and writes it to [screenshotDirectory].
  ///
  /// Returns the file path, or null when capture or writing failed.
  Future<String?> captureScreenshot([String? name]) async {
    final bytes = await captureScreenshotBytes();
    if (bytes == null) return null;

    try {
      final slug = (name ?? 'screenshot').replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final fileName = '${slug}_${DateTime.now().millisecondsSinceEpoch}.png';
      final path = await _screenshotWriter.write(
        bytes,
        directory: _screenshotDirectory ?? _screenshotWriter.defaultDirectory,
        fileName: fileName,
      );
      debugPrint('[SelfTest] Screenshot saved to: $path');
      return path;
    } catch (e, stackTrace) {
      printError('Screenshot could not be written: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Test runs
  // ---------------------------------------------------------------------------

  final List<Map<String, dynamic>> _testRunLog = [];
  String? _currentTestRun;

  /// The name of the running test run, or null when none is active.
  String? get currentTestRun => _currentTestRun;

  /// Steps logged during the current test run.
  List<Map<String, dynamic>> get testRunLog => List.unmodifiable(_testRunLog);

  /// Starts a named test run, discarding any log from a previous one.
  void startTestRun(String name) {
    _testRunLog.clear();
    _currentTestRun = name;
    debugPrint('[SelfTest] Started test run: $name');
  }

  /// Appends a step to the current test run, optionally photographing it.
  ///
  /// Does nothing when no run is active, so instrumentation left in app code
  /// is harmless outside a test.
  Future<void> logTestStep(
    String description, {
    bool captureScreen = false,
    bool passed = true,
    String? error,
  }) async {
    if (_currentTestRun == null) return;

    String? screenshotPath;
    if (captureScreen) {
      await waitForAnimations();
      screenshotPath = await captureScreenshot(description);
    }

    _testRunLog.add({
      'description': description,
      'passed': passed,
      'error': error,
      'screenshot': screenshotPath,
      'at': DateTime.now().toIso8601String(),
    });
  }

  /// The current test run as JSON, ready to be written out by the host app.
  Map<String, dynamic> exportTestRun() => {
    'name': _currentTestRun,
    'passed': _testRunLog.every((step) => step['passed'] == true),
    'stepCount': _testRunLog.length,
    'steps': _testRunLog,
  };
}
