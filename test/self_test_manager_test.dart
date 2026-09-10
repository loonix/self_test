import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

// Mock custom widget for testing
class MockCustomWidget extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const MockCustomWidget({Key? key, this.onPressed, required this.child})
    : super(key: key);

  @override
  Widget build(BuildContext context) => child;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelfTestManager', () {
    late SelfTestManager manager;

    setUp(() {
      manager = SelfTestManager();
      manager.setTestMode(true);
    });

    test('registers and triggers test node', () async {
      bool tapped = false;
      final node = TestNode(id: 'test_button', onTap: () => tapped = true);

      manager.registerTestNode(node);
      await manager.trigger('test_button');

      expect(tapped, true);
    });

    test('enters text in test node', () async {
      String? enteredText;
      final node = TestNode(
        id: 'test_input',
        onTextChange: (text) => enteredText = text,
      );

      manager.registerTestNode(node);
      await manager.enterText('test_input', 'hello world');

      expect(enteredText, 'hello world');
      expect(node.currentText, 'hello world');
    });

    test('custom widget builder registration works', () {
      // Register a custom builder
      bool builderCalled = false;
      manager.registerRecordingBuilder<MockCustomWidget>((
        widget,
        selfTestWidget,
      ) {
        builderCalled = true;
        final mockWidget = widget as MockCustomWidget;
        return MockCustomWidget(
          onPressed: () async {
            await manager.trigger(selfTestWidget.id);
            mockWidget.onPressed?.call();
            selfTestWidget.onTap?.call();
          },
          child: mockWidget.child,
        );
      });

      // Verify the builder is registered
      final registeredBuilder = manager.getRecordingBuilder(MockCustomWidget);
      expect(registeredBuilder, isNotNull);

      // Create a SelfTestableWidget with MockCustomWidget (not used in this test)
      SelfTestableWidget(
        id: 'custom_widget',
        onTap: () {},
        child: MockCustomWidget(onPressed: () {}, child: const SizedBox()),
      );

      // The builder should be called during build (simulated)
      // Since we can't easily test the build process in unit tests,
      // we verify the builder exists and can be retrieved
      expect(builderCalled, false); // Not called yet
      expect(manager.getRecordingBuilder(MockCustomWidget), isNotNull);
    });
  });
}
