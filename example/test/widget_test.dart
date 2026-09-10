import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_example/main.dart';
import 'package:self_test_example/example.dart';

void main() {
  group('Self-Test Integration Tests', () {
    setUp(() {
      // Reset state before each test
      SelfTestManager().setTestMode(false);
      SelfTestManager().setSelfTestModeActive(false);
    });

    testWidgets('Login flow test', (WidgetTester tester) async {
      // Activate test mode for testing environment
      SelfTestManager().setTestMode(true);

      // Build the app wrapped in SelfTestRoot
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('Please fill all fields'), findsNothing);
      expect(find.text('Login successful!'), findsNothing);

      // Run self-test - enter valid credentials
      await SelfTestManager().enterText('username_field', 'testuser');
      await SelfTestManager().enterText('password_field', 'testpass');
      await SelfTestManager().waitForAnimations();
      await SelfTestManager().trigger('login_button');

      // Pump to update UI
      await tester.pump();

      // Verify successful login
      expect(find.text('Login successful!'), findsOneWidget);
    });

    testWidgets('Empty fields validation test', (WidgetTester tester) async {
      // Activate test mode for testing environment
      SelfTestManager().setTestMode(true);

      // Build the app
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Try to login with empty fields
      await SelfTestManager().trigger('login_button');

      // Pump to update UI
      await tester.pump();

      // Verify validation message
      expect(find.text('Please fill all fields'), findsOneWidget);
      expect(find.text('Login successful!'), findsNothing);
    });

    testWidgets('Partial fields validation test', (WidgetTester tester) async {
      // Activate test mode for testing environment
      SelfTestManager().setTestMode(true);

      // Build the app
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Enter only username
      await SelfTestManager().enterText('username_field', 'testuser');
      await SelfTestManager().trigger('login_button');

      // Pump to update UI
      await tester.pump();

      // Verify validation message
      expect(find.text('Please fill all fields'), findsOneWidget);
    });

    testWidgets('Self-test mode activation test', (WidgetTester tester) async {
      // Build the app without test mode initially
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Activate self-test mode via UI
      await tester.tap(find.text('Activate Self-Test Mode'));
      await tester.pumpAndSettle();

      // Verify mode is activated
      expect(SelfTestManager().isSelfTestModeActive, isTrue);

      // The status text is derived from the manager, so it survives the
      // widget-tree restart that activation performs. A snackbar did not.
      expect(find.text('Self-test mode activated'), findsOneWidget);
    });

    testWidgets('ExampleWidget integration test', (WidgetTester tester) async {
      // Activate test mode
      SelfTestManager().setTestMode(true);

      // Build ExampleWidget directly
      await tester.pumpWidget(
        SelfTestRoot(
          child: MaterialApp(
            home: ExampleWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('Current username: '), findsOneWidget);

      // Test text input
      await SelfTestManager().enterText('username_field', 'example_user');
      await SelfTestManager().waitForAnimations();
      await tester.pump();

      // Verify text was entered
      expect(find.text('Current username: example_user'), findsOneWidget);

      // Test button press
      await SelfTestManager().trigger('login_btn');
      await tester.pump();

      // Note: Since onLoginPressed only prints to debug console,
      // we verify the button interaction worked by checking no errors occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('Navigation to ExampleWidget test',
        (WidgetTester tester) async {
      // Build the app
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Navigate to ExampleWidget
      await tester.tap(find.text('Open Example Widget'));
      await tester.pumpAndSettle();

      // Verify we're on the ExampleWidget page
      expect(find.text('Example Widget'), findsOneWidget);
      expect(find.text('Current username: '), findsOneWidget);
    });

    testWidgets('Test node registration test', (WidgetTester tester) async {
      // Activate test mode
      SelfTestManager().setTestMode(true);

      // Build the app
      await tester.pumpWidget(SelfTestRoot(child: MyApp()));
      await tester.pumpAndSettle();

      // Verify test nodes are registered
      final activeNodes = SelfTestManager().activeTestNodes;
      expect(activeNodes.containsKey('username_field'), isTrue);
      expect(activeNodes.containsKey('password_field'), isTrue);
      expect(activeNodes.containsKey('login_button'), isTrue);

      // Verify node properties
      final usernameNode = activeNodes['username_field']!;
      expect(usernameNode.onTextChange, isNotNull);
      expect(usernameNode.onTap, isNull);

      final buttonNode = activeNodes['login_button']!;
      expect(buttonNode.onTap, isNotNull);
      expect(buttonNode.onTextChange, isNull);
    });
  });
}
