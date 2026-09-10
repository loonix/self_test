import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Self-Test End-to-End Tests', () {
    setUp(() {
      // SelfTestManager is a singleton, so without this the mode a previous
      // test switched on is still on when the next one asserts it is off.
      SelfTestManager().setTestMode(false);
      SelfTestManager().setSelfTestModeActive(false);
      SelfTestManager().activeTestNodes.clear();
    });

    testWidgets('Complete user flow with self-test activation', (
      WidgetTester tester,
    ) async {
      // Build the app
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Initially self-test mode should be inactive
      expect(SelfTestManager().isSelfTestModeActive, isFalse);

      // Activate self-test mode through UI
      await tester.tap(find.text('Activate Self-Test Mode'));
      await tester.pumpAndSettle();

      // Verify mode is activated
      expect(SelfTestManager().isSelfTestModeActive, isTrue);

      // Wait for snackbar to disappear
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Run the automated test via UI
      await tester.tap(find.text('Run Test'));
      await tester.pumpAndSettle();

      // Verify the test executed successfully
      expect(find.text('Login successful!'), findsOneWidget);
    });

    testWidgets('Test ExampleWidget navigation and functionality', (
      WidgetTester tester,
    ) async {
      // Build the app
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Activate self-test mode first
      await tester.tap(find.text('Activate Self-Test Mode'));
      await tester.pumpAndSettle();

      // Navigate to ExampleWidget
      await tester.tap(find.text('Open Example Widget'));
      await tester.pumpAndSettle();

      // Verify we're on the example page
      expect(find.text('Example Widget'), findsOneWidget);

      // Test manual interaction with the example widget
      // Note: Manual interaction might not work in test mode,
      // but we can verify the widgets are present
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
      expect(find.text('Current username: '), findsOneWidget);

      // Go back to main page
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Verify we're back on the main page. 'Login' is both the AppBar
      // title and the button label here, so match the button.
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
      expect(find.text('Activate Self-Test Mode'), findsOneWidget);
    });

    testWidgets('Test self-test mode toggle behavior', (
      WidgetTester tester,
    ) async {
      // Build the app
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Initially inactive
      expect(SelfTestManager().isSelfTestModeActive, isFalse);

      // Activate via UI
      await tester.tap(find.text('Activate Self-Test Mode'));
      await tester.pumpAndSettle();
      expect(SelfTestManager().isSelfTestModeActive, isTrue);

      // Test that widgets are now registered
      // We can't directly check registration in integration tests,
      // but we can verify the run test functionality works
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('Run Test'));
      await tester.pumpAndSettle();

      // If registration worked, the test should execute without throwing
      expect(find.text('Login successful!'), findsOneWidget);
    });

    testWidgets('Test error handling with invalid operations', (
      WidgetTester tester,
    ) async {
      // Build the app with test mode active
      SelfTestManager().setTestMode(true);
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Try to trigger a non-existent widget (should not crash the app)
      bool threwException = false;
      try {
        await SelfTestManager().trigger('nonexistent_widget');
      } catch (e) {
        threwException = true;
        expect(e.toString(), contains('not found'));
      }
      expect(threwException, isTrue);

      // Verify the app is still functional after the error
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);

      // Normal operations should still work
      await SelfTestManager().enterText('username_field', 'test');
      await SelfTestManager().enterText('password_field', 'pass');
      await SelfTestManager().trigger('login_button');
      await tester.pump();

      expect(find.text('Login successful!'), findsOneWidget);
    });
  });
}
