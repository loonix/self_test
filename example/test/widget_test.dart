import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_example/main.dart';

void main() {
  testWidgets('Self-test example', (WidgetTester tester) async {
    // Activate test mode for testing environment
    SelfTestManager().setTestMode(true);

    // Build the app
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    // Run self-test
    SelfTestManager().enterText('username_field', 'testuser');
    SelfTestManager().enterText('password_field', 'testpass');
    SelfTestManager().trigger('login_button');

    // Pump to update UI
    await tester.pump();

    // Verify result
    expect(find.text('Login successful!'), findsOneWidget);
  });

  testWidgets('Scrollable list test with ensureVisible', (WidgetTester tester) async {
    // Activate test mode for testing environment
    SelfTestManager().setTestMode(true);

    // Build the app
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    // Navigate to the list page
    SelfTestManager().trigger('go_to_list');
    await tester.pumpAndSettle();

    // Test that ensureVisible can find the initially visible nodes
    // (Note: scrolling doesn't work in test environment, so we only test visible items)
    await SelfTestManager().ensureVisible('list_item_5');
    expect(SelfTestManager().activeTestNodes.containsKey('list_item_5'), true);

    await SelfTestManager().ensureVisible('list_item_10');
    expect(SelfTestManager().activeTestNodes.containsKey('list_item_10'), true);

    // Test that we can still interact with items
    SelfTestManager().trigger('list_item_2');
    await tester.pump();

    // Test scroll to top button (this should work since it's visible)
    SelfTestManager().trigger('scroll_to_top_button');
    await tester.pump();

    // Go back to login page
    SelfTestManager().trigger('back_from_list');
    await tester.pumpAndSettle();

    // Verify we're back on the login page
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Login'), findsNWidgets(2)); // AppBar title + button text
  });
}
