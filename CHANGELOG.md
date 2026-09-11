## 0.2.0

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
- **The bridge no longer depends on go_router.** `SelfTestBridge` took a
  `GoRouter? router`, so a testing bridge that was meant to drive any Flutter
  app only navigated in apps that had picked one particular routing package.
  The parameter is now `BridgeNavigator? navigator`, an interface this package
  owns, with four members the bridge actually needs. Pass
  `NavigatorStateBridgeNavigator(yourNavigatorKey)` and it works in any app;
  a go_router app implements the interface in ten lines, and
  `BridgeNavigator`'s doc comment gives that adapter in full.

  The parameter was renamed rather than kept as `router`, because it no longer
  takes a router. `bridge.router` is now `bridge.navigator`.

  Navigation commands that used to report `{"success": true}` while doing
  nothing, because no router was configured, now return an error saying so.
  `getFlowGraph` returns the routes the navigator reports rather than the empty
  map deprecated `FlowDiscovery` handed back.

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
- **A recording keeps how each widget was addressed**, not just an id.
  `RecordedStep.locator` carries the locator, so a session recorded on an app
  with no wrappers replays. A step recorded before this, or against an id,
  still replays through the id path.
- `recordAssertion` records an assertion against a locator, so a recorded
  session can check something. Recording only actions produces a generated
  test that drives the app and asserts nothing, which passes on a blank screen.
- The code generator emits the locator API and a `testWidgets` body that pumps
  between steps, because a driven tap is a real pointer event and nothing it
  changes is visible until the next frame. It also pumps the app for you when
  given an `appExpression`.
- `useClock` lets a widget test hand the driver `tester.pump`, which is what a
  long press needs to be held rather than silently degrading to a tap.
- **The bridge speaks locators.** Every command that named a widget by its
  registered id now also takes a `locator` object, and prefers it when both are
  sent:

  ```json
  {"by": "text|key|id|semanticsLabel|type|tooltip",
   "value": "Sign in", "exact": true, "index": 0}
  ```

  `tap`, `doubleTap`, `longPress`, `type`/`enterText`, `submit`, `drag`,
  `scroll` and `clear` route through the manager's locator API when given one,
  so they reach widgets the app never registered. `describeScreen`, `find`,
  `exists`, `isVisible` and `readText` are new and take a locator only;
  `describeScreen` answers with `WidgetSnapshot` JSON. `submit` is a new
  command.

  A malformed locator is answered with what is wrong with it - an unknown
  `by`, a non-string `value`, a negative `index` - rather than a cast error
  from three layers down.


- Recording, replay and test code generation, merged in from the
  `feature/visual_tests` line: a recording control panel, a recording-field
  registry, and `TestCodeGenerator`.
- A DevTools extension and a standalone inspector under `packages/`.
- `SelfTestManager.captureScreenshotBytes()` for platform-neutral capture, and
  `clearScreenshotKey()` so a disposed boundary cannot leave a stale key.
- MIT license, replacing the previous custom terms.
- CI covering every package, including a job that runs the README quickstart.

### Security

- **self_test is inert in a release build.** Every action and every query is
  gated: no taps, no typing, no screenshots, no recording, no reading the
  widget tree, and no register of what is on screen is even built. A device
  farm that means to drive a signed build calls
  `SelfTestManager.enableInReleaseBuilds()` deliberately. Nothing flips it by
  accident, and `debugSimulateReleaseBuild` exists so the guard is covered by
  tests rather than asserted in a comment.
- **The bridge binds to loopback**, not to every network interface. Until now
  it was `InternetAddress.anyIPv4`, so anyone on the same wifi could drive a
  colleague's debug build: read the tree, tap, type, photograph the screen.
  Pass `host: InternetAddress.anyIPv4` to reach it from a real device, and it
  says out loud what that means.
- **The bridge requires a token.** One is generated per instance and printed
  at startup, or the app supplies its own. A connection without it, or with a
  wrong one, gets an HTTP 403 before the WebSocket upgrade. The comparison is
  constant time.
- **The bridge refuses to start in a release build** unless
  `allowInReleaseBuilds: true` is passed, because a bridge in a shipped app is
  a remote control for it.

### Fixed

- **The bridge answered "done" before it had done anything.** `tap`, `type` and
  eleven other commands called `SelfTestManager.trigger` and `enterText`
  without awaiting them. Those methods became async when they started
  dispatching real pointer events, so an agent that tapped and then read the
  screen was told the tap was finished and shown the screen from before it.
  `unawaited_futures` is now enforced in that package so it cannot come back.
- Time-travel capture-on-interaction and test-step recording were implemented
  and then never called, so both recorded nothing. Recorded comments were
  dropped between the command and the step.
- The widget rebuild profiler reported every rebuild as "Frame sample" instead
  of the reason it had worked out.
- Starting memory profiling twice abandoned the first timer, leaving two
  running and interleaving their samples.

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

- **The generator could not run on current Flutter at all.** `self_test_gen`
  pinned `analyzer` below 9, and analyzer 7 throws
  `Missing implementation of visitDotShorthandPropertyAccess` while
  serialising any library that reaches the Flutter framework, which on Dart
  3.12 and later is every library. `build_runner build` therefore worked on
  the declared floor, Flutter 3.35, and crashed on Flutter 3.47. It now takes
  `analyzer >=8.1.1 <15.0.0`, `source_gen ^4.2.4` and `build >=3.0.2 <5.0.0`,
  which resolves to analyzer 10 on Dart 3.9 and analyzer 14 on Dart 3.13.
  Generated output is byte-identical under both. The quickstart CI job now
  runs on both ends of the range rather than on one of them, which is why
  nothing caught this.
- The core package no longer publishes the rest of the monorepo inside itself.
  A `.pubignore` keeps the bridge, the generator, the inspector and the MCP
  server's Node tree out of the `self_test` archive, and keeps
  `extension/devtools/build` in, because that is how DevTools finds the panel.

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
