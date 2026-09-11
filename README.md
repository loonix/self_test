# self_test

[![pub package](https://img.shields.io/pub/v/self_test.svg)](https://pub.dev/packages/self_test)

Automated regression testing for Flutter, driven from outside the app with
**real pointer events**. Widgets are found by what is on screen (their text,
key, tooltip or semantics label), so an app does not have to be modified,
wrapped or annotated before it can be tested.

**🤖 AI-Powered Testing:** Pair with [self_test_mcp](packages/self_test_mcp) to enable Claude and other AI agents to test your Flutter apps with Playwright feature parity - works on iOS, Android, Web, and Desktop!

## Features

### Core Testing
- **Universal locators** - Address a widget by the text it paints, its key, its tooltip, its semantics label or its type. No wrapper, no annotation, no change to the app
- **Real pointer events** - Taps, drags, scrolls and long presses go through `GestureBinding`, so hit testing runs and a button behind a dialog is not reachable
- **Real text entry** - Typing goes through the same method the soft keyboard calls, so input formatters run and a form validates what was actually typed
- **Runtime Testing** - Run tests in live app environments without external test frameworks
- **Text Assertions** - Built-in text validation for input fields
- **Memory Safe** - Automatic registration/unregistration prevents memory leaks
- **Hot Restart Compatible** - Works seamlessly with Flutter's hot restart
- **Test Scenarios** - Define and run multi-step test scenarios with `TestScenario`

### AI-Powered Testing (with MCP)
- **60+ Playwright-Equivalent Tools** - Full feature parity with Playwright browser testing
- **State Management Inspection** - Inspect and modify Riverpod, Bloc, and Provider state
- **Network Mocking** - Mock HTTP responses, block requests, monitor traffic
- **Visual Regression** - Golden file comparison for UI testing
- **Platform Mocking** - Mock GPS, permissions, platform channels, sensors
- **Cross-Platform** - Works on iOS, Android, Web (with or without bridge), Desktop
- **Bridgeless Web Testing** - Test any Flutter web app via Playwright + semantics tree

## Installation

### Core Package Only

Add to your `pubspec.yaml`:

```yaml
dependencies:
  self_test: ^0.2.0
```

Requires **Flutter 3.35.0** or newer (Dart 3.9.0). That is the oldest version
the test suite runs against in CI, not a guess.

Then run:

```bash
flutter pub get
```

The core package has no dependencies beyond Flutter and `meta`. The
`build_runner` code generator is a separate, optional package
(`self_test_gen`), so the analyzer and formatter never end up in your app's
dependency tree. See [Code Generation](#code-generation-with-annotations).

### With AI-Powered Testing (Optional)

For AI agent integration with Claude Code:

1. **Install MCP server:**
   ```bash
   git clone https://github.com/loonix/self_test
   cd self_test/packages/self_test_mcp
   npm install && npm run build
   ./scripts/setup-claude.sh
   ```

2. **Add bridge to your app:**
   ```yaml
   dependencies:
     self_test_bridge:
       git:
         url: https://github.com/loonix/self_test
         path: packages/self_test_bridge
   ```

See [Architecture](#architecture) section below for details.

## Security

self_test can read the entire widget tree, tap anything, type anything and
photograph the screen. That is the product in a debug build and a remote
control in a shipped one, so:

- **It is inert in a release build.** Every action and every query returns
  nothing or throws. Opt in explicitly with
  `SelfTestManager.enableInReleaseBuilds()` if a device farm needs to drive a
  signed build.
- **The bridge listens on loopback only**, and refuses to start in a release
  build. Pass `host: InternetAddress.anyIPv4` to reach it from a real device
  and accept that the network can reach it too.
- **The bridge requires a token**, generated per instance and printed at
  startup, presented as `?token=` or an `x-self-test-token` header. A wrong
  token gets a 403 before the WebSocket upgrade.

```dart
final bridge = SelfTestBridge();      // loopback, random token
await bridge.start();
debugPrint(bridge.url);               // ws://127.0.0.1:9999?token=...
```

## Sponsors

<div align="center">
  <a href="https://objais.com" target="_blank">
    <img src="logo-objais.png" alt="Objais" width="200"/>
  </a>
  <br/>
  <em>Proudly sponsored by <a href="https://objais.com">Objais</a></em>
</div>

## Quick Start

### Drive an app that has never heard of this package

```bash
flutter pub add dev:self_test
```

`test/login_test.dart`, complete and copy-pasteable:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

import 'package:your_app/main.dart';

void main() {
  final app = SelfTestManager();

  testWidgets('a user can sign in', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // "Username" is the label beside the field, which is how a person names
    // it. self_test resolves from the label to the field it belongs to.
    await app.typeInto(const SelfTestLocator.text('Username'), 'ada');
    await app.typeInto(const SelfTestLocator.text('Password'), 'correct horse');
    await app.tap(const SelfTestLocator.text('Sign in'));
    await tester.pumpAndSettle();

    expect(app.exists(const SelfTestLocator.text('Welcome, ada')), isTrue);
  });
}
```

```bash
flutter test test/login_test.dart
```

That is the whole quickstart. `MyApp` is your app, unchanged: no
`SelfTestRoot`, no `SelfTestableWidget`, no annotations, no generated code.
This exact flow runs in CI on every push as `test/no_wrapper_test.dart`,
against an app that imports nothing from this package.

Nothing above needs a change to the app. The locator is resolved against the
element tree at the moment it is used, and the tap is a real
`PointerDownEvent` and `PointerUpEvent` through `GestureBinding`, so hit
testing runs: a button under a dialog is not reachable, a disabled button
swallows the tap, and typing goes through the field's input formatters.

Locators, in the order you will reach for them:

| Locator | Finds |
|---|---|
| `SelfTestLocator.text('Sign in')` | the text a widget paints (`exact: false` for a substring) |
| `SelfTestLocator.key('submit')` | a `ValueKey<String>` |
| `SelfTestLocator.tooltip('Delete')` | an icon-only button |
| `SelfTestLocator.semantics('Avatar')` | what a screen reader would read |
| `SelfTestLocator.type('Switch')` | a widget type by name |
| `SelfTestLocator.id('login_button')` | a `SelfTestableWidget` id |

Add `.at(2)` to any of them to pick between duplicates, in tree order.

`describeScreen()` answers "what can I do here?" without a locator at all: it
returns every actionable widget on screen with its type, text, tooltip, rect
and enabled state. That is what the MCP server hands an agent.

Two questions that look the same and are not: `exists` asks whether a widget
is in the tree, `isVisible` asks whether the user can see it. A list keeps
items built for a while after they scroll away, so a driven tap on one refuses
rather than landing on whatever is drawn at those coordinates now.

Under `integration_test`, add one line to `main()` before your tests:

```dart
final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
binding.shouldPropagateDevicePointerEvents = true;
```

That binding drops every pointer event that did not come from a
`WidgetTester`. Without the line the taps do nothing and say nothing; with
self_test you get an error that tells you this instead.

### Optional: give widgets an id

Wrapping is no longer required. It is still useful when a widget has no text,
no key and no label to find it by, or when you want a recorded script to keep
working after the copy changes.

### 1. Wrap Your App Root

```dart
import 'package:self_test/self_test.dart';

void main() {
  runApp(SelfTestRoot(child: MyApp()));
}
```

In a debug build this also draws the floating recording controls over your
app. They are hidden automatically under `flutter_test`, because they are a
live overlay and `pumpAndSettle` on a tree containing them never returns.
Use `showControls` to decide for yourself:

```dart
SelfTestRoot(showControls: false, child: MyApp())  // never draw them
SelfTestRoot(showControls: true, child: MyApp())   // always, tests included
SelfTestRoot(child: MyApp())                       // debug app yes, test no
```

### 2. Wrap Interactive Widgets

```dart
SelfTestableWidget(
  id: 'username_field',
  onTextChange: (value) => setState(() => username = value),
  child: TextField(
    decoration: InputDecoration(labelText: 'Username'),
    onChanged: (value) => setState(() => username = value),
  ),
),
```

### 3. Run Tests

```dart
await SelfTestManager().enterText('username_field', 'john_doe');
await SelfTestManager().trigger('login_button');
await SelfTestManager().waitForAnimations();
```

`trigger` and `enterText` still take an id and still work. They now
send a real pointer event when the widget is on screen, and fall back to the
registered callback only when it is not.

## Usage

### Code Generation with Annotations

A typed controller removes the stringly-typed ids from your tests. It is
generated by `self_test_gen`, which is a dev dependency: nothing it pulls in
reaches your app.

```yaml
dependencies:
  self_test: ^0.2.0

dev_dependencies:
  build_runner: ^2.4.9
  self_test_gen: ^0.2.0
```

Annotate the handlers you already wrote. The id is the same one the widget
registers under:

```dart
// lib/login_form.dart
import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

class _LoginFormState extends State<LoginForm> {
  @SelfTestButton('login_btn')
  void onLoginPressed() { /* ... */ }

  @SelfTestInput('username_field')
  void onUsernameChanged(String value) { /* ... */ }

  @SelfTestInput('password_field')
  void onPasswordChanged(String value) { /* ... */ }
}
```

Generate:

```bash
dart run build_runner build
```

That writes `lib/login_form.g.dart`, a standalone library. **Do not add a
`part` directive for it, and do not import it from `login_form.dart`.** It is
a library, not a part file, and importing a file that does not exist yet makes
`login_form.dart` unresolvable, which leaves the generator with no annotations
to find. Import it from your test:

```dart
// test/login_form_test.dart
import 'package:your_app/login_form.g.dart';

final controller = LoginFormStateTestController();

controller.enterUsernameField('john_doe');
controller.enterPasswordField('secret123');
controller.tapLoginBtn();
controller.expectUsernameFieldText('john_doe');
controller.expectLoginBtnExists();
```

Naming rules, so you can predict the generated API without reading the output:

| From | Generated |
|---|---|
| `class _LoginFormState` | `LoginFormStateTestController` (a leading `_` is dropped so the controller is usable from a test) |
| `@SelfTestButton('login_btn')` | `tapLoginBtn()`, `expectLoginBtnExists()`, `expectLoginBtnDoesNotExist()` |
| `@SelfTestInput('username_field')` | `enterUsernameField(String)`, `expectUsernameFieldText(String)`, plus the two existence assertions |

Ids are converted to camelCase for method names, so generated code passes the
same lints as the rest of your project. The id itself is used verbatim in the
calls, because that is the key the widget registered under.

A working end-to-end example, annotations through to a passing test, lives in
[`example/`](example): see `lib/example.dart` for the annotations and
`test/controller_test.dart` for the generated controller in use.

### Test Scenarios

Define multi-step test scenarios:

```dart
final scenario = TestScenario(
  name: 'Login flow',
  steps: [
    TestStep.enterText('username_field', 'user@example.com'),
    TestStep.enterText('password_field', 'password123'),
    TestStep.tap('login_button'),
    TestStep.wait(Duration(milliseconds: 500)),
    TestStep.screenshot('after_login'),
  ],
);

final result = await scenario.run();
print(result.allPassed ? 'All steps passed' : 'Failed at step ${result.failedAtStep}');
```

### Widget Testing

Integrate with `flutter_test`:

```dart
testWidgets('Login flow test', (WidgetTester tester) async {
  SelfTestManager().setTestMode(true);

  await tester.pumpWidget(MyApp());
  await tester.pumpAndSettle();

  SelfTestManager().enterText('username_field', 'testuser');
  SelfTestManager().trigger('login_button');
  await tester.pump();

  expect(find.text('Login successful!'), findsOneWidget);
});
```

### Enabling Self-Test Mode

```dart
// In debug/profile builds
SelfTestManager().setSelfTestModeActive(true);
SelfTestManager().restartWidgetTree();

// In test environments
SelfTestManager().setTestMode(true);
```

## API Reference

### SelfTestManager

Singleton managing test nodes and actions.

| Method | Description |
|--------|-------------|
| `trigger(id)` | Tap a button by ID |
| `enterText(id, text)` | Enter text in a field by ID |
| `waitForAnimations()` | Wait for UI updates |
| `restartWidgetTree()` | Force widget tree rebuild |
| `captureScreenshot([name])` | Capture a screenshot |
| `registerTestNode(node)` | Register a test node |
| `unregisterTestNode(id)` | Unregister a test node |
| `setSelfTestModeActive(bool)` | Enable/disable in debug/profile |
| `setTestMode(bool)` | Enable/disable in test environments |

### SelfTestableWidget

```dart
SelfTestableWidget({
  required String id,
  required Widget child,
  VoidCallback? onTap,
  ValueSetter<String>? onTextChange,
})
```

### Annotations

```dart
@SelfTestButton(String id)  // For tappable widgets
@SelfTestInput(String id)   // For text input widgets
```

## Architecture

The self_test ecosystem consists of three components:

```
┌─────────────────────────────────────────────────────────────────┐
│                      AI Agent (Claude)                           │
└─────────────────────────────┬───────────────────────────────────┘
                              │ MCP Protocol
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   self_test_mcp Server                           │
│  • 60+ Playwright-equivalent tools                               │
│  • Actions: tap, type, scroll, drag                             │
│  • Assertions: expect, visual regression                        │
│  • State inspection: Riverpod, Bloc, Provider                   │
│  • Network mocking & monitoring                                 │
└─────────────────────────────┬───────────────────────────────────┘
                              │ WebSocket
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                Flutter App + self_test_bridge                    │
│  • Receives commands from MCP                                    │
│  • Executes via self_test callbacks                             │
│  • Works on iOS, Android, Web, Desktop                          │
└─────────────────────────────────────────────────────────────────┘
```

### Components

| Package | Description | When to Use |
|---------|-------------|-------------|
| **self_test** (this package) | Core: locators, real pointer events, recording | Always - enables runtime testing in your Flutter app |
| **self_test_bridge** | WebSocket bridge connecting MCP to Flutter | When using AI-powered testing with Claude |
| **self_test_mcp** | MCP server with 60+ tools for AI agents | When using AI agents for automated testing |

## AI-Powered Testing with MCP

The self_test MCP (Model Context Protocol) server enables AI agents like Claude to test your Flutter apps with **Playwright feature parity**.

### Platform Support

| Platform | Bridge Required | How It Works |
|----------|----------------|--------------|
| **iOS** | ✅ Yes | Bridge runs WebSocket server on device, MCP connects |
| **Android** | ✅ Yes | Bridge runs WebSocket server on device, MCP connects |
| **Web** (with bridge) | ✅ Yes | Bridge embedded in web app, MCP connects |
| **Web** (bridgeless) | ❌ No | MCP uses Playwright + Flutter semantics tree |
| **Desktop** | ✅ Yes | Bridge runs WebSocket server in app, MCP connects |

### Quick Start with MCP

#### 1. Install MCP Server

```bash
npx self-test-mcp --help
```

Add it to `~/.claude/settings.json`. The token is the one your app prints at
startup: the bridge refuses a connection without it.

```json
{
  "mcpServers": {
    "flutter-self-test": {
      "command": "npx",
      "args": ["self-test-mcp"],
      "env": {
        "FLUTTER_APP_HOST": "127.0.0.1",
        "FLUTTER_APP_PORT": "9999",
        "SELF_TEST_TOKEN": "<the token the app printed>"
      }
    }
  }
}
```

#### 2. Add Bridge to Flutter App

Add to `pubspec.yaml`:

```yaml
dependencies:
  self_test_bridge:
    git:
      url: https://github.com/loonix/self_test
      path: packages/self_test_bridge
```

Add to `main.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debug only. The bridge refuses to start in a release build anyway: it is
  // a remote control for the app, and it listens on a socket.
  if (kDebugMode) {
    final bridge = SelfTestBridge(port: 9999);
    await bridge.start();
    // Loopback and a fresh token per run. Give this to the MCP server.
    debugPrint(bridge.url);
  }

  runApp(SelfTestRoot(child: MyApp()));
}
```

#### 3. Test with Claude

Open Claude Code and ask:

The agent's first call is `flutter_describe_screen`, which answers with every
widget on screen and a ready-made locator for each. It does not need your app
to have been prepared in any way.

```
Test the login flow in my Flutter app:
1. Enter username "test@example.com"
2. Enter password "password123"
3. Tap login button
4. Verify we navigated to the dashboard
```

Claude will use the MCP tools to interact with your app!

### Web-External Mode (No Bridge Required!)

Test **any Flutter web app** without code changes using Playwright:

```bash
# Configure for web-external mode
export BRIDGE_MODE=web-external
export FLUTTER_APP_URL=https://your-app.com
export PLAYWRIGHT_HEADLESS=false

# Run MCP server
npm start
```

Perfect for:
- Production web apps
- Third-party Flutter apps
- CI/CD smoke tests
- Quick exploratory testing

### Available MCP Tools

The MCP server provides 60+ tools with Playwright feature parity:

**Locators & Queries:**
- `flutter_snapshot` - Get widget tree
- `flutter_get_by_role` - Find by semantic role
- `flutter_get_by_text` - Find by text content

**Actions:**
- `flutter_tap`, `flutter_type`, `flutter_clear`, `flutter_scroll`
- `flutter_drag`, `flutter_hover`, `flutter_focus`
- `flutter_long_press`, `flutter_double_tap`

**Assertions:**
- `flutter_expect` - Assert widget state (toBeVisible, toHaveText, etc.)
- `flutter_expect_screenshot` - Visual regression testing

**State Management:**
- `flutter_get_state` - Inspect Riverpod/Bloc/Provider state
- `flutter_dispatch_action` - Dispatch events/actions
- `flutter_watch_state` - Subscribe to state changes

**Network:**
- `flutter_mock_http` - Mock API responses
- `flutter_block_http` - Block requests
- `flutter_network_log` - Monitor network traffic

**Platform Mocking:**
- `flutter_set_geolocation` - Mock GPS
- `flutter_set_permission` - Mock permissions
- `flutter_mock_channel` - Mock platform channels

[See full tool list in packages/self_test_mcp/README.md]

## Ecosystem

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run the test suite: `flutter test`
6. Submit a pull request

## License

Copyright (c) 2025-2026 Ari Silva, Daniel Carneiro. All rights reserved.

This software may be used and modified in your own products and services, but may not be sold or redistributed as a standalone product. See the [LICENSE](LICENSE) file for details.
