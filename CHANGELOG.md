## 0.2.0

### Added

- **Universal locators.** `SelfTestLocator` finds a widget by the text it
  paints, its `ValueKey`, its tooltip, its semantics label, its type, or a
  `SelfTestableWidget` id, with `.at(n)` to pick between duplicates. Resolution
  walks the element tree, so an app needs no wrapper, no annotation and no
  generated code to be driven. Locators are JSON in both directions, which is
  how the bridge and the MCP server will carry them.
- **Real pointer events.** `tap`, `doubleTap`, `longPress`, `dragFrom` and
  `scrollBy` dispatch through `GestureBinding.handlePointerEvent`, the same
  entry point the engine uses. Hit testing runs, so a widget behind a dialog is
  not reachable and a disabled button swallows the tap. Before this, a driven
  tap invoked the app's callback directly and therefore passed on buttons the
  user could not even reach.
- **Real text entry.** `typeInto` goes through
  `EditableTextState.updateEditingValue`, the method the soft keyboard calls,
  so input formatters run, `onChanged` fires and a `TextFormField` validates
  what was actually typed. It also resolves a field from the label beside it,
  which is how a person describes it.
- `describeScreen()` returns every actionable widget on screen with its type,
  text, tooltip, rect and enabled state, for an agent deciding what to do next.
- `exists` and `isVisible` are separate questions. A list keeps items built
  after they scroll away, and tapping one of those would land on whatever is
  drawn at those coordinates now, so a driven gesture refuses instead.
- `useClock` lets a widget test hand the driver `tester.pump`, which is what a
  long press needs to be held rather than silently degrading to a tap.

### Fixed

- A recorded tap fired the app's handler twice. The recording wrappers called
  the driving API to record the action, which invoked the wrapper's callback,
  and then called the child's callback as well. Recording now records, and the
  child's own handler runs once; `SelfTestableWidget.onTap` is a fallback for a
  child that carries none.
- Driving a widget wrapped in `SelfTestableWidget` with no matching recording
  builder recursed until the stack ran out, because the fallback wrapper called
  `trigger` from inside the tap it was handling.
- Under `integration_test`, driven gestures did nothing at all and said
  nothing: that binding drops pointer events that did not come from a
  `WidgetTester`. The driver now detects it and names the one line that fixes
  it, `binding.shouldPropagateDevicePointerEvents = true`.

### Breaking

- Minimum Flutter is now 3.35.0 (Dart 3.9.0), raised from a declared 3.24.0
  that was never true. `lib/recording_fields` passes widget properties that
  only exist from 3.35 (`Switch.activeThumbColor` and friends), so installing
  0.1.0 on Flutter 3.24 produced eight compile errors inside this package.
  3.35.0 is the oldest version the whole suite is verified against, and CI now
  runs against it on every push so the number stays honest.

- The `build_runner` generator has moved to its own package, `self_test_gen`.
  Add it to `dev_dependencies` to keep using annotations. In exchange, the core
  package no longer depends on `analyzer`, `source_gen`, `build` or
  `dart_style`, so none of them reach your app any more. Its only dependencies
  are Flutter and `meta`.
- Generated controller methods are camelCase, matching what the README always
  documented: `tapLoginBtn()` rather than `tap_login_btn()`. A private class
  such as `_LoginFormState` now generates `LoginFormStateTestController`, so it
  can be referenced from a test.
- Do not write a `part` directive for the generated file and do not import it
  from its own source. The builder emits a standalone library; import it from
  your test. Importing it from its own source leaves that library unresolvable,
  and the generator then finds no annotations at all.
- Recording persistence is an interface. `RecordingStore` and
  `InMemoryRecordingStore` replace `DatabaseService`, and `hive_ce` and
  `path_provider` are gone. Pass your own implementation to
  `SelfTestManager().useRecordingStore()` for recordings that survive a
  restart. `initializeDatabase` and `clearDatabase` are deprecated aliases for
  `initializeRecordingStore` and `clearRecordings`.
- The recording model formerly called `TestStep` is now `RecordedStep`.
  `TestStep` remains the scenario command type it always was in the public API.
- `TestCodeGenerator` returns strings instead of writing files, so the caller
  decides where generated code goes.
- `WidgetCatalog` and `FlowDiscovery` are deprecated. Both only ever returned
  an empty map.

### Fixed

- Annotations on class members are found. `LibraryReader.annotatedWith` only
  visits top-level declarations, so annotating a handler, which is what the
  README asks for, previously generated nothing at all.
- Recorded values are escaped when generating test code. A value containing a
  quote, a dollar sign or a newline produced source that would not compile, or
  that picked up an unintended interpolation.
- Two `assertText` steps in one recording no longer declare the same local
  twice, which made the generated file fail to compile.
- `SelfTestRoot` no longer draws its recording controls in a widget test. They
  are a live overlay, so `pumpAndSettle` on a wrapped app never returned. The
  new `showControls` flag makes the choice explicit.
- `ScreenshotBoundary` installs a real `RepaintBoundary` and registers it with
  the manager. It was a `StatelessWidget` that returned its child, so capture
  photographed whichever boundary happened to come first in the tree, or
  nothing.

- `self_test_gen` moved to `source_gen` 2.x and `analyzer` 7.x. Its output is
  unchanged; the old pins held it to a `dart_style` that predates the Dart 3.7
  formatter, so generated code could not match `dart format`.

### Added

- Recording, replay and test code generation, merged in from the
  `feature/visual_tests` line: a recording control panel, a recording-field
  registry, and `TestCodeGenerator`.
- A DevTools extension and a standalone inspector under `packages/`.
- `SelfTestManager.captureScreenshotBytes()` for platform-neutral capture, and
  `clearScreenshotKey()` so a disposed boundary cannot leave a stale key.
- MIT license, replacing the previous custom terms.
- CI covering every package, including a job that runs the README quickstart.

## 0.1.0

- Direct callback invocation for automated testing
- Code generation with `build_runner` and annotations
- `SelfTestableWidget` wrapper for manual setup
- `TestScenario` and `TestStep` for multi-step test flows
- Text assertion support for input field validation
- Screenshot capture during test execution
- Memory-safe test node management
- Runtime testing in debug/profile builds
- Test mode support for unit/integration tests
- Generated test controllers with full type safety

## 0.0.1

- Initial experimental release
