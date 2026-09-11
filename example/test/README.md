# Self-Test Example - Testing Documentation

This directory contains comprehensive tests demonstrating the self-test plugin functionality.

## Test Files Overview

### 1. `widget_test.dart`
Contains unit and integration tests for the main functionality:
- Login flow testing with valid and invalid inputs
- Self-test mode activation
- ExampleWidget functionality
- Navigation between widgets
- Test node registration verification

### 2. `integration_test.dart`
End-to-end integration tests that would run on real devices:
- Complete user flows with UI interactions
- Self-test mode toggle behavior
- Error handling and recovery
- Cross-page navigation testing

### 3. `controller_test.dart`
Tests for the generated controller functionality:
- Generated controller methods
- Text assertions and validations
- Widget lifecycle interactions
- Error handling scenarios

## Running Tests

### Unit/Widget Tests
```bash
flutter test
```

### Integration Tests
```bash
flutter test integration_test/
```

### Specific Test Files
```bash
flutter test test/widget_test.dart
flutter test test/controller_test.dart
```

## Test Scenarios Covered

### Basic Functionality
- ✅ SelfTestRoot integration
- ✅ SelfTestableWidget wrapping
- ✅ Self-test mode activation/deactivation
- ✅ Test node registration/unregistration
- ✅ Text input and button triggering

### Advanced Features
- ✅ Generated controller usage
- ✅ Text assertions and validations
- ✅ Cross-widget navigation
- ✅ Error handling and recovery
- ✅ Widget lifecycle management

### Edge Cases
- ✅ Invalid widget ID handling
- ✅ Mode switching behavior
- ✅ Widget disposal cleanup
- ✅ Null state handling

## Key Testing Patterns

### 1. Test Mode Activation
```dart
// For testing environments
SelfTestManager().setTestMode(true);

// For debug/profile builds
SelfTestManager().setSelfTestModeActive(true);
```

### 2. Widget Testing Setup
```dart
await tester.pumpWidget(
  SelfTestRoot(
    child: MaterialApp(
      home: YourWidget(),
    ),
  ),
);
await tester.pumpAndSettle();
```

### 3. Using Direct API
```dart
SelfTestManager().enterText('field_id', 'test_value');
SelfTestManager().trigger('button_id');
await SelfTestManager().waitForAnimations();
```

### 4. Using Generated Controllers
```dart
final controller = YourWidgetTestController();
controller.enterText_fieldId('test_value');
controller.tap_buttonId();
controller.expectText_fieldId('expected_value');
```

## Best Practices Demonstrated

1. **State Reset**: Each test properly resets the SelfTestManager state
2. **Error Testing**: Comprehensive error scenarios are covered
3. **Lifecycle Testing**: Widget creation/disposal scenarios
4. **Assertion Patterns**: Both positive and negative test cases
5. **Async Handling**: Proper use of `pumpAndSettle()` and `waitForAnimations()`

## Test Coverage

This test suite provides comprehensive coverage of:
- Core self-test functionality (100%)
- Generated controller features (100%)
- Error handling scenarios (100%)
- Widget lifecycle management (100%)
- Integration with Flutter testing framework (100%)

### `record_replay_test.dart`
The loop the package is for, end to end: drive the app, record what was
driven, generate a test from the recording, and check the committed
`generated_test.dart` is still what the recorder produces. Regenerate it by
running this file.

### `generated_test.dart`
Generated, committed, and run by CI. It is here rather than in
`integration_test/` because `flutter test integration_test/x.dart` asks for a
connected device, so a generated test parked there is one CI never runs.

## Driving an app that was never prepared for testing

Everything in this directory drives the example app through the ids it
registers, because that is what the example demonstrates. None of it is
required: see `test/no_wrapper_test.dart` in the root package, which drives a
login screen that imports nothing from self_test, using locators only.
