import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

/// The binding `integration_test` runs under. It throws away pointer events
/// that did not come from a `WidgetTester`, which is the one way a driven tap
/// can do nothing and report nothing.
void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('says so instead of dispatching into the void', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, child: const Text('Press')),
        ),
      ),
    );

    await expectLater(
      SelfTestManager().tap(const SelfTestLocator.text('Press')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('shouldPropagateDevicePointerEvents'),
            contains('drops pointer events'),
          ),
        ),
      ),
    );
  });
}
