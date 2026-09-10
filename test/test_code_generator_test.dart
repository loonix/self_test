import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

void main() {
  _regressionTests();

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
        RecordedStep(
          id: 1,
          scriptId: 1,
          order: 0,
          action: 'enterText',
          targetId: 'username',
          value: 'user@example.com',
        ),
        RecordedStep(
          id: 2,
          scriptId: 1,
          order: 1,
          action: 'enterText',
          targetId: 'password',
          value: 'password123',
        ),
        RecordedStep(
          id: 3,
          scriptId: 1,
          order: 2,
          action: 'trigger',
          targetId: 'login_button',
        ),
        RecordedStep(
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
      expect(code,
          contains("await manager.enterText('username', 'user@example.com');"));
      expect(code, contains("await manager.trigger('login_button');"));
      // node0, not node: assertion locals are numbered so two assertText
      // steps in one body cannot redeclare the same name.
      expect(code, contains("expect(node0?.currentText, 'Welcome!');"));
    });
  });
}

void _regressionTests() {
  group('generated source is valid Dart', () {
    final generator = TestCodeGenerator();
    final script = TestScript(
      id: 1,
      name: 'login flow',
      createdAt: DateTime.utc(2026, 9, 10),
    );

    RecordedStep step(String action, String targetId,
            {String? value, int id = 0}) =>
        RecordedStep(
          id: id,
          scriptId: 1,
          order: id,
          action: action,
          targetId: targetId,
          value: value,
        );

    test('numbers assertion locals so two assertText steps do not collide', () {
      final source = generator.generateTestCode(script, [
        step('assertText', 'username', value: 'a', id: 0),
        step('assertText', 'password', value: 'b', id: 1),
      ]);

      // Two `final node = ...` in one block would not compile.
      expect(source.contains('final node0 ='), isTrue);
      expect(source.contains('final node1 ='), isTrue);
      expect(RegExp(r'final node\d+ =').allMatches(source).length, 2);
    });

    test('escapes a recorded value holding a quote', () {
      final source = generator.generateTestCode(script, [
        step('enterText', 'username', value: "O'Brien"),
      ]);

      expect(source.contains(r"\'Brien"), isTrue);
      expect(source.contains("'O'Brien'"), isFalse);
    });

    test('escapes a dollar sign so it is not read as interpolation', () {
      final source = generator.generateTestCode(script, [
        step('enterText', 'amount', value: r'$100'),
      ]);

      expect(source.contains(r'\$100'), isTrue);
    });

    test('escapes newlines rather than breaking the literal across lines', () {
      final source = generator.generateTestCode(script, [
        step('enterText', 'notes', value: 'line one\nline two'),
      ]);

      expect(source.contains(r'line one\nline two'), isTrue);
      expect(source.split('\n').where((l) => l.contains('line one')).length, 1);
    });

    test('a null recorded value becomes an empty literal, not the word null',
        () {
      final source = generator.generateTestCode(script, [
        step('enterText', 'username'),
      ]);

      expect(source.contains("enterText('username', '')"), isTrue);
      expect(source.contains('null'), isFalse);
    });

    test('an unknown action is commented, not silently dropped', () {
      final source = generator.generateTestCode(script, [
        step('teleport', 'username'),
      ]);

      expect(source.contains('Unsupported recorded action'), isTrue);
    });

    test('an empty script still produces a runnable test body', () {
      final source = generator.generateTestCode(script, const []);

      expect(source.contains('Nothing was recorded'), isTrue);
      expect(source.contains('void main()'), isTrue);
    });

    test('a script name with a quote does not break the test declaration', () {
      final source = generator.generateTestCode(
        TestScript(
            id: 2, name: "user's login", createdAt: DateTime.utc(2026, 9, 10)),
        const [],
      );

      expect(source.contains(r"test('user\'s login'"), isTrue);
    });
  });
}
