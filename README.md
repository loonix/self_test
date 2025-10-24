# Self-Test Package for Flutter

[![pub package](https://img.shields.io/pub/v/self_test.svg)](https://pub.dev/packages/self_test)

A Flutter package that enables automated regression testing directly within your app's runtime environment. Unlike traditional testing frameworks that simulate UI interactions, Self-Test invokes widget callbacks directly, providing fast and reliable testing for development and pre-production environments.

## ✨ Features

- **🚀 Direct Callback Invocation**: Execute user actions by calling widget callbacks directly instead of injecting touch events
- **⚡ Runtime Testing**: Run tests in live app environments without external test frameworks
- **🔧 Code Generation**: Automatic test controller generation using build_runner and annotations
- **📝 Text Assertions**: Built-in text validation for input fields
- **🧠 Memory Safe**: Automatic registration/unregistration prevents memory leaks
- **🎯 Type Safe**: Compile-time generated controllers with full type safety
- **🔄 Hot Restart Compatible**: Works seamlessly with Flutter's hot restart
- **⚙️ Automatic Activation**: Self-test mode activates automatically in debug/profile builds

## 📦 Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  self_test: ^0.0.1

dev_dependencies:
  build_runner: ^2.4.9
  source_gen: ^1.5.0
  analyzer: ^6.0.0
  dart_style: ^2.3.6
```

Then run:

```bash
flutter pub get
```

## 🚀 Quick Start

### 1. Wrap Your App Root

```dart
import 'package:self_test/self_test.dart';

void main() {
  runApp(SelfTestRoot(child: MyApp()));
}
```

### 2. Manual Widget Wrapping

Wrap interactive widgets with `SelfTestableWidget`:

```dart
class LoginForm extends StatefulWidget {
  @override
  _LoginFormState createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  String username = '';
  String password = '';

  void _onLoginPressed() {
    // Your login logic
    print('Login pressed with: $username, $password');
  }

  void _onUsernameChanged(String value) {
    setState(() => username = value);
  }

  void _onPasswordChanged(String value) {
    setState(() => password = value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SelfTestableWidget(
          id: 'username_field',
          onTextChange: _onUsernameChanged,
          child: TextField(
            decoration: InputDecoration(labelText: 'Username'),
            onChanged: _onUsernameChanged,
          ),
        ),
        SizedBox(height: 16),
        SelfTestableWidget(
          id: 'password_field',
          onTextChange: _onPasswordChanged,
          child: TextField(
            decoration: InputDecoration(labelText: 'Password'),
            obscureText: true,
            onChanged: _onPasswordChanged,
          ),
        ),
        SizedBox(height: 16),
        SelfTestableWidget(
          id: 'login_button',
          onTap: _onLoginPressed,
          child: ElevatedButton(
            onPressed: _onLoginPressed,
            child: Text('Login'),
          ),
        ),
      ],
    );
  }
}
```

### 3. Automatic Self-Test Mode Activation

Self-test mode is automatically activated in debug and profile builds. No manual activation is required - the framework detects the build mode and enables testing capabilities automatically.

```dart
// Automatic activation - no code needed!
// In debug/profile builds: Self-test mode is active
// In release builds: Self-test mode is inactive for performance
```

For testing release builds or custom environments:

```dart
// Manual override for testing release builds
SelfTestManager().setTestMode(true);
```

### 4. Run Tests

```dart
// Direct API usage
SelfTestManager().ensureVisible('login_button'); // Scroll into view if needed
SelfTestManager().enterText('username_field', 'john_doe');
SelfTestManager().enterText('password_field', 'secret123');
await SelfTestManager().waitForAnimations();
SelfTestManager().trigger('login_button');

// Test scrolling functionality
SelfTestManager().trigger('go_to_list'); // Navigate to scrollable list
await SelfTestManager().waitForAnimations();
SelfTestManager().ensureVisible('list_item_50'); // Scroll to middle of list
SelfTestManager().trigger('list_item_50'); // Interact with item
SelfTestManager().ensureVisible('list_item_95'); // Scroll to bottom
SelfTestManager().trigger('list_item_95'); // Interact with bottom item
```

## 🔧 Advanced Usage

### Code Generation with Annotations

For type-safe test controllers, use annotations and code generation:

```dart
import 'package:self_test/self_test.dart';

part 'login_form.self_test.g.dart'; // Generated file

class LoginForm extends StatefulWidget {
  @override
  _LoginFormState createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  @SelfTestButton('login_btn')
  void onLoginPressed() {
    // Login logic
  }

  @SelfTestInput('username_field')
  void onUsernameChanged(String value) {
    // Handle username input
  }

  @SelfTestInput('password_field')
  void onPasswordChanged(String value) {
    // Handle password input
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(onChanged: onUsernameChanged),
        TextField(onChanged: onPasswordChanged, obscureText: true),
        ElevatedButton(onPressed: onLoginPressed, child: Text('Login')),
      ],
    );
  }
}
```

Generate the controller:

```bash
flutter pub run build_runner build
```

Use the generated controller:

```dart
final controller = LoginFormTestController();

// Type-safe actions
controller.enterUsernameField('john_doe');
controller.enterPasswordField('secret123');
controller.tapLoginBtn();

// Text assertions
controller.expectUsernameFieldText('john_doe');
controller.expectPasswordFieldText('secret123');
```

### Extending Widget Support

Self-Test provides built-in support for common Flutter widgets, but you can extend it to work with custom or third-party widgets by registering recording builders.

#### Registering Custom Widget Builders

```dart
import 'package:self_test/self_test.dart';

// Define a recording builder for your custom widget
Widget buildRecordingCustomButton(CustomButton button, SelfTestableWidget widget) {
  return CustomButton(
    onPressed: () async {
      // Record the action
      await SelfTestManager().trigger(widget.id);
      // Call the original callback
      button.onPressed?.call();
      // Call the SelfTestableWidget callback
      widget.onTap?.call();
    },
    // Copy other properties...
    child: button.child,
  );
}

// Register the builder
SelfTestManager().registerRecordingBuilder<CustomButton>(
  (child, widget) => buildRecordingCustomButton(child as CustomButton, widget)
);
```

#### Using Custom Widgets

```dart
SelfTestableWidget(
  id: 'custom_button',
  onTap: () => print('Custom button tapped'),
  child: CustomButton(
    onPressed: () => print('Custom button tapped'),
    child: Text('Custom Button'),
  ),
)
```

#### Important Notes

- **Test Logic Responsibility**: The framework handles infrastructure (recording, playback, node management). You are responsible for implementing the test logic and ensuring your widgets behave correctly during testing.
- **Fallback Behavior**: If no builder is registered for a widget type, Self-Test will:
  - Wrap the widget in a `GestureDetector` if `onTap` is provided on `SelfTestableWidget`
  - Return the widget as-is with a warning if no `onTap` is provided
- **Memory Management**: Builders should not introduce memory leaks. The framework handles automatic registration/unregistration.
- **Thread Safety**: Recording builders are called during widget build, so avoid heavy computations.

#### Supported Built-in Widgets

Self-Test includes built-in support for:

- **Text Input**: `TextField`, `TextFormField`
- **Buttons**: `ElevatedButton`, `TextButton`, `OutlinedButton`, `IconButton`, `FloatingActionButton`
- **Form Controls**: `Checkbox`, `Radio`, `Switch`, `CheckboxListTile`, `RadioListTile`, `SwitchListTile`
- **Lists**: `ListTile`
- **Other**: `Slider`

For unsupported widgets, register custom builders or use the fallback `GestureDetector` wrapping.

### Testing Integration

For unit/integration tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

void main() {
  testWidgets('Login flow test', (WidgetTester tester) async {
    // Enable test mode
    SelfTestManager().setTestMode(true);

    // Build app
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    // Run self-test
    SelfTestManager().enterText('username_field', 'testuser');
    SelfTestManager().enterText('password_field', 'testpass');
    SelfTestManager().trigger('login_button');

    // Wait for UI updates
    await tester.pump();

    // Verify results
    expect(find.text('Login successful!'), findsOneWidget);
  });
}
```

## 📚 API Reference

### SelfTestManager

Singleton class managing test nodes and actions.

```dart
// Mode control
SelfTestManager().setSelfTestModeActive(bool active); // For debug/profile
SelfTestManager().setTestMode(bool active);           // For tests

// Actions
SelfTestManager().trigger(String id);                 // Tap button
SelfTestManager().enterText(String id, String text);  // Enter text
SelfTestManager().ensureVisible(String id);           // Scroll element into view

// Utilities
await SelfTestManager().waitForAnimations();          // Wait for UI updates
SelfTestManager().restartWidgetTree();                // Hot restart simulation

// Node management
SelfTestManager().registerTestNode(TestNode node);
SelfTestManager().unregisterTestNode(String id);
```

### SelfTestableWidget

Wrapper widget for manual testing setup.

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

### Generated Controllers

Auto-generated classes with type-safe methods:

```dart
class MyWidgetTestController {
  // Actions
  void tapButtonId();
  void enterTextFieldId(String text);

  // Assertions
  void expectExistsFieldId();
  void expectNotExistsFieldId();
  void expectTextFieldId(String expectedText);
}
```

### Scroll Testing

Self-Test provides built-in scroll utilities for testing scrollable content:

```dart
// Ensure element is visible before interaction
SelfTestManager().ensureVisible('list_item_50');
SelfTestManager().trigger('list_item_50');

// Works with any scrollable container (ListView, SingleChildScrollView, etc.)
SelfTestManager().ensureVisible('bottom_button');
SelfTestManager().trigger('bottom_button');
```

The example app includes a scrollable list page with 100 clickable items to demonstrate scroll testing capabilities.

### Testing Integration
}
```

## 🎯 Best Practices

### 1. ID Naming Convention
```dart
// ✅ Good: descriptive and unique
'login_button', 'username_input', 'submit_form'

// ❌ Avoid: generic or conflicting
'button', 'input', 'btn1'
```

### 2. Test Organization
```dart
class LoginTests {
  static Future<void> testValidLogin() async {
    SelfTestManager().enterText('username_field', 'user@example.com');
    SelfTestManager().enterText('password_field', 'password123');
    SelfTestManager().trigger('login_button');
    await SelfTestManager().waitForAnimations();
  }

  static Future<void> testEmptyFields() async {
    SelfTestManager().trigger('login_button');
    await SelfTestManager().waitForAnimations();
    // Assert error message appears
  }
}
```

### 3. State Management
```dart
class TestStateManager {
  static void setupTestMode() {
    SelfTestManager().setTestMode(true);
    // Additional test setup
  }

  static void cleanup() {
    SelfTestManager().setTestMode(false);
    // Cleanup logic
  }
}
```

### 4. Error Handling
```dart
try {
  SelfTestManager().trigger('nonexistent_button');
} catch (e) {
  print('Test failed: $e');
  // Handle test failure
}
```

## 🔍 Troubleshooting

### Build Issues

**Problem**: `build_runner` fails with dependency errors
```bash
# Solution: Update dependencies
flutter pub upgrade
flutter pub run build_runner clean
flutter pub run build_runner build
```

**Problem**: Generated files not found
```bash
# Check build.yaml configuration
# Ensure part directive is correct: part 'filename.g.dart';
```

### Runtime Issues

**Problem**: Actions not working in release builds
```dart
// Self-test only works in debug/profile builds by default
// For testing release builds, use:
SelfTestManager().setTestMode(true);
```

**Problem**: Memory leaks in tests
```dart
// Ensure proper cleanup
tearDown(() {
  SelfTestManager().setTestMode(false);
});
```

**Problem**: Text assertions failing unexpectedly
```dart
// Check that onTextChange callback is provided
SelfTestableWidget(
  id: 'field_id',
  onTextChange: (value) => setState(() => text = value), // Required
  child: TextField(onChanged: (value) => setState(() => text = value)),
);
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run the test suite: `flutter test`
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

Inspired by the need for fast, reliable regression testing in Flutter applications without the overhead of full UI testing frameworks.
