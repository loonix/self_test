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
}
