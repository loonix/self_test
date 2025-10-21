import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dart:io';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  group('SelfTestManager', () {
    late SelfTestManager manager;

    setUp(() {
      manager = SelfTestManager();
      manager.setTestMode(true);
    });

    test('registers and triggers test node', () async {
      bool tapped = false;
      final node = TestNode(
        id: 'test_button',
        onTap: () => tapped = true,
      );

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

    test('recording mode records actions', () async {
      await manager.initializeDatabase();

      // Clear any existing data from previous tests
      await manager.clearDatabase();

      await manager.startRecording('Test Script');

      final node = TestNode(
        id: 'test_button',
        onTap: () {},
      );
      manager.registerTestNode(node);

      await manager.trigger('test_button');

      final scripts = manager.getTestScripts();
      expect(scripts.length, 1);
      expect(scripts.first.name, 'Test Script');

      final steps = manager.getTestSteps(scripts.first.id);
      expect(steps.length, 1);
      expect(steps.first.action, 'trigger');
      expect(steps.first.targetId, 'test_button');
    });
  });
}
