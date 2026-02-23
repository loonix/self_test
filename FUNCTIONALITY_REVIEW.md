<!-- cSpell:ignore writeln -->
# Functionality Review: self_test Flutter Package

**Review Date:** 2026-01-12
**Package Version:** 0.0.1
**Reviewer:** Claude (Functionality Analysis)

---

## Executive Summary

This document provides a comprehensive review of all functionalities in the `self_test` package, evaluating implementation quality, identifying edge cases and bugs, and suggesting improvements.

---

## 1. Recording Functionality

### Implementation Overview

Recording captures user interactions and stores them as `TestStep` objects in a Hive database.

**Flow:**
```
User Interaction → SelfTestableWidget → Recording Builder → SelfTestManager._recordUserAction() → Hive DB
```

**Key Code Locations:**
- Start recording: `lib/self_test.dart:246-264`
- Record action: `lib/self_test.dart:275-297`
- Stop recording: `lib/self_test.dart:268-272`

### Current Implementation

```dart
// lib/self_test.dart:275-297
Future<void> _recordUserAction(String action, String targetId, [String? value]) async {
  if (!_isRecordingModeActive || _currentScriptId == null || _stepBox == null) {
    return;  // Silent return
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
}
```

### Supported Actions

| Action | Recorded When | Value Captured |
|--------|--------------|----------------|
| `trigger` | Button tap, checkbox toggle, radio select | None |
| `enterText` | Text field change | Text value |
| `assertText` | Manual assertion added | Expected text |
| `assertExists` | (Not implemented in recording) | N/A |

### Edge Cases & Bugs

1. **BUG: Order calculation is O(n)** (`lib/self_test.dart:281`)
   ```dart
   final order = _stepBox!.values.where((s) => s.scriptId == _currentScriptId).length;
   ```
   - Scans all steps on every recording action
   - Performance degrades with many steps

2. **BUG: Race condition on concurrent recordings**
   - `_nextStepId++` is not atomic
   - Rapid interactions could create duplicate IDs

3. **EDGE CASE: Widget unregistered during recording**
   - Recording continues but playback will fail
   - No warning during recording

4. **EDGE CASE: Recording during navigation**
   - Steps recorded but widget tree changes
   - Playback may not find widgets on different screens

5. **LIMITATION: No long-press or gesture recording**
   - Only `onTap` and `onChanged` are captured
   - Complex gestures (swipe, drag, pinch) not supported

### Recommendations

1. **Track step count per script:**
   ```dart
   final Map<int, int> _stepCountByScript = {};

   Future<void> _recordUserAction(...) async {
     final order = _stepCountByScript[_currentScriptId] ?? 0;
     _stepCountByScript[_currentScriptId!] = order + 1;
     // ...
   }
   ```

2. **Add navigation tracking:**
   ```dart
   Future<void> recordNavigation(String routeName) async {
     await _recordUserAction('navigate', routeName);
   }
   ```

3. **Validate widget exists before recording completes:**
   ```dart
   void stopRecording() {
     final steps = getTestSteps(_currentScriptId!);
     for (final step in steps) {
       if (!_activeTestNodes.containsKey(step.targetId)) {
         _printWarning('Widget "${step.targetId}" not found at recording end');
       }
     }
   }
   ```

---

## 2. Playback Functionality

### Implementation Overview

Playback executes recorded steps by invoking callbacks on registered `TestNode` objects.

**Flow:**
```
runTestScript() → getTestSteps() → for each step → trigger()/enterText() → waitForAnimations()
```

**Key Code Location:** `lib/self_test.dart:396-446`

### Current Implementation

```dart
// lib/self_test.dart:396-446
Future<void> runTestScript(int scriptId) async {
  setTestMode(true);
  restartWidgetTree();
  await Future.delayed(const Duration(milliseconds: 100));

  try {
    final steps = getTestSteps(scriptId);
    setRecordingMode(RecordingMode.recording);  // Visual feedback

    for (final step in steps) {
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
          break;  // Skipped during playback!
        default:
          debugPrint('[SelfTest] Unknown action: ${step.action}');
      }
      await waitForAnimations();
    }
  } finally {
    setTestMode(false);
    restartWidgetTree();
  }
}
```

### Edge Cases & Bugs

1. **BUG: Assertions skipped during playback** (`lib/self_test.dart:425-426`)
   ```dart
   case 'assertText':
     break;  // Does nothing!
   ```
   - Assertions are recorded but never executed
   - Test always "passes" regardless of actual state

2. **BUG: Fixed 100ms delay insufficient** (`lib/self_test.dart:400`)
   ```dart
   await Future.delayed(const Duration(milliseconds: 100));
   ```
   - Complex widget trees may not be ready
   - No verification widgets are registered

3. **BUG: No error recovery**
   - If one step fails, entire test aborts
   - No partial success reporting

4. **EDGE CASE: Widget not found**
   - Throws exception, stops playback
   - No retry mechanism

5. **EDGE CASE: Navigation between screens**
   - Widgets on other screens not registered
   - Playback fails silently

6. **LIMITATION: No timeout handling**
   - Infinite wait if animation never completes
   - `waitForAnimations()` is just 100ms delay

### Recommendations

1. **Implement assertion execution:**
   ```dart
   case 'assertText':
     final node = _activeTestNodes[step.targetId];
     if (node?.currentText != step.value) {
       throw AssertionError(
         'Expected "${step.value}" but found "${node?.currentText}" for ${step.targetId}'
       );
     }
     break;
   case 'assertExists':
     if (!_activeTestNodes.containsKey(step.targetId)) {
       throw AssertionError('Widget "${step.targetId}" does not exist');
     }
     break;
   ```

2. **Add retry mechanism:**
   ```dart
   Future<void> _executeStepWithRetry(TestStep step, {int maxRetries = 3}) async {
     for (int i = 0; i < maxRetries; i++) {
       try {
         await _executeStep(step);
         return;
       } catch (e) {
         if (i == maxRetries - 1) rethrow;
         await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
       }
     }
   }
   ```

3. **Wait for widget registration:**
   ```dart
   Future<void> _waitForWidget(String id, {Duration timeout = const Duration(seconds: 5)}) async {
     final endTime = DateTime.now().add(timeout);
     while (!_activeTestNodes.containsKey(id)) {
       if (DateTime.now().isAfter(endTime)) {
         throw TimeoutException('Widget "$id" not found after $timeout');
       }
       await Future.delayed(const Duration(milliseconds: 50));
     }
   }
   ```

---

## 3. Widget Interception

### Implementation Overview

Widget interception wraps original widgets with recording-enabled versions that capture interactions.

**Supported Widgets:**

| Widget Type | Builder Location | Actions Captured |
|-------------|-----------------|------------------|
| `TextField` | `lib/recording_fields/text_field.dart` | `onChanged` → `enterText` |
| `TextFormField` | `lib/recording_fields/text_form_field.dart` | `onChanged` → `enterText` |
| `ElevatedButton` | `lib/recording_fields/button.dart` | `onPressed` → `trigger` |
| `TextButton` | `lib/recording_fields/button.dart` | `onPressed` → `trigger` |
| `OutlinedButton` | `lib/recording_fields/button.dart` | `onPressed` → `trigger` |
| `IconButton` | `lib/recording_fields/button.dart` | `onPressed` → `trigger` |
| `Checkbox` | `lib/recording_fields/checkbox.dart` | `onChanged` → `trigger` |
| `CheckboxListTile` | `lib/recording_fields/checkbox.dart` | `onChanged` → `trigger` |
| `Radio` | `lib/recording_fields/radio.dart` | `onChanged` → `trigger` |
| `RadioListTile` | `lib/recording_fields/radio.dart` | `onChanged` → `trigger` |
| `Switch` | `lib/recording_fields/switch.dart` | `onChanged` → `trigger` |
| `SwitchListTile` | `lib/recording_fields/switch.dart` | `onChanged` → `trigger` |
| `Slider` | `lib/recording_fields/slider.dart` | `onChanged` → `trigger` |
| `ListTile` | `lib/recording_fields/list_tile.dart` | `onTap` → `trigger` |
| `FloatingActionButton` | `lib/recording_fields/floating_action_button.dart` | `onPressed` → `trigger` |

### Edge Cases & Bugs

1. **BUG: Slider doesn't record value** (`lib/recording_fields/slider.dart:7-11`)
   ```dart
   onChanged: (value) async {
     await SelfTestManager().trigger(widget.id);  // No value captured!
     slider.onChanged?.call(value);
   },
   ```
   - Records `trigger` action but loses slider value
   - Playback cannot restore slider position

2. **BUG: Missing type annotation** (all builder files)
   ```dart
   Widget buildRecordingButton(Widget button, widget) {  // 'widget' untyped
   ```
   - No compile-time type checking
   - Potential runtime errors

3. **EDGE CASE: Disabled widgets**
   - Builders don't check `enabled` property
   - May record interactions on disabled widgets

4. **EDGE CASE: onLongPress not captured**
   - Buttons have `onLongPress` but it's not recorded
   - Only `onPressed`/`onTap` captured

5. **LIMITATION: DropdownButtonFormField not supported**
   - Intentionally excluded due to complexity
   - Common widget with no recording support

6. **LIMITATION: Gesture-based widgets not supported**
   - No support for `GestureDetector`, `Dismissible`, `Draggable`
   - Swipes and drags cannot be recorded

### Recommendations

1. **Capture slider value:**
   ```dart
   onChanged: (value) async {
     await SelfTestManager().enterText(widget.id, value.toString());
     slider.onChanged?.call(value);
   },
   ```

2. **Add type annotations:**
   ```dart
   Widget buildRecordingSlider(Slider slider, SelfTestableWidget widget) {
   ```

3. **Add DropdownButtonFormField support:**
   ```dart
   Widget buildRecordingDropdown<T>(DropdownButtonFormField<T> dropdown, SelfTestableWidget widget) {
     return DropdownButtonFormField<T>(
       // ... copy all properties
       onChanged: (value) async {
         await SelfTestManager().enterText(widget.id, value.toString());
         dropdown.onChanged?.call(value);
       },
     );
   }
   ```

4. **Support onLongPress:**
   ```dart
   onLongPress: () async {
     await SelfTestManager()._recordUserAction('longPress', widget.id);
     button.onLongPress?.call();
   },
   ```

---

## 4. Code Generation

### Implementation Overview

Two code generation systems exist:

1. **Annotation-based generation** (`lib/src/self_test_generator.dart`)
   - Uses `@SelfTestButton` and `@SelfTestInput` annotations
   - Generates `*TestController` classes via `build_runner`

2. **Runtime export** (`lib/src/test_code_generator.dart`)
   - Exports recorded scripts to Dart test files or JSON
   - Writes to device's documents directory

### Annotation Processing

```dart
// lib/annotations.dart
class SelfTestButton {
  final String id;
  const SelfTestButton(this.id);
}

class SelfTestInput {
  final String id;
  const SelfTestInput(this.id);
}
```

**Generated Output:**
```dart
class MyWidgetTestController {
  void tap_loginButton() {
    SelfTestManager().trigger('loginButton');
  }

  void enterText_emailInput(String text) {
    SelfTestManager().enterText('emailInput', text);
  }

  void expectExists_loginButton() {
    if (!SelfTestManager().activeTestNodes.containsKey('loginButton')) {
      throw Exception('TestNode with id "loginButton" does not exist');
    }
  }
}
```

### Runtime Export

**Dart Export:** (`lib/src/test_code_generator.dart:13-55`)
```dart
String generateTestCode(TestScript script, List<TestStep> steps) {
  // Generates flutter_test compatible code
}
```

**JSON Export:** (`lib/src/test_code_generator.dart:58-83`)
```dart
Future<void> exportToJson(TestScript script, List<TestStep> steps) async {
  // Exports to {appDocuments}/test_generated/*.json
}
```

### Edge Cases & Bugs

1. **BUG: Generated test requires manual app initialization** (`lib/src/test_code_generator.dart:25-26`)
   ```dart
   buffer.writeln("    // Initialize your app here if needed");
   ```
   - Generated tests won't run without manual setup
   - No widget pumping code generated

2. **BUG: No escaping of special characters** (`lib/src/test_code_generator.dart:38`)
   ```dart
   buffer.writeln("    await manager.enterText('${step.targetId}', '${step.value}');");
   ```
   - If `step.value` contains `'`, generated code breaks
   - SQL injection-like vulnerability in code generation

3. **EDGE CASE: Annotation on private members**
   - Generator doesn't handle `_privateMethod` correctly
   - May generate invalid method names

4. **LIMITATION: No import management**
   - Generated controllers don't import necessary files
   - Requires manual import additions

5. **LIMITATION: Export location not configurable**
   - Always writes to app documents
   - Cannot export to project test directory

### Recommendations

1. **Escape special characters:**
   ```dart
   String _escapeString(String value) {
     return value
       .replaceAll('\\', '\\\\')
       .replaceAll("'", "\\'")
       .replaceAll('\n', '\\n')
       .replaceAll('\r', '\\r');
   }

   buffer.writeln("    await manager.enterText('${step.targetId}', '${_escapeString(step.value!)}');");
   ```

2. **Generate complete test file:**
   ```dart
   String generateTestCode(TestScript script, List<TestStep> steps, {String? appImport}) {
     buffer.writeln("import 'package:flutter/material.dart';");
     buffer.writeln("import 'package:flutter_test/flutter_test.dart';");
     if (appImport != null) buffer.writeln("import '$appImport';");
     // ...
     buffer.writeln("  testWidgets('${script.name}', (tester) async {");
     buffer.writeln("    await tester.pumpWidget(MyApp());");
     buffer.writeln("    await tester.pumpAndSettle();");
   }
   ```

3. **Add export path configuration:**
   ```dart
   Future<void> exportToDart(TestScript script, List<TestStep> steps, {String? outputPath}) async {
     final dir = outputPath != null
       ? Directory(outputPath)
       : Directory('${(await getApplicationDocumentsDirectory()).path}/test_generated');
   }
   ```

---

## 5. UI Components

### Implementation Overview

The package provides overlay UI components for recording control.

**Components:**

| Component | Location | Purpose |
|-----------|----------|---------|
| Draggable FAB | `lib/self_test.dart:697-732` | Main menu button |
| Expandable Menu | `lib/self_test.dart:801-887` | START/VIEW actions |
| Stop FAB | `lib/self_test.dart:890-936` | Stop recording |
| Recording Indicator | `lib/self_test.dart:765-794` | Visual recording badge |
| Control Panel | `lib/self_test.dart:975-1251` | Script management |
| Name Dialog | `lib/self_test.dart:938-960` | Script naming |

### FAB Positioning

```dart
// lib/self_test.dart:664
Offset _fabPosition = Offset(300, 300);  // Default

// lib/self_test.dart:674-682
WidgetsBinding.instance.addPostFrameCallback((_) {
  final screenSize = MediaQuery.of(context).size;
  final newPosition = Offset(screenSize.width - 88, screenSize.height / 2 - 36);
  setState(() {
    _fabPosition = newPosition;
  });
});
```

### Edge Cases & Bugs

1. **BUG: FAB can be dragged off-screen** (`lib/self_test.dart:699-702`)
   ```dart
   onPanUpdate: (details) {
     setState(() {
       _fabPosition += details.delta;  // No bounds checking
     });
   },
   ```
   - FAB can be moved completely off-screen
   - User loses access to controls

2. **BUG: Deprecated `textScaleFactor`** (`lib/self_test.dart:1124`)
   ```dart
   Text('Assert', textScaleFactor: 0.7),  // Deprecated
   ```
   - Will break in future Flutter versions

3. **BUG: Control panel doesn't update on external changes**
   - If script deleted elsewhere, panel shows stale data
   - No reactive data binding

4. **EDGE CASE: Safe area not respected**
   - FAB may overlap with system UI (notch, home indicator)
   - No padding for safe areas

5. **EDGE CASE: Landscape orientation**
   - Initial position calculation doesn't account for orientation changes
   - FAB position may be off-screen after rotation

6. **LIMITATION: No keyboard avoidance**
   - Control panel may be obscured by keyboard
   - Name dialog doesn't scroll

### Recommendations

1. **Add FAB bounds checking:**
   ```dart
   void _updateFabPosition(Offset delta) {
     final size = MediaQuery.of(context).size;
     final padding = MediaQuery.of(context).padding;

     final newX = (_fabPosition.dx + delta.dx)
       .clamp(padding.left, size.width - 72 - padding.right);
     final newY = (_fabPosition.dy + delta.dy)
       .clamp(padding.top + 50, size.height - 100 - padding.bottom);

     setState(() => _fabPosition = Offset(newX, newY));
   }
   ```

2. **Replace deprecated API:**
   ```dart
   Text('Assert', textScaler: TextScaler.linear(0.7)),
   ```

3. **Add reactive updates:**
   ```dart
   class _ControlPanelState extends State<_ControlPanel> {
     late StreamSubscription _subscription;

     @override
     void initState() {
       super.initState();
       _subscription = widget.manager.scriptsStream.listen((_) => _loadScripts());
     }
   }
   ```

4. **Handle orientation changes:**
   ```dart
   @override
   void didChangeMetrics() {
     super.didChangeMetrics();
     _constrainFabPosition();
   }
   ```

---

## 6. Database Persistence

### Implementation Overview

Uses Hive for local NoSQL storage of test scripts and steps.

**Models:**
- `TestScript`: id, name, createdAt, lastRunStatus, lastRunDate
- `TestStep`: id, scriptId, order, action, targetId, value

**Storage Location:** `{appDocuments}/testScripts` and `{appDocuments}/testSteps`

### Database Operations

| Operation | Method | Location |
|-----------|--------|----------|
| Initialize | `initializeDatabase()` | `lib/self_test.dart:204-226` |
| Save script | `startRecording()` | `lib/self_test.dart:246-264` |
| Save step | `_recordUserAction()` | `lib/self_test.dart:275-297` |
| Delete | `deleteTestScript()` | `lib/self_test.dart:300-319` |
| Clear all | `clearDatabase()` | `lib/self_test.dart:323-328` |
| Query scripts | `getTestScripts()` | `lib/self_test.dart:331-334` |
| Query steps | `getTestSteps()` | `lib/self_test.dart:343-346` |

### Edge Cases & Bugs

1. **BUG: ID generation not persistent** (`lib/self_test.dart:218-219`)
   ```dart
   _nextScriptId = (_scriptBox!.values.isEmpty ? 0 : _scriptBox!.values.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1);
   ```
   - Recalculates max ID on every init
   - If box has gaps (deleted items), IDs may collide

2. **BUG: No transaction support**
   - Script and steps saved separately
   - Crash mid-save leaves orphaned records

3. **BUG: Steps query is O(n)** (`lib/self_test.dart:345`)
   ```dart
   return _stepBox!.values.where((s) => s.scriptId == scriptId).toList()
   ```
   - Scans all steps for every query
   - No indexing by scriptId

4. **EDGE CASE: Database corruption**
   - No integrity checks
   - Corrupted data causes silent failures

5. **EDGE CASE: Concurrent access**
   - Multiple instances could corrupt data
   - No file locking

6. **LIMITATION: No migration strategy**
   - Schema changes will break existing data
   - No version field in models

### Recommendations

1. **Use UUID for IDs:**
   ```dart
   import 'package:uuid/uuid.dart';

   final step = TestStep(
     id: const Uuid().v4(),
     // ...
   );
   ```

2. **Add transaction-like behavior:**
   ```dart
   Future<void> startRecording(String name) async {
     final script = TestScript(/*...*/);
     try {
       await _scriptBox!.put(script.id, script);
       _currentScriptId = script.id;
     } catch (e) {
       await _scriptBox!.delete(script.id);  // Rollback
       rethrow;
     }
   }
   ```

3. **Index steps by scriptId:**
   ```dart
   @HiveType(typeId: 1)
   class TestStep extends HiveObject {
     // Add compound key
     String get compoundKey => '${scriptId}_$order';
   }

   // Store with compound key
   await _stepBox!.put(step.compoundKey, step);
   ```

4. **Add data versioning:**
   ```dart
   @HiveField(10)
   int schemaVersion = 1;

   static Future<void> migrate(Box box) async {
     for (final item in box.values) {
       if (item.schemaVersion < currentVersion) {
         // Apply migrations
       }
     }
   }
   ```

---

## 7. Assertion System

### Implementation Overview

Assertions verify widget state during test execution.

**Assertion Types:**
| Type | Purpose | Status |
|------|---------|--------|
| `assertText` | Verify text content | Recorded but not executed |
| `assertExists` | Verify widget exists | Not implemented |

### Current Implementation

**Recording Assertion:** (`lib/self_test.dart:163-181`)
```dart
Future<void> addAssertion(String id) async {
  final node = _activeTestNodes[id];
  if (node != null) {
    final value = node.currentText ?? '';
    await _recordUserAction('assertText', id, value);
  }
  setRecordingMode(RecordingMode.viewing);
}
```

**Playback (BROKEN):** (`lib/self_test.dart:424-426`)
```dart
case 'assertText':
  break;  // Does nothing!
```

### Edge Cases & Bugs

1. **CRITICAL BUG: Assertions not executed**
   - Assertions recorded but skipped during playback
   - Tests appear to pass but don't verify anything

2. **BUG: Only text assertions supported**
   - No existence assertions during recording
   - No state assertions (checkbox checked, slider value)

3. **BUG: Assertion mode exits immediately** (`lib/self_test.dart:174`)
   ```dart
   setRecordingMode(RecordingMode.viewing);  // Exits after one assertion
   ```
   - Can only add one assertion at a time
   - Must re-enter assertion mode for each

4. **EDGE CASE: Null text handling**
   ```dart
   final value = node.currentText ?? '';  // Empty string for null
   ```
   - Cannot distinguish "no text" from "empty text"

5. **LIMITATION: No visual assertions**
   - Cannot verify colors, positions, visibility
   - Only text content

### Recommendations

1. **Execute assertions during playback:**
   ```dart
   case 'assertText':
     final node = _activeTestNodes[step.targetId];
     if (node == null) {
       _updateScriptStatus(scriptId, 'FAILED', 'Widget "${step.targetId}" not found');
       throw AssertionError('Widget not found');
     }
     if (node.currentText != step.value) {
       _updateScriptStatus(scriptId, 'FAILED',
         'Expected "${step.value}" but got "${node.currentText}"');
       throw AssertionError('Text mismatch');
     }
     break;

   case 'assertExists':
     if (!_activeTestNodes.containsKey(step.targetId)) {
       _updateScriptStatus(scriptId, 'FAILED', 'Widget "${step.targetId}" does not exist');
       throw AssertionError('Widget not found');
     }
     break;
   ```

2. **Add multiple assertion support:**
   ```dart
   Future<void> addAssertion(String id) async {
     // Record assertion but stay in assertion mode
     await _recordUserAction('assertText', id, node.currentText);
     // Don't change mode - let user add more
   }

   void finishAssertions() {
     setRecordingMode(RecordingMode.viewing);
   }
   ```

3. **Add more assertion types:**
   ```dart
   enum AssertionType {
     textEquals,
     textContains,
     exists,
     notExists,
     isEnabled,
     isDisabled,
     isVisible,
   }

   Future<void> addAssertion(String id, AssertionType type, [dynamic expected]) async {
     await _recordUserAction('assert_${type.name}', id, expected?.toString());
   }
   ```

---

## 8. Custom Widget Support

### Implementation Overview

Extensible builder registry allows third-party widget support.

**Registration:** (`lib/self_test.dart:119-122`)
```dart
void registerRecordingBuilder<T extends Widget>(
  Widget Function(Widget, SelfTestableWidget) builder
) {
  _recordingBuilders[T] = builder;
}
```

**Usage Example:** (`example/lib/main.dart:11`)
```dart
SelfTestManager().registerRecordingBuilder<CustomRatingWidget>(
  buildRecordingCustomRatingWidget
);
```

### Custom Builder Pattern

The `CustomRatingWidget` example (`example/lib/custom_rating_builder.dart`) shows best practices:

1. Create wrapper widget that intercepts interactions
2. Generate sub-IDs for child elements (`${widget.id}_star_1`)
3. Call original callbacks after recording
4. Use `SelfTestableWidget` for nested testable elements

### Edge Cases & Bugs

1. **BUG: No builder inheritance**
   - Cannot extend built-in builders
   - Must copy all property mappings

2. **BUG: Type matching is exact** (`lib/self_test.dart:125-127`)
   ```dart
   Widget Function(Widget, SelfTestableWidget)? getRecordingBuilder(Type widgetType) {
     return _recordingBuilders[widgetType];
   }
   ```
   - Subclasses don't match parent builders
   - `CustomElevatedButton extends ElevatedButton` won't use button builder

3. **EDGE CASE: Builder throws exception**
   - No try-catch around builder invocation
   - Crashes entire widget tree

4. **EDGE CASE: Widget rebuilds with different type**
   - AnimatedSwitcher may swap widget types
   - Builder lookup happens on each build

5. **LIMITATION: No builder priority**
   - Cannot override built-in builders cleanly
   - Last registered wins

### Recommendations

1. **Add inheritance-aware lookup:**
   ```dart
   Widget Function(Widget, SelfTestableWidget)? getRecordingBuilder(Type widgetType) {
     // Direct match first
     if (_recordingBuilders.containsKey(widgetType)) {
       return _recordingBuilders[widgetType];
     }

     // Check for parent type matches
     for (final entry in _recordingBuilders.entries) {
       if (_isSubtypeOf(widgetType, entry.key)) {
         return entry.value;
       }
     }
     return null;
   }
   ```

2. **Add error handling:**
   ```dart
   Widget _applyBuilder(Widget child, SelfTestableWidget widget) {
     final builder = getRecordingBuilder(child.runtimeType);
     if (builder == null) return child;

     try {
       return builder(child, widget);
     } catch (e, stack) {
       _printError('Builder failed for ${child.runtimeType}: $e');
       debugPrint('$stack');
       return child;  // Fall back to original
     }
   }
   ```

3. **Add builder documentation:**
   ```dart
   /// Registers a custom recording builder for a widget type.
   ///
   /// Example:
   /// ```dart
   /// SelfTestManager().registerRecordingBuilder<MyWidget>(
   ///   (child, selfTestWidget) {
   ///     final myWidget = child as MyWidget;
   ///     return MyWidget(
   ///       onTap: () async {
   ///         await SelfTestManager().trigger(selfTestWidget.id);
   ///         myWidget.onTap?.call();
   ///       },
   ///     );
   ///   },
   /// );
   /// ```
   void registerRecordingBuilder<T extends Widget>(...) {
   ```

---

## Summary of Critical Issues

| Issue | Severity | Component | Fix Effort |
|-------|----------|-----------|------------|
| Assertions not executed | Critical | Playback | Low |
| Slider value not captured | High | Widget Interception | Low |
| FAB can be dragged off-screen | Medium | UI Components | Low |
| No error recovery in playback | Medium | Playback | Medium |
| O(n) step queries | Medium | Database | Medium |
| No transaction support | Medium | Database | High |
| Deprecated textScaleFactor | Low | UI Components | Low |
| Missing type annotations | Low | Widget Interception | Low |

---

## Conclusion

The `self_test` package provides a solid foundation for in-app testing but has several functionality gaps:

1. **Critical:** Assertions are recorded but never executed during playback
2. **High:** Slider values are lost during recording
3. **Medium:** Error handling and recovery are minimal

Priority fixes should focus on making assertions work, capturing all widget values, and adding proper error handling for production readiness.

---

*Review generated by functionality analysis on 2026-01-12*
