# Architecture Review: self_test Flutter Package

**Review Date:** 2026-01-12
**Package Version:** 0.0.1
**Reviewer:** Claude (Architecture Analysis)

---

## Executive Summary

The `self_test` package is a Flutter testing framework that enables automated regression testing through direct callback invocation. The architecture is functional but has several areas that could benefit from refactoring to improve maintainability, testability, and extensibility.

**Overall Assessment:** The package demonstrates solid foundational concepts but suffers from a monolithic main file, inconsistent patterns, and gaps in error handling and test coverage.

---

## 1. Code Organization

### Current State

The project follows a basic Flutter package structure:

```
lib/
├── self_test.dart              (1,252 lines - main library)
├── annotations.dart            (12 lines)
├── builder.dart                (build_runner config)
├── src/
│   ├── models.dart             (81 lines)
│   ├── models.g.dart           (generated)
│   ├── test_code_generator.dart (106 lines)
│   └── self_test_generator.dart (117 lines)
└── recording_fields/           (10 widget builders)
```

### Issues Identified

| Issue | Location | Severity |
|-------|----------|----------|
| **Monolithic main file** | `lib/self_test.dart:1-1252` | High |
| **Mixed concerns** | `SelfTestManager` handles state, recording, UI, and database | High |
| **Inconsistent file naming** | `recording_fields/` vs `src/` conventions | Low |
| **No interface layer** | Direct coupling between components | Medium |

### Recommendations

1. **Split `self_test.dart` into focused modules:**
   ```
   lib/
   ├── self_test.dart              (exports only)
   ├── src/
   │   ├── core/
   │   │   ├── manager.dart        (SelfTestManager)
   │   │   ├── test_node.dart      (TestNode class)
   │   │   └── recording_mode.dart (enum)
   │   ├── widgets/
   │   │   ├── self_testable_widget.dart
   │   │   ├── self_test_root.dart
   │   │   └── control_panel.dart
   │   ├── persistence/
   │   │   ├── models.dart
   │   │   └── database_service.dart
   │   └── recording_fields/
   ```

2. **Extract `_ControlPanel` to separate file** (`lib/self_test.dart:975-1251`)

3. **Create a `DatabaseService` interface** to decouple from Hive implementation

---

## 2. Design Patterns

### Current State

| Pattern | Implementation | Location |
|---------|---------------|----------|
| Singleton | `SelfTestManager` | `lib/self_test.dart:45-506` |
| Registry | Recording builders | `lib/self_test.dart:93` |
| Decorator | `SelfTestableWidget` wraps children | `lib/self_test.dart:509-646` |
| Factory | Limited use | N/A |

### Issues Identified

1. **Singleton Anti-pattern Concerns** (`lib/self_test.dart:46-49`)
   - Makes unit testing difficult
   - Hidden global state
   - No dependency injection support

   ```dart
   // Current implementation
   static final SelfTestManager _instance = SelfTestManager._internal();
   factory SelfTestManager() => _instance;
   ```

2. **Missing Null Safety Patterns** (`lib/self_test.dart:83-86`)
   ```dart
   Box<TestScript>? _scriptBox;
   Box<TestStep>? _stepBox;
   // Requires null checks throughout codebase
   ```

3. **Type Safety Issues in Recording Builders** (`lib/recording_fields/button.dart:4`)
   ```dart
   Widget buildRecordingButton(Widget button, widget) {
   // 'widget' has no type annotation
   ```

### Recommendations

1. **Consider Dependency Injection pattern:**
   ```dart
   class SelfTestManager {
     static SelfTestManager? _instance;
     final DatabaseService _database;

     SelfTestManager._internal(this._database);

     factory SelfTestManager({DatabaseService? database}) {
       return _instance ??= SelfTestManager._internal(
         database ?? HiveDatabaseService()
       );
     }

     // For testing
     @visibleForTesting
     static void reset() => _instance = null;
   }
   ```

2. **Add type annotations to all recording builders:**
   ```dart
   Widget buildRecordingButton(Widget button, SelfTestableWidget widget) {
   ```

3. **Use late initialization for database boxes:**
   ```dart
   late final Box<TestScript> _scriptBox;
   late final Box<TestStep> _stepBox;
   bool _isInitialized = false;
   ```

---

## 3. Extensibility

### Current State

The package provides good extensibility through the recording builder registry:

```dart
// lib/self_test.dart:119-122
void registerRecordingBuilder<T extends Widget>(
  Widget Function(Widget, SelfTestableWidget) builder
) {
  _recordingBuilders[T] = builder;
}
```

### Strengths

- Custom widget support via `registerRecordingBuilder<T>()`
- Clear builder pattern for widget interception
- Example implementation in `example/lib/custom_rating_builder.dart`

### Issues Identified

1. **No builder inheritance** - Cannot extend existing builders
2. **No middleware/interceptor pattern** for cross-cutting concerns
3. **Limited action types** - Only `trigger`, `enterText`, `assertText`, `assertExists`

### Recommendations

1. **Add builder composition:**
   ```dart
   void registerRecordingBuilder<T extends Widget>(
     Widget Function(Widget, SelfTestableWidget) builder, {
     bool override = false,
   });

   Widget Function(Widget, SelfTestableWidget)? getRecordingBuilder(
     Type widgetType, {
     bool includeInherited = true,
   });
   ```

2. **Add action extension point:**
   ```dart
   typedef ActionHandler = Future<void> Function(String targetId, String? value);

   void registerAction(String actionName, ActionHandler handler);
   ```

3. **Add lifecycle hooks:**
   ```dart
   void addRecordingStartHook(VoidCallback callback);
   void addRecordingStopHook(VoidCallback callback);
   void addStepRecordedHook(Function(TestStep) callback);
   ```

---

## 4. State Management

### Current State

State is managed through a combination of:
- Boolean flags in `SelfTestManager`
- `RecordingMode` enum
- StatefulWidget local state

| State Variable | Location | Purpose |
|---------------|----------|---------|
| `_isSelfTestModeActive` | `lib/self_test.dart:75` | Global enable/disable |
| `_isTestMode` | `lib/self_test.dart:76` | Testing environment flag |
| `_recordingMode` | `lib/self_test.dart:89` | Current UI mode |
| `_isRecordingModeActive` | `lib/self_test.dart:81` | Recording state |
| `_currentScriptId` | `lib/self_test.dart:82` | Active recording session |

### Issues Identified

1. **Redundant state flags** (`lib/self_test.dart:75-89`)
   - `_isRecordingModeActive` duplicates `_recordingMode == RecordingMode.recording`

2. **No state change notifications**
   - Components poll state rather than react to changes
   - `restartWidgetTree()` is a heavy-handed approach

3. **State scattered across multiple variables**
   - Hard to understand current system state
   - Race conditions possible

### Recommendations

1. **Consolidate state into immutable state object:**
   ```dart
   @immutable
   class SelfTestState {
     final bool isActive;
     final bool isTestMode;
     final RecordingMode recordingMode;
     final int? currentScriptId;
     final TestScript? viewingScript;

     const SelfTestState({...});

     SelfTestState copyWith({...});
   }
   ```

2. **Add ChangeNotifier or Stream-based state updates:**
   ```dart
   class SelfTestManager extends ChangeNotifier {
     SelfTestState _state = const SelfTestState();

     SelfTestState get state => _state;

     void updateState(SelfTestState Function(SelfTestState) updater) {
       _state = updater(_state);
       notifyListeners();
     }
   }
   ```

3. **Remove `_isRecordingModeActive`** - derive from `_recordingMode`

---

## 5. Error Handling

### Current State

Error handling is inconsistent:

| Approach | Locations | Consistency |
|----------|-----------|-------------|
| try-catch with rethrow | `lib/self_test.dart:163-180, 204-226` | Partial |
| debugPrint errors | Throughout | Yes |
| Silent failures | `lib/self_test.dart:494-500` | Problematic |

### Issues Identified

1. **Silent error swallowing** (`lib/self_test.dart:493-500`)
   ```dart
   } catch (e3) {
     debugPrint('[SelfTest] All scrolling approaches failed for "$id": $e3');
     // Error is swallowed, no indication to caller
   }
   ```

2. **No error recovery strategies**
   - Database failures leave system in undefined state
   - UI errors can crash the overlay

3. **Missing validation** (`lib/self_test.dart:232-234`)
   ```dart
   void registerTestNode(TestNode node) {
     _activeTestNodes[node.id] = node;
     // No validation of node.id uniqueness or format
   }
   ```

4. **Exceptions thrown without custom types** (`lib/self_test.dart:362`)
   ```dart
   throw Exception('TestNode with id "$id" not found...');
   // Generic Exception, hard to catch specifically
   ```

### Recommendations

1. **Create custom exception hierarchy:**
   ```dart
   abstract class SelfTestException implements Exception {
     final String message;
     const SelfTestException(this.message);
   }

   class NodeNotFoundException extends SelfTestException {...}
   class DatabaseException extends SelfTestException {...}
   class RecordingException extends SelfTestException {...}
   ```

2. **Add validation layer:**
   ```dart
   void registerTestNode(TestNode node) {
     if (node.id.isEmpty) {
       throw ArgumentError('TestNode id cannot be empty');
     }
     if (_activeTestNodes.containsKey(node.id)) {
       _printWarning('Overwriting existing node: ${node.id}');
     }
     _activeTestNodes[node.id] = node;
   }
   ```

3. **Add Result type for fallible operations:**
   ```dart
   sealed class Result<T> {
     const Result();
   }
   class Success<T> extends Result<T> {
     final T value;
     const Success(this.value);
   }
   class Failure<T> extends Result<T> {
     final SelfTestException error;
     const Failure(this.error);
   }
   ```

---

## 6. Testing Coverage

### Current State

| Test File | Coverage Area | Test Count |
|-----------|--------------|------------|
| `test/self_test_test.dart` | Basic manager ops | 3 |
| `test/self_test_manager_test.dart` | Manager + custom builders | 3 |
| `test/test_code_generator_test.dart` | Code generation | 1 |
| `test/generated_controller_test.dart` | Generated controllers | Unknown |

**Total Unit Tests:** ~7 tests

### Issues Identified

1. **Low test coverage** - Only ~7 tests for 1,500+ lines of code
2. **No widget tests** for `SelfTestableWidget` or `SelfTestRoot`
3. **No integration tests** for recording/playback flow
4. **No edge case testing** (empty scripts, invalid IDs, concurrent operations)
5. **Database not tested** - Uses mock that bypasses Hive

### Recommendations

1. **Add widget tests:**
   ```dart
   testWidgets('SelfTestableWidget registers on mount', (tester) async {
     await tester.pumpWidget(
       MaterialApp(
         home: SelfTestableWidget(
           id: 'test_widget',
           onTap: () {},
           child: ElevatedButton(onPressed: () {}, child: Text('Test')),
         ),
       ),
     );
     // Verify registration
   });
   ```

2. **Add integration tests for recording flow:**
   ```dart
   test('full recording and playback cycle', () async {
     final manager = SelfTestManager();
     await manager.initializeDatabase();

     await manager.startRecording('Test Script');
     await manager.trigger('button_1');
     await manager.enterText('input_1', 'hello');
     manager.stopRecording();

     final scripts = manager.getTestScripts();
     expect(scripts.length, 1);

     final steps = manager.getTestSteps(scripts.first.id);
     expect(steps.length, 2);
   });
   ```

3. **Target 80% code coverage** with focus on:
   - `SelfTestManager` public methods
   - `SelfTestableWidget` build logic
   - Recording builders
   - Error paths

---

## 7. Performance

### Current State

| Concern | Location | Impact |
|---------|----------|--------|
| Widget rebuild on mode change | `lib/self_test.dart:187-201` | Medium |
| Synchronous database reads | `lib/self_test.dart:331-346` | Low |
| No builder caching | `lib/self_test.dart:623-626` | Low |

### Issues Identified

1. **Full widget tree rebuild** (`lib/self_test.dart:187-201`)
   ```dart
   void restartWidgetTree() {
     _rebuildCounter++;
     // Forces entire tree rebuild via setState
     (rootKey!.currentState as dynamic).setState(() {});
   }
   ```
   - Called on every mode change
   - Expensive for large widget trees

2. **Map lookup on every build** (`lib/self_test.dart:623`)
   ```dart
   final registeredBuilder = manager.getRecordingBuilder(child.runtimeType);
   ```
   - Called during build phase
   - Repeated for same widget types

3. **Linear search for steps** (`lib/self_test.dart:345`)
   ```dart
   return _stepBox!.values.where((s) => s.scriptId == scriptId).toList()
     ..sort((a, b) => a.order.compareTo(b.order));
   ```
   - O(n) filter + O(n log n) sort on every access

### Recommendations

1. **Use InheritedWidget for state propagation:**
   ```dart
   class SelfTestScope extends InheritedWidget {
     final SelfTestState state;

     static SelfTestState of(BuildContext context) {
       return context.dependOnInheritedWidgetOfExactType<SelfTestScope>()!.state;
     }

     @override
     bool updateShouldNotify(SelfTestScope oldWidget) {
       return state != oldWidget.state;
     }
   }
   ```

2. **Cache builder lookups:**
   ```dart
   final Map<Type, Widget Function(Widget, SelfTestableWidget)?> _builderCache = {};

   Widget Function(Widget, SelfTestableWidget)? getCachedBuilder(Type type) {
     return _builderCache.putIfAbsent(type, () => _recordingBuilders[type]);
   }
   ```

3. **Index steps by scriptId:**
   ```dart
   final Map<int, List<TestStep>> _stepsByScript = {};

   void _rebuildStepIndex() {
     _stepsByScript.clear();
     for (final step in _stepBox!.values) {
       _stepsByScript.putIfAbsent(step.scriptId, () => []).add(step);
     }
     for (final list in _stepsByScript.values) {
       list.sort((a, b) => a.order.compareTo(b.order));
     }
   }
   ```

---

## 8. API Design

### Current State

The public API consists of:

| Class/Function | Purpose | Usability |
|----------------|---------|-----------|
| `SelfTestManager` | Core manager | Good |
| `SelfTestableWidget` | Widget wrapper | Good |
| `SelfTestRoot` | App root wrapper | Good |
| `TestNode` | Node data class | Good |
| `RecordingMode` | Mode enum | Good |
| `registerRecordingBuilder<T>()` | Extension point | Good |
| Annotations | Code gen markers | Good |

### Strengths

- Simple setup: wrap app with `SelfTestRoot`
- Intuitive widget wrapping with `SelfTestableWidget`
- Good extensibility with `registerRecordingBuilder`
- Clear separation between recording and playback

### Issues Identified

1. **Inconsistent async/sync methods** (`lib/self_test.dart:331-340`)
   ```dart
   List<TestScript> getTestScripts() {...}  // sync
   Future<List<TestScript>> getTestScriptsAsync() {...}  // async
   ```

2. **Mutable `TestNode.currentText`** (`lib/self_test.dart:33`)
   ```dart
   String? currentText; // For text assertions
   // Mutated externally, violates encapsulation
   ```

3. **Boolean trap in API** (`lib/self_test.dart:113-115`)
   ```dart
   static void setVerboseLogging(bool enabled) {
     _verboseLogging = enabled;
   }
   ```

4. **Magic strings for actions** (`lib/self_test.dart:415-429`)
   ```dart
   case 'trigger':
   case 'enterText':
   case 'assertText':
   ```

### Recommendations

1. **Standardize on async-first API:**
   ```dart
   Future<List<TestScript>> getTestScripts() async {
     await _ensureInitialized();
     return _scriptBox!.values.toList();
   }
   ```

2. **Make TestNode immutable:**
   ```dart
   @immutable
   class TestNode {
     final String id;
     final VoidCallback? onTap;
     final ValueSetter<String>? onTextChange;
     final String? currentText;

     const TestNode({...});

     TestNode withText(String text) => TestNode(
       id: id,
       onTap: onTap,
       onTextChange: onTextChange,
       currentText: text,
     );
   }
   ```

3. **Use enum for actions:**
   ```dart
   enum TestAction {
     trigger,
     enterText,
     assertText,
     assertExists;

     static TestAction fromString(String value) =>
       TestAction.values.firstWhere((a) => a.name == value);
   }
   ```

4. **Use named parameters for booleans:**
   ```dart
   static void configureLogging({bool verbose = false, bool colorized = true});
   ```

---

## Priority Matrix

| Issue | Severity | Effort | Priority |
|-------|----------|--------|----------|
| Split monolithic `self_test.dart` | High | High | 1 |
| Add custom exception types | High | Low | 2 |
| Improve test coverage | High | Medium | 3 |
| Consolidate state management | Medium | Medium | 4 |
| Add type annotations to builders | Medium | Low | 5 |
| Performance optimizations | Low | Medium | 6 |
| API consistency improvements | Low | Low | 7 |

---

## Conclusion

The `self_test` package has a solid conceptual foundation with good extensibility patterns. The main areas requiring attention are:

1. **Code organization** - The 1,252-line main file should be split into focused modules
2. **Error handling** - Needs custom exceptions and consistent error propagation
3. **Test coverage** - Current ~7 tests are insufficient for production readiness
4. **State management** - Consolidate scattered state flags into cohesive state object

Addressing these issues will significantly improve maintainability and reliability of the package.

---

*Review generated by architectural analysis on 2026-01-12*
