library self_test;

export 'annotations.dart';
export 'src/test_code_generator.dart';

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:self_test/recording_fields/button.dart';
import 'package:self_test/recording_fields/checkbox.dart';
import 'package:self_test/recording_fields/floating_action_button.dart';
import 'package:self_test/recording_fields/list_tile.dart';
import 'package:self_test/recording_fields/radio.dart';
import 'package:self_test/recording_fields/slider.dart';
import 'package:self_test/recording_fields/switch.dart';
import 'package:self_test/recording_fields/text_field.dart';
import 'package:self_test/recording_fields/text_form_field.dart';
import 'src/models.dart';
import 'src/test_code_generator.dart';

/// Represents the current recording mode.
enum RecordingMode { inactive, recording, viewing, asserting }

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
  static bool _adaptersRegistered = false;

  factory SelfTestManager() => _instance;
  SelfTestManager._internal() {
    // Register built-in recording builders
    _registerBuiltInBuilders();
  }

  void _registerBuiltInBuilders() {
    registerRecordingBuilder<TextField>((child, widget) => buildRecordingTextField(child as TextField, widget));
    registerRecordingBuilder<ElevatedButton>((child, widget) => buildRecordingButton(child, widget));
    registerRecordingBuilder<TextButton>((child, widget) => buildRecordingButton(child, widget));
    registerRecordingBuilder<OutlinedButton>((child, widget) => buildRecordingButton(child, widget));
    registerRecordingBuilder<IconButton>((child, widget) => buildRecordingButton(child, widget));
    registerRecordingBuilder<CheckboxListTile>((child, widget) => buildRecordingCheckboxListTile(child as CheckboxListTile, widget));
    registerRecordingBuilder<RadioListTile>((child, widget) => buildRecordingRadioListTile(child as RadioListTile, widget));
    registerRecordingBuilder<Slider>((child, widget) => buildRecordingSlider(child as Slider, widget));
    registerRecordingBuilder<SwitchListTile>((child, widget) => buildRecordingSwitchListTile(child as SwitchListTile, widget));
    registerRecordingBuilder<ListTile>((child, widget) => buildRecordingListTile(child as ListTile, widget));
    registerRecordingBuilder<Switch>((child, widget) => buildRecordingSwitch(child as Switch, widget));
    registerRecordingBuilder<Checkbox>((child, widget) => buildRecordingCheckbox(child as Checkbox, widget));
    registerRecordingBuilder<Radio>((child, widget) => buildRecordingRadio(child as Radio, widget));
    registerRecordingBuilder<FloatingActionButton>((child, widget) => buildRecordingFloatingActionButton(child as FloatingActionButton, widget));
    registerRecordingBuilder<TextFormField>((child, widget) => buildRecordingTextFormField(child as TextFormField, widget));
    // Note: DropdownButtonFormField is intentionally not registered due to complexity
  }

  static final Map<String, TestNode> _activeTestNodes = {};
  bool _isSelfTestModeActive = false;
  bool _isTestMode = false; // For testing environments
  GlobalKey<State>? rootKey;
  int _rebuildCounter = 0; // Counter to force rebuilds

  // Recording functionality
  bool _isRecordingModeActive = false;
  int? _currentScriptId;
  Box<TestScript>? _scriptBox;
  Box<TestStep>? _stepBox;
  int _nextScriptId = 0;
  int _nextStepId = 0;

  // UI functionality
  RecordingMode _recordingMode = RecordingMode.inactive;
  TestScript? _currentViewingScript;

  // Widget builder registry for extensibility
  final Map<Type, Widget Function(Widget, SelfTestableWidget)> _recordingBuilders = {};

  /// Helper function to print formatted warnings with color and clear formatting.
  static void _printWarning(String message) {
    debugPrint('\x1B[33m######## START WARNING ########\x1B[0m');
    debugPrint('\x1B[33m$message\x1B[0m');
    debugPrint('\x1B[33m######## END WARNING ########\x1B[0m');
  }

  /// Helper function to print formatted errors with color and clear formatting.
  static void _printError(String message) {
    debugPrint('\x1B[31m######## START ERROR ########\x1B[0m');
    debugPrint('\x1B[31m$message\x1B[0m');
    debugPrint('\x1B[31m######## END ERROR ########\x1B[0m');
  }

  /// Enable/disable verbose logging for debugging
  static bool _verboseLogging = false;

  /// Set verbose logging mode (useful for debugging widget lifecycle issues)
  static void setVerboseLogging(bool enabled) {
    _verboseLogging = enabled;
  }

  /// Registers a custom recording builder for a specific widget type.
  /// This allows developers to extend support for custom or third-party widgets.
  void registerRecordingBuilder<T extends Widget>(Widget Function(Widget, SelfTestableWidget) builder) {
    _recordingBuilders[T] = builder;
    debugPrint('[SelfTest] Registered recording builder for ${T.toString()}');
  }

  /// Gets the registered recording builder for a widget type, if any.
  Widget Function(Widget, SelfTestableWidget)? getRecordingBuilder(Type widgetType) {
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
        debugPrint('[SelfTest] Added assertion: assertText on "$id" with value "$value"');
      } else {
        SelfTestManager._printWarning('Node "$id" not found for assertion');
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
    debugPrint('[SelfTest] Restarting widget tree (rebuild counter: $_rebuildCounter, rootKey: $rootKey)');
    if (rootKey?.currentState != null) {
      debugPrint('[SelfTest] Calling setState on root key');
      (rootKey!.currentState as dynamic).setState(() {});
    } else {
      SelfTestManager._printWarning('rootKey is null or currentState is null (rootKey: $rootKey)');
      // Try to find and set the root key if it exists
      if (rootKey == null) {
        debugPrint('[SelfTest] Attempting to set root key');
        rootKey = GlobalKey<State>(debugLabel: 'SelfTestRoot');
      }
    }
  }

  /// Initializes the local database for storing test scripts and steps.
  Future<void> initializeDatabase() async {
    try {
      debugPrint('[SelfTest] Initializing database...');
      final dir = await getApplicationDocumentsDirectory();
      debugPrint('[SelfTest] Documents directory: ${dir.path}');
      Hive.init(dir.path);
      if (!_adaptersRegistered) {
        Hive.registerAdapter(TestScriptAdapter());
        Hive.registerAdapter(TestStepAdapter());
        _adaptersRegistered = true;
        debugPrint('[SelfTest] Hive adapters registered');
      }
      _scriptBox = await Hive.openBox<TestScript>('testScripts');
      _stepBox = await Hive.openBox<TestStep>('testSteps');
      _nextScriptId = (_scriptBox!.values.isEmpty ? 0 : _scriptBox!.values.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1);
      _nextStepId = (_stepBox!.values.isEmpty ? 0 : _stepBox!.values.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1);
      debugPrint('[SelfTest] Database initialized successfully. Next IDs: script $_nextScriptId, step $_nextStepId');
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR initializing database: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
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
    if (_verboseLogging) {
      debugPrint('[SelfTest] Unregistered TestNode: "$id"');
    }
  }

  /// Starts recording a new test script.
  Future<void> startRecording(String name) async {
    try {
      debugPrint('[SelfTest] Starting recording for script: "$name"');
      if (_scriptBox == null) await initializeDatabase();
      final script = TestScript(
        id: _nextScriptId++,
        name: name,
        createdAt: DateTime.now(),
      );
      await _scriptBox!.put(script.id, script);
      _currentScriptId = script.id;
      _isRecordingModeActive = true;
      setRecordingMode(RecordingMode.recording);
      debugPrint('[SelfTest] Started recording script: "$name" (id: ${script.id})');
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
  Future<void> _recordUserAction(String action, String targetId, [String? value]) async {
    try {
      if (!_isRecordingModeActive || _currentScriptId == null || _stepBox == null) {
        debugPrint('[SelfTest] Not recording or box not initialized, skipping action: $action on $targetId');
        return;
      }
      final order = _stepBox!.values.where((s) => s.scriptId == _currentScriptId).length;
      final step = TestStep(
        id: _nextStepId++,
        scriptId: _currentScriptId!,
        order: order,
        action: action,
        targetId: targetId,
        value: value,
      );
      await _stepBox!.put(step.id, step);
      debugPrint('[SelfTest] Recorded action: $action on "$targetId" (order: $order)');
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR recording action: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Deletes a test script and all its steps.
  Future<void> deleteTestScript(int scriptId) async {
    try {
      debugPrint('[SelfTest] Deleting test script: $scriptId');
      if (_scriptBox == null) await initializeDatabase();

      // Delete all steps for this script
      final stepsToDelete = _stepBox!.values.where((s) => s.scriptId == scriptId).toList();
      for (final step in stepsToDelete) {
        await _stepBox!.delete(step.id);
        debugPrint('[SelfTest] Deleted step: ${step.id}');
      }

      // Delete the script
      await _scriptBox!.delete(scriptId);
      debugPrint('[SelfTest] Deleted test script: $scriptId');
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR deleting test script $scriptId: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Clears all test scripts and steps (for testing purposes).
  Future<void> clearDatabase() async {
    if (_scriptBox != null) await _scriptBox!.clear();
    if (_stepBox != null) await _stepBox!.clear();
    _nextScriptId = 0;
    _nextStepId = 0;
  }

  /// Gets all test scripts.
  List<TestScript> getTestScripts() {
    if (_scriptBox == null) return [];
    return _scriptBox!.values.toList();
  }

  /// Gets all test scripts (async version that initializes DB if needed).
  Future<List<TestScript>> getTestScriptsAsync() async {
    if (_scriptBox == null) await initializeDatabase();
    return _scriptBox!.values.toList();
  }

  /// Gets test steps for a specific script.
  List<TestStep> getTestSteps(int scriptId) {
    if (_stepBox == null) return [];
    return _stepBox!.values.where((s) => s.scriptId == scriptId).toList()..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Triggers the tap action for the given id.
  Future<void> trigger(String id) async {
    try {
      debugPrint('[SelfTest] Looking for TestNode: "$id" to trigger tap');
      debugPrint('[SelfTest] Active nodes: ${_activeTestNodes.keys.toList()}');
      final node = _activeTestNodes[id];
      if (node != null && node.onTap != null) {
        debugPrint('[SelfTest] Found TestNode "$id", triggering tap');
        if (_isRecordingModeActive) {
          await _recordUserAction('trigger', id);
        }
        node.onTap!();
      } else {
        SelfTestManager._printError('TestNode "$id" not found or has no tap callback');
        throw Exception('TestNode with id "$id" not found or has no tap callback.');
      }
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR in trigger("$id"): $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Enters text for the given id.
  Future<void> enterText(String id, String text) async {
    try {
      debugPrint('[SelfTest] Looking for TestNode: "$id" to enter text: "$text"');
      debugPrint('[SelfTest] Active nodes: ${_activeTestNodes.keys.toList()}');
      final node = _activeTestNodes[id];
      if (node != null && node.onTextChange != null) {
        debugPrint('[SelfTest] Found TestNode "$id", entering text');
        if (_isRecordingModeActive) {
          await _recordUserAction('enterText', id, text);
        }
        node.onTextChange!(text);
        node.currentText = text; // Update current text for assertions
      } else {
        SelfTestManager._printError('TestNode "$id" not found or has no text change callback');
        throw Exception('TestNode with id "$id" not found or has no text change callback.');
      }
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR in enterText("$id", "$text"): $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
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
      setRecordingMode(RecordingMode.recording); // Reuse recording mode for visual feedback

      for (final step in steps) {
        debugPrint('[SelfTest] Executing step: ${step.action} on ${step.targetId}');
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
            // Assertions are handled during recording, skip during playback
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

  /// Waits for animations to complete (simulates pumpAndSettle).
  Future<void> waitForAnimations() async {
    // Simple delay; in real implementation, might need more sophisticated logic
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Scrolls to make the specified element visible (if needed).
  /// This is a utility method to ensure elements are accessible before interaction.
  Future<void> ensureVisible(String id) async {
    debugPrint('[SelfTest] ensureVisible called for id: "$id"');
    final node = _activeTestNodes[id];
    debugPrint('[SelfTest] Found node: ${node != null}, context: ${node?.context != null}');
    if (node != null && node.context != null) {
      debugPrint('[SelfTest] Attempting to scroll to "$id"');
      try {
        // Use ScrollController-based scrolling for better reliability
        ScrollController? scrollController;
        try {
          scrollController = PrimaryScrollController.of(node.context!);
          // For list items, estimate position based on item index
          final parts = id.split('_');
          final itemIndex = parts.length > 1 ? int.tryParse(parts.last) ?? 0 : 0;
          final estimatedPosition = itemIndex * 72.0; // Rough estimate of item height
          final clampedPosition = estimatedPosition.clamp(0.0, scrollController.position.maxScrollExtent);
          debugPrint('[SelfTest] Scrolling to estimated position $clampedPosition for item $itemIndex');
          await scrollController.animateTo(
            clampedPosition,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          debugPrint('[SelfTest] Scrolling completed for "$id"');
        } catch (e2) {
          debugPrint('[SelfTest] ScrollController approach failed for "$id": $e2');
          // Final fallback
          try {
            await Scrollable.ensureVisible(
              node.context!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ).timeout(
              const Duration(seconds: 2),
              onTimeout: () {
                debugPrint('[SelfTest] Scrollable.ensureVisible timed out for "$id"');
              },
            );
          } catch (e3) {
            debugPrint('[SelfTest] All scrolling approaches failed for "$id": $e3');
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
    try {
      final manager = SelfTestManager();
      final shouldBeRegistered = ((kDebugMode || kProfileMode) && manager.isSelfTestModeActive) || manager.isTestMode;

      if (shouldBeRegistered && !_wasRegistered) {
        if (SelfTestManager._verboseLogging) {
          debugPrint('[SelfTest] SelfTestableWidget "${widget.id}" registering (mode active: ${manager.isSelfTestModeActive}, test mode: ${manager.isTestMode})');
        }
        final node = TestNode(
          id: widget.id,
          onTap: widget.onTap,
          onTextChange: widget.onTextChange,
          context: context,
        );
        manager.registerTestNode(node);
        _wasRegistered = true;
      } else if (!shouldBeRegistered && _wasRegistered) {
        if (SelfTestManager._verboseLogging) {
          debugPrint('[SelfTest] SelfTestableWidget "${widget.id}" unregistering due to mode change');
        }
        manager.unregisterTestNode(widget.id);
        _wasRegistered = false;
      }
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR in _updateRegistration for "${widget.id}": $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
    }
  }

  void _unregisterIfNeeded() {
    if (_wasRegistered) {
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
    // Ensure registration is up to date on every build
    _updateRegistration();

    final manager = SelfTestManager();
    final isRecording = manager.recordingMode == RecordingMode.recording;
    final isAsserting = manager.recordingMode == RecordingMode.asserting;
    final child = widget.child;

    if (isAsserting) {
      debugPrint('[SelfTest] Building SelfTestableWidget "${widget.id}" with assertion highlight');
      return GestureDetector(
        onTap: () => manager.addAssertion(widget.id),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFF0000), width: 2),
          ),
          child: child,
        ),
      );
    }

    // Intercept interactions for recording or testing
    if (isRecording || manager.isTestMode) {
      final manager = SelfTestManager();

      // First, check if there's a registered builder for this widget type
      final registeredBuilder = manager.getRecordingBuilder(child.runtimeType);
      if (registeredBuilder != null) {
        return registeredBuilder(child, widget);
      }

      // Final fallback: wrap in GestureDetector if onTap is provided, otherwise return as-is with warning
      if (widget.onTap != null) {
        SelfTestManager._printWarning('No recording builder found for ${child.runtimeType}, wrapping in GestureDetector for tap recording');
        return GestureDetector(
          onTap: () async {
            await manager.trigger(widget.id);
            widget.onTap!();
          },
          child: child,
        );
      } else {
        SelfTestManager._printWarning('No recording builder found for ${child.runtimeType} and no onTap provided - interactions will not be recorded');
        return child;
      }
    }

    return child;
  }
}

/// A wrapper widget for the root of the app to enable programmatic restart.
class SelfTestRoot extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  SelfTestRoot({Key? key, required this.child, this.navigatorKey}) : super(key: key ?? (SelfTestManager().rootKey ?? GlobalKey<State>(debugLabel: 'SelfTestRoot'))) {
    // Ensure the manager has a root key
    SelfTestManager().rootKey ??= GlobalKey<State>(debugLabel: 'SelfTestRoot');
  }

  @override
  State<SelfTestRoot> createState() => _SelfTestRootState();
}

class _SelfTestRootState extends State<SelfTestRoot> {
  bool _isFabExpanded = false;
  Offset _fabPosition = Offset(300, 300); // Default position, will be updated

  @override
  void initState() {
    super.initState();
    debugPrint('[SelfTest] SelfTestRoot initState called');
    debugPrint('[SelfTest] SelfTestRoot key: ${widget.key}, manager rootKey: ${SelfTestManager().rootKey}');
    // Ensure the manager's rootKey points to this state
    SelfTestManager().rootKey = widget.key as GlobalKey<State>?;
    // Initialize FAB position to middle-right, fully visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final screenSize = MediaQuery.of(context).size;
        final newPosition = Offset(screenSize.width - 88, screenSize.height / 2 - 36);
        debugPrint('[SelfTest] Setting FAB position to: $newPosition, screen size: $screenSize');
        setState(() {
          _fabPosition = newPosition;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Overlay creation is now handled in initState after position is set
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildDraggableFab(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _fabPosition += details.delta;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            child: FloatingActionButton(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              onPressed: () => setState(() => _isFabExpanded = !_isFabExpanded),
              child: Icon(_isFabExpanded ? Icons.close : Icons.menu, size: 32),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isFabExpanded ? 'CLOSE' : 'TEST',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Force rebuild when self-test mode changes or restart is called
    final manager = SelfTestManager();
    debugPrint('[SelfTest] SelfTestRoot building with key: ${manager.isSelfTestModeActive}_${manager.isTestMode}_${manager.rebuildCounter}');
    final child = KeyedSubtree(
      key: ValueKey('${manager.isSelfTestModeActive}_${manager.isTestMode}_${manager.rebuildCounter}'),
      child: widget.child,
    );

    if (!kDebugMode) return child;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: _buildOverlay(context, manager),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, SelfTestManager manager) {
    final isRecording = manager.recordingMode == RecordingMode.recording;
    debugPrint('[SelfTest] Building overlay, isRecording: $isRecording');
    return Stack(
      children: [
        // Recording indicator
        if (isRecording)
          Positioned(
            top: 50,
            right: 16,
            child: AnimatedOpacity(
              opacity: 0.8,
              duration: const Duration(milliseconds: 500),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text('RECORDING', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        // Expandable FAB or Stop FAB
        if (!isRecording) _buildExpandableFab(context, manager) else _buildStopFab(context, manager),
      ],
    );
  }

  Widget _buildExpandableFab(BuildContext context, SelfTestManager manager) {
    debugPrint('[SelfTest] Building expandable FAB');
    return Stack(
      children: [
        // Background overlay when expanded
        if (_isFabExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _isFabExpanded = false),
              child: Container(color: Colors.black.withOpacity(0.1)),
            ),
          ),

        // Mini FABs (when expanded) - now positioned relative to main FAB
        if (_isFabExpanded) ...[
          Positioned(
            left: _fabPosition.dx,
            top: _fabPosition.dy - 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.green,
                  onPressed: () async {
                    setState(() => _isFabExpanded = false);
                    final name = await _showNameDialog(widget.navigatorKey?.currentContext ?? context);
                    if (name != null && name.isNotEmpty) {
                      await manager.startRecording(name);
                      manager.setRecordingMode(RecordingMode.recording);
                      if ((widget.navigatorKey?.currentContext ?? context).mounted) {
                        ScaffoldMessenger.of(widget.navigatorKey?.currentContext ?? context).showSnackBar(
                          SnackBar(content: Text('Started recording: "$name"')),
                        );
                      }
                    }
                  },
                  child: const Icon(Icons.play_circle_fill, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('START', style: TextStyle(color: Colors.white, fontSize: 8)),
                ),
              ],
            ),
          ),

          Positioned(
            left: _fabPosition.dx,
            top: _fabPosition.dy - 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.blue,
                  onPressed: () {
                    setState(() => _isFabExpanded = false);
                    _showControlPanel(widget.navigatorKey?.currentContext ?? context, manager);
                  },
                  child: const Icon(Icons.list, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('VIEW', style: TextStyle(color: Colors.white, fontSize: 8)),
                ),
              ],
            ),
          ),
        ],
        Positioned(
          left: _fabPosition.dx,
          top: _fabPosition.dy,
          child: _buildDraggableFab(context),
        ),
      ],
    );
  }

  Widget _buildStopFab(BuildContext context, SelfTestManager manager) {
    debugPrint('[SelfTest] Building stop FAB');
    return Positioned(
      left: _fabPosition.dx,
      top: _fabPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _fabPosition += details.delta;
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                onPressed: () {
                  manager.stopRecording();
                  manager.setRecordingMode(RecordingMode.viewing);
                  _showControlPanel(widget.navigatorKey?.currentContext ?? context, manager);
                  if ((widget.navigatorKey?.currentContext ?? context).mounted) {
                    ScaffoldMessenger.of(widget.navigatorKey?.currentContext ?? context).showSnackBar(
                      const SnackBar(content: Text('Recording stopped')),
                    );
                  }
                },
                child: const Icon(Icons.stop, size: 32),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('STOP', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Test Script'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter script name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  void _showControlPanel(BuildContext context, SelfTestManager manager) async {
    // Initialize database if needed
    await manager.initializeDatabase();

    // Use navigator key context if available, otherwise use provided context
    final dialogContext = widget.navigatorKey?.currentContext ?? context;
    showModalBottomSheet(
      context: dialogContext,
      builder: (context) => _ControlPanel(manager: manager),
    );
  }
}

class _ControlPanel extends StatefulWidget {
  final SelfTestManager manager;

  const _ControlPanel({required this.manager});

  @override
  State<_ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<_ControlPanel> {
  TestScript? selectedScript;
  List<TestScript> scripts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    try {
      final loadedScripts = await widget.manager.getTestScriptsAsync();
      if (mounted) {
        setState(() {
          scripts = loadedScripts;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[SelfTest] ERROR loading scripts: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Recorded Tests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Tap a test to view/edit steps', style: TextStyle(fontSize: 14, color: Colors.grey)),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : scripts.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_off, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No recorded tests yet', style: TextStyle(color: Colors.grey)),
                            Text('Tap the play button to start recording', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: scripts.length,
                        itemBuilder: (context, index) {
                          final script = scripts[index];
                          return ListTile(
                            title: Text(script.name),
                            subtitle: Text('Created: ${script.createdAt} • ${script.lastRunStatus}'),
                            onTap: () => setState(() => selectedScript = script),
                            selected: selectedScript == script,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Test'),
                                    content: Text('Are you sure you want to delete "${script.name}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  try {
                                    await widget.manager.deleteTestScript(script.id);
                                    await _loadScripts(); // Refresh the list
                                    if (selectedScript == script) {
                                      setState(() => selectedScript = null);
                                    }
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Deleted "${script.name}"')),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to delete: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
          if (selectedScript != null) ...[
            const Divider(),
            Expanded(
              child: _buildStepsList(selectedScript!),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.manager.setRecordingMode(RecordingMode.asserting);
                      Navigator.of(context).pop();
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline, size: 16),
                        SizedBox(height: 2),
                        Text('Assert', textScaleFactor: 0.7),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        debugPrint('[SelfTest] Running test script: ${selectedScript!.name}');
                        await widget.manager.runTestScript(selectedScript!.id);
                        debugPrint('[SelfTest] Test run completed');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Test completed successfully')),
                          );
                        }
                      } catch (e, stackTrace) {
                        debugPrint('[SelfTest] ERROR running test: $e');
                        debugPrint('[SelfTest] Stack trace: $stackTrace');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Test failed: $e')),
                          );
                        }
                      }
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, size: 16),
                        SizedBox(height: 2),
                        Text('Run', textScaleFactor: 0.7),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        debugPrint('[SelfTest] Exporting script: ${selectedScript!.name}');
                        final steps = widget.manager.getTestSteps(selectedScript!.id);
                        final generator = TestCodeGenerator();
                        await generator.exportToDart(selectedScript!, steps);
                        debugPrint('[SelfTest] Export completed');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Test exported to app documents/test_generated')),
                          );
                        }
                      } catch (e, stackTrace) {
                        debugPrint('[SelfTest] ERROR exporting: $e');
                        debugPrint('[SelfTest] Stack trace: $stackTrace');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Export failed: $e')),
                          );
                        }
                      }
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.code, size: 16),
                        SizedBox(height: 2),
                        Text('Dart', textScaleFactor: 0.7),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        debugPrint('[SelfTest] Exporting script to JSON: ${selectedScript!.name}');
                        final steps = widget.manager.getTestSteps(selectedScript!.id);
                        final generator = TestCodeGenerator();
                        await generator.exportToJson(selectedScript!, steps);
                        debugPrint('[SelfTest] JSON export completed');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Test exported to JSON in app documents/test_generated')),
                          );
                        }
                      } catch (e, stackTrace) {
                        debugPrint('[SelfTest] ERROR exporting to JSON: $e');
                        debugPrint('[SelfTest] Stack trace: $stackTrace');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('JSON export failed: $e')),
                          );
                        }
                      }
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.data_object, size: 16),
                        SizedBox(height: 2),
                        Text('JSON', textScaleFactor: 0.7),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepsList(TestScript script) {
    final steps = widget.manager.getTestSteps(script.id);
    return ListView.builder(
      itemCount: steps.length,
      itemBuilder: (context, index) {
        final step = steps[index];
        return ListTile(
          title: Text('${step.action} on ${step.targetId}'),
          subtitle: step.value != null ? Text('Value: ${step.value}') : null,
        );
      },
    );
  }
}
