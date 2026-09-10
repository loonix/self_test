import 'package:flutter_test/flutter_test.dart';

import 'package:self_test/self_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelfTestManager', () {
    late SelfTestManager manager;

    setUp(() {
      manager = SelfTestManager();
      manager.setSelfTestModeActive(true);
    });

    test('register and trigger tap', () {
      bool tapped = false;
      final node = TestNode(id: 'test_button', onTap: () => tapped = true);
      manager.registerTestNode(node);

      manager.trigger('test_button');

      expect(tapped, true);
    });

    test('register and enter text', () {
      String enteredText = '';
      final node = TestNode(
        id: 'test_input',
        onTextChange: (text) => enteredText = text,
      );
      manager.registerTestNode(node);

      manager.enterText('test_input', 'Hello World');

      expect(enteredText, 'Hello World');
    });

    test('unregister node', () {
      final node = TestNode(id: 'test_node');
      manager.registerTestNode(node);

      expect(manager.activeTestNodes.containsKey('test_node'), true);

      manager.unregisterTestNode('test_node');

      expect(manager.activeTestNodes.containsKey('test_node'), false);
    });
  });
}
