import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_example/main.dart';

void main() {
  final manager = SelfTestManager();

  tearDown(manager.clearClock);

  testWidgets('login flow', (tester) async {
    manager.useClock(tester.pump);
    await tester.pumpWidget(SelfTestRoot(child: const MyApp()));
    await tester.pumpAndSettle();
    await manager.typeInto(const SelfTestLocator.id('username_field'), 'ada');
    await tester.pumpAndSettle();
    await manager.typeInto(
      const SelfTestLocator.id('password_field'),
      'lovelace',
    );
    await tester.pumpAndSettle();
    await manager.tap(const SelfTestLocator.id('login_button'));
    await tester.pumpAndSettle();
    expect(
      manager.readText(const SelfTestLocator.text('Login successful!')),
      'Login successful!',
    );
  });
}
