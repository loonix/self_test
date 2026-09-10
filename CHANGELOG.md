## 0.2.0

### Breaking

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
