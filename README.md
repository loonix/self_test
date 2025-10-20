# Self-Test Package for Flutter

A Flutter package that allows executing automated regression tests (Self-Tests) directly in development and pre-production environments (debug or profile builds). The package enables the app to programmatically perform user actions (like tapping buttons or entering text) without relying on WidgetTester or low-level touch event injection.

## Features

- **Direct Callback Invocation**: Simulates user actions by directly calling widget callbacks instead of injecting touch events.
- **Runtime Testing**: Run tests in live app environments without external test frameworks.
- **Code Generation**: Uses build_runner to automatically wrap annotated widgets.
- **Memory Safe**: Proper registration and unregistration of test nodes to prevent leaks.

## Getting Started

Add to your pubspec.yaml:

```yaml
dependencies:
  self_test: ^0.0.1
```

For development:

```yaml
dev_dependencies:
  build_runner: ^2.0.0
```

## Usage

1. Wrap your app's root with `SelfTestRoot`:

```dart
void main() {
  runApp(SelfTestRoot(child: MyApp()));
}
```

2. Manually wrap testable widgets:

```dart
SelfTestableWidget(
  id: 'login_btn',
  onTap: () => print('Login pressed'),
  child: ElevatedButton(onPressed: () {}, child: Text('Login')),
)

SelfTestableWidget(
  id: 'username_field',
  onTextChange: (value) => print('Username: $value'),
  child: TextField(onChanged: (value) {}),
)
```

3. Run code generation (for test controllers):

```bash
flutter pub run build_runner build
```

Include the generated part:

```dart
part 'your_file.self_test.g.dart';
```

4. Activate self-test mode:

```dart
SelfTestManager().setSelfTestModeActive(true);
SelfTestManager().restartWidgetTree(); // Restart to apply
```

For testing environments (where kDebugMode is false):

```dart
SelfTestManager().setTestMode(true); // Enables registration in tests
```

5. Run tests:

```dart
SelfTestManager().trigger('login_btn');
SelfTestManager().enterText('username_field', 'testuser');
await SelfTestManager().waitForAnimations();
```

## Architecture

- **SelfTestManager**: Singleton managing test nodes.
- **TestNode**: Holds callbacks for actions.
- **SelfTestableWidget**: Wrapper for testable widgets.
- **Code Generation**: Automatic injection via build_runner.

## Additional Information

This package is in development. See the plan for full implementation details.
