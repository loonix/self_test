import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test/src/models.dart';

void main() {
  group('TestCodeGenerator', () {
    late TestCodeGenerator generator;

    setUp(() {
      generator = TestCodeGenerator();
    });

    test('generates correct test code', () {
      final script = TestScript(
        id: 1,
        name: 'Login Test',
        createdAt: DateTime(2023, 1, 1),
      );

      final steps = [
        TestStep(
          id: 1,
          scriptId: 1,
          order: 0,
          action: 'enterText',
          targetId: 'username',
          value: 'user@example.com',
        ),
        TestStep(
          id: 2,
          scriptId: 1,
          order: 1,
          action: 'enterText',
          targetId: 'password',
          value: 'password123',
        ),
        TestStep(
          id: 3,
          scriptId: 1,
          order: 2,
          action: 'trigger',
          targetId: 'login_button',
        ),
        TestStep(
          id: 4,
          scriptId: 1,
          order: 3,
          action: 'assertText',
          targetId: 'welcome_message',
          value: 'Welcome!',
        ),
      ];

      final code = generator.generateTestCode(script, steps);

      expect(code, contains("test('Login Test'"));
      expect(code, contains("await manager.enterText('username', 'user@example.com');"));
      expect(code, contains("await manager.trigger('login_button');"));
      expect(code, contains("expect(node?.currentText, 'Welcome!');"));
    });
  });
}
