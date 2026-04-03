# self_test

[![pub package](https://img.shields.io/pub/v/self_test.svg)](https://pub.dev/packages/self_test)

Automated regression testing for Flutter through **direct callback invocation**. Unlike traditional testing frameworks that simulate UI interactions, `self_test` invokes widget callbacks directly, providing fast and reliable testing for development and pre-production environments.

## Features

- **Direct Callback Invocation** - Execute user actions by calling widget callbacks directly instead of injecting touch events
- **Runtime Testing** - Run tests in live app environments without external test frameworks
- **Code Generation** - Automatic test controller generation using `build_runner` and annotations
- **Text Assertions** - Built-in text validation for input fields
- **Memory Safe** - Automatic registration/unregistration prevents memory leaks
- **Type Safe** - Compile-time generated controllers with full type safety
- **Hot Restart Compatible** - Works seamlessly with Flutter's hot restart
- **Test Scenarios** - Define and run multi-step test scenarios with `TestScenario`

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  self_test: ^0.1.0

dev_dependencies:
  build_runner: ^2.4.9
```

Then run:

```bash
flutter pub get
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

### 1. Wrap Your App Root

```dart
import 'package:self_test/self_test.dart';

void main() {
  runApp(SelfTestRoot(child: MyApp()));
}
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
SelfTestManager().enterText('username_field', 'john_doe');
SelfTestManager().trigger('login_button');
await SelfTestManager().waitForAnimations();
```

## Usage

### Code Generation with Annotations

For type-safe test controllers, annotate your callback methods:

```dart
import 'package:self_test/self_test.dart';

part 'login_form.self_test.g.dart';

class _LoginFormState extends State<LoginForm> {
  @SelfTestButton('login_btn')
  void onLoginPressed() { /* ... */ }

  @SelfTestInput('username_field')
  void onUsernameChanged(String value) { /* ... */ }

  @SelfTestInput('password_field')
  void onPasswordChanged(String value) { /* ... */ }
}
```

Generate the controller:

```bash
flutter pub run build_runner build
```

Use the generated controller:

```dart
final controller = LoginFormTestController();

controller.enterUsernameField('john_doe');
controller.enterPasswordField('secret123');
controller.tapLoginBtn();
controller.expectUsernameFieldText('john_doe');
```

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

## Ecosystem

| Package | Description |
|---------|-------------|
| `self_test` | Core Flutter package (this one) |
| `self_test_bridge` | WebSocket bridge for MCP/external tool integration |
| `self_test_mcp` | MCP server for AI-assisted testing |

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
