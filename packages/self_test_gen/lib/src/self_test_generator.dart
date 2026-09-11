import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:self_test/annotations.dart';
import 'package:source_gen/source_gen.dart';

/// Generates a typed controller per annotated class.
///
/// A class carrying `@SelfTestButton('login_btn')` and
/// `@SelfTestInput('username_field')` gets a `<Class>TestController` with
/// `tapLoginBtn()`, `enterUsernameField(String)`,
/// `expectUsernameFieldText(String)` and existence assertions.
///
/// Method names are camelCase derived from the annotation id, so generated
/// code passes the same lints as hand-written code. The id itself stays
/// verbatim in the calls to [SelfTestManager], because that is the key the
/// widget registered itself under.
class SelfTestGenerator extends Generator {
  static const _buttonChecker = TypeChecker.typeNamed(
    SelfTestButton,
    inPackage: 'self_test',
  );
  static const _inputChecker = TypeChecker.typeNamed(
    SelfTestInput,
    inPackage: 'self_test',
  );

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    final buttons = <String, List<String>>{};
    final inputs = <String, List<String>>{};

    for (final classElement in library.classes) {
      // Null for an augmentation, which has nothing to generate a controller
      // from and no name to give one.
      final className = classElement.name;
      if (className == null) continue;

      // The class declaration itself, then everything declared inside it.
      // LibraryReader.annotatedWith only visits top-level declarations, so
      // walking members here is what makes annotating a handler work at all.
      for (final element in <Element>[
        classElement,
        ...classElement.methods,
        ...classElement.fields,
        ...classElement.getters,
        ...classElement.setters,
      ]) {
        for (final id in _idsOn(element, _buttonChecker)) {
          buttons.putIfAbsent(className, () => <String>[]).add(id);
        }
        for (final id in _idsOn(element, _inputChecker)) {
          inputs.putIfAbsent(className, () => <String>[]).add(id);
        }
      }
    }

    final classNames = <String>{...buttons.keys, ...inputs.keys}.toList()
      ..sort();
    if (classNames.isEmpty) return '';

    final controllers = classNames.map(
      (className) => _controller(
        className,
        buttons: _dedupe(buttons[className]),
        inputs: _dedupe(inputs[className]),
      ),
    );

    return [
      "import 'package:self_test/self_test.dart';",
      '',
      ...controllers,
    ].join('\n');
  }

  /// Every id [checker] annotates [element] with. A declaration may carry the
  /// annotation more than once, so this reads all of them, not just the first.
  Iterable<String> _idsOn(Element element, TypeChecker checker) => checker
      .annotationsOf(element)
      .map((annotation) => _annotationId(ConstantReader(annotation)));

  /// Ids in first-seen order, duplicates dropped: two handlers annotated with
  /// the same id would otherwise generate the same method twice.
  List<String> _dedupe(List<String>? ids) =>
      ids == null ? const [] : <String>{...ids}.toList();

  String _annotationId(ConstantReader annotation) =>
      annotation.read('id').stringValue;

  String _controller(
    String className, {
    required List<String> buttons,
    required List<String> inputs,
  }) {
    final methods = <String>[];

    for (final id in buttons) {
      final name = _camelCase(id);
      methods.add('''
  /// Invokes the callback registered for `$id`.
  void tap${_capitalize(name)}() {
    SelfTestManager().trigger('$id');
  }''');
    }

    for (final id in inputs) {
      final name = _camelCase(id);
      methods.add('''
  /// Sends [text] to the field registered for `$id`.
  void enter${_capitalize(name)}(String text) {
    SelfTestManager().enterText('$id', text);
  }

  /// Throws unless the field registered for `$id` currently holds
  /// [expectedText].
  void expect${_capitalize(name)}Text(String expectedText) {
    final node = SelfTestManager().activeTestNodes['$id'];
    if (node == null) {
      throw StateError('No self_test node registered for id "$id"');
    }
    if (node.currentText != expectedText) {
      throw StateError(
        'Expected "\$expectedText" in "$id" but found "\${node.currentText}"',
      );
    }
  }''');
    }

    for (final id in <String>{...buttons, ...inputs}) {
      final name = _capitalize(_camelCase(id));
      methods.add('''
  /// Throws unless a node is registered for `$id`.
  void expect${name}Exists() {
    if (!SelfTestManager().activeTestNodes.containsKey('$id')) {
      throw StateError('No self_test node registered for id "$id"');
    }
  }

  /// Throws if a node is registered for `$id`.
  void expect${name}DoesNotExist() {
    if (SelfTestManager().activeTestNodes.containsKey('$id')) {
      throw StateError('A self_test node is still registered for id "$id"');
    }
  }''');
    }

    // A Flutter State class is conventionally private, and
    // `_LoginFormStateTestController` could not be referenced from a test in
    // another library. The leading underscore is dropped so the generated
    // controller is always usable; the doc comment keeps the link honest.
    final controllerName = className.startsWith('_')
        ? className.substring(1)
        : className;

    return '''
/// Typed test controller for `$className`, generated by self_test_gen.
class ${controllerName}TestController {
${methods.join('\n\n')}
}
''';
  }

  /// `login_btn` -> `loginBtn`. Ids are keys chosen by the developer, so this
  /// tolerates dashes, spaces and repeated separators.
  String _camelCase(String id) {
    final parts = id
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'node';
    final head = parts.first.toLowerCase();
    final tail = parts.skip(1).map((part) {
      final lower = part.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    });
    final name = '$head${tail.join()}';
    return RegExp(r'^[0-9]').hasMatch(name) ? 'n$name' : name;
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
