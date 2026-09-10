import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:self_test_gen/builder.dart';
import 'package:test/test.dart';

/// Runs the builder over [source] and returns the generated library, or null
/// when the generator produced nothing.
Future<String?> generate(String source) async {
  final result = await testBuilders(
    [selfTestBuilder(BuilderOptions.empty)],
    {
      'a|lib/input.dart': source,
      // The generator matches on these annotations, so they have to resolve.
      // Stubbed rather than read from the real package: it keeps the test
      // hermetic, and the generator only ever looks at the annotation's name
      // and its single id argument.
      'self_test|lib/annotations.dart': '''
class SelfTestButton {
  final String id;
  const SelfTestButton(this.id);
}

class SelfTestInput {
  final String id;
  const SelfTestInput(this.id);
}
''',
      'self_test|lib/self_test.dart': "export 'annotations.dart';",
    },
    // Without this build_test picks the root from an unordered set of the
    // packages it was handed, so the builder sometimes ran against
    // `self_test` and wrote its output there instead.
    rootPackage: 'a',
    generateFor: {'a|lib/input.dart'},
  );

  final readerWriter = result.readerWriter;
  final id = AssetId('a', 'lib/input.g.dart');
  if (!readerWriter.testing.assetsWritten.contains(id)) return null;

  // build_test reports the output under its logical id but stores it beneath
  // the build's generated directory, so reading the logical id directly finds
  // nothing.
  return readerWriter.readAsString(
    AssetId('a', '.dart_tool/build/generated/a/lib/input.g.dart'),
  );
}

void main() {
  _privateClassNames();

  test('emits nothing for a library with no annotations', () async {
    final generated = await generate('class Plain {}');
    expect(generated, isNull);
  });

  test('derives camelCase method names from a snake_case id', () async {
    final generated = await generate('''
import 'package:self_test/annotations.dart';

class LoginForm {
  @SelfTestButton('login_btn')
  void onLogin() {}

  @SelfTestInput('username_field')
  void onUsername(String value) {}
}
''');

    expect(generated, isNotNull);
    expect(generated, contains('class LoginFormTestController'));
    // The documented API. Snake_case here would make generated code fail the
    // same lints the rest of the project is held to.
    expect(generated, contains('void tapLoginBtn()'));
    expect(generated, contains('void enterUsernameField(String text)'));
    expect(
      generated,
      contains('void expectUsernameFieldText(String expectedText)'),
    );
    expect(generated, contains('void expectLoginBtnExists()'));
    expect(generated, contains('void expectLoginBtnDoesNotExist()'));
    // The id itself must survive verbatim: it is the registration key.
    expect(generated, contains("trigger('login_btn')"));
    expect(generated, contains("enterText('username_field', text)"));
  });

  test('finds an annotation on the class declaration too', () async {
    final generated = await generate('''
import 'package:self_test/annotations.dart';

@SelfTestButton('submit')
class Form {}
''');

    expect(generated, contains('void tapSubmit()'));
  });

  test('handles dashes, spaces and repeated separators in an id', () async {
    final generated = await generate('''
import 'package:self_test/annotations.dart';

class Screen {
  @SelfTestButton('save--now button')
  void onSave() {}
}
''');

    expect(generated, contains('void tapSaveNowButton()'));
    expect(generated, contains("trigger('save--now button')"));
  });

  test(
    'prefixes an id starting with a digit so the method name is legal',
    () async {
      final generated = await generate('''
import 'package:self_test/annotations.dart';

class Screen {
  @SelfTestButton('2fa_submit')
  void onSubmit() {}
}
''');

      expect(generated, contains('void tapN2faSubmit()'));
    },
  );

  test('generates one method per id when two handlers share an id', () async {
    final generated = await generate('''
import 'package:self_test/annotations.dart';

class Screen {
  @SelfTestButton('save')
  void onSaveA() {}

  @SelfTestButton('save')
  void onSaveB() {}
}
''');

    expect('void tapSave()'.allMatches(generated!).length, 1);
  });

  test('generates a controller per annotated class, sorted', () async {
    final generated = await generate('''
import 'package:self_test/annotations.dart';

class Zeta {
  @SelfTestButton('z')
  void onZ() {}
}

class Alpha {
  @SelfTestButton('a')
  void onA() {}
}
''');

    expect(generated, contains('class AlphaTestController'));
    expect(generated, contains('class ZetaTestController'));
    expect(
      generated!.indexOf('AlphaTestController'),
      lessThan(generated.indexOf('ZetaTestController')),
    );
  });

  test(
    'emits the self_test import so the output is a standalone library',
    () async {
      final generated = await generate('''
import 'package:self_test/annotations.dart';

class Screen {
  @SelfTestButton('go')
  void onGo() {}
}
''');

      expect(generated, contains("import 'package:self_test/self_test.dart';"));
      // Not a part file: a `part` directive pointing at a library is a compile
      // error, and the README used to tell people to write one.
      expect(generated, isNot(contains('part of')));
    },
  );
}

void _privateClassNames() {
  test('drops the leading underscore of a private class name', () async {
    final generated = await generate('''
import 'package:self_test/annotations.dart';

class _LoginFormState {
  @SelfTestButton('login_btn')
  void onLogin() {}
}
''');

    // _LoginFormStateTestController would be unreferenceable from a test in
    // another library, which is where tests live.
    expect(generated, contains('class LoginFormStateTestController'));
    expect(generated, isNot(contains('class _LoginFormState')));
  });
}
