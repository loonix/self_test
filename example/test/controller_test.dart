import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_example/example.dart';

void main() {
  group('Generated Controller Tests', () {
    setUp(() {
      // Reset state before each test
      SelfTestManager().setTestMode(false);
      SelfTestManager().setSelfTestModeActive(false);
    });

    testWidgets('Test generated controller functionality', (WidgetTester tester) async {
      // Activate test mode
      SelfTestManager().setTestMode(true);

      // Build ExampleWidget
      await tester.pumpWidget(
        MaterialApp(
          home: SelfTestRoot(
            child: ExampleWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Create controller instance
      final controller = ExampleStateTestController();

      // Test existence checks
      controller.expectExists_username_field();
      controller.expectExists_login_btn();

      // Test text input using controller
      controller.enterText_username_field('controller_test_user');
      await tester.pump();

      // Verify text was set
      controller.expectText_username_field('controller_test_user');

      // Test button tap using controller
      controller.tap_login_btn();
      await tester.pump();

      // Verify the UI reflects the username
      expect(find.text('Current username: controller_test_user'), findsOneWidget);
    });

    testWidgets('Test controller error handling', (WidgetTester tester) async {
      // Create controller without building any widgets
      final controller = ExampleStateTestController();

      // Test expectNotExists when nodes don't exist
      controller.expectNotExists_username_field();
      controller.expectNotExists_login_btn();

      // Test existence check failures
      expect(() => controller.expectExists_username_field(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('does not exist'))));

      expect(() => controller.expectExists_login_btn(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('does not exist'))));
    });

    testWidgets('Test text assertion failures', (WidgetTester tester) async {
      // Activate test mode
      SelfTestManager().setTestMode(true);

      // Build ExampleWidget
      await tester.pumpWidget(
        MaterialApp(
          home: SelfTestRoot(
            child: ExampleWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = ExampleStateTestController();

      // Set some text
      controller.enterText_username_field('actual_text');
      await tester.pump();

      // Test successful assertion
      controller.expectText_username_field('actual_text');

      // Test failed assertion
      expect(() => controller.expectText_username_field('wrong_text'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf([
            contains('Expected text "wrong_text"'),
            contains('but found "actual_text"')
          ]))));
    });

    testWidgets('Test controller with widget lifecycle', (WidgetTester tester) async {
      // Activate test mode
      SelfTestManager().setTestMode(true);

      final controller = ExampleStateTestController();

      // Initially no widgets exist
      controller.expectNotExists_username_field();

      // Build the widget
      await tester.pumpWidget(
        MaterialApp(
          home: SelfTestRoot(
            child: ExampleWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Now widgets should exist
      controller.expectExists_username_field();
      controller.expectExists_login_btn();

      // Dispose the widget
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();

      // Widgets should no longer exist
      controller.expectNotExists_username_field();
      controller.expectNotExists_login_btn();
    });
  });
}