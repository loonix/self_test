import 'dart:convert';

import 'locator/locator.dart';
import 'models.dart';

/// Turns a recorded [TestScript] into source a developer can commit.
///
/// Every method returns a string and touches no filesystem. Deciding where
/// generated code goes belongs to the host app, which is also why this class
/// pulls in no path or storage dependency. It also does its own formatting
/// rather than calling a formatter: `dart_style` depends on `analyzer`, and
/// pulling both into every app that depends on self_test is a steep price for
/// tidy indentation in a string this class fully controls.
class TestCodeGenerator {
  /// Generates a `flutter_test` file replaying [steps] against [script].
  ///
  /// Pass [appExpression] to have the generated file pump the app for you, for
  /// example `MyApp()`. Without it the file leaves a marked gap, because a
  /// recorder cannot know which widget is the app's root.
  String generateTestCode(
    TestScript script,
    List<RecordedStep> steps, {
    String? appExpression,
    String? appImport,
  }) {
    final buffer = StringBuffer()
      ..writeln("import 'package:flutter_test/flutter_test.dart';")
      ..writeln("import 'package:self_test/self_test.dart';");
    if (appImport != null) {
      buffer.writeln("import ${_literal(appImport)};");
    }
    buffer
      ..writeln()
      ..writeln('void main() {')
      ..writeln('  final manager = SelfTestManager();')
      ..writeln()
      ..writeln('  tearDown(manager.clearClock);')
      ..writeln()
      ..writeln('  testWidgets(${_literal(script.name)}, (tester) async {')
      // A held press needs the clock the test owns; without this a long press
      // in a recording replays as a tap and quietly passes.
      ..writeln('    manager.useClock(tester.pump);');

    if (appExpression != null) {
      buffer.writeln('    await tester.pumpWidget($appExpression);');
    } else {
      buffer.writeln('    // Pump your app here, then delete this line.');
    }
    buffer.writeln('    await tester.pumpAndSettle();');

    if (steps.isEmpty) {
      buffer.writeln('    // Nothing was recorded for this script.');
    }

    for (final step in steps) {
      final target = _locatorExpression(step);
      switch (step.action) {
        case 'trigger':
          buffer
            ..writeln('    await manager.tap($target);')
            ..writeln('    await tester.pumpAndSettle();');
        case 'doubleTap':
          buffer
            ..writeln('    await manager.doubleTap($target);')
            ..writeln('    await tester.pumpAndSettle();');
        case 'longPress':
          buffer
            ..writeln('    await manager.longPress($target);')
            ..writeln('    await tester.pumpAndSettle();');
        case 'enterText':
          buffer
            ..writeln(
              '    await manager.typeInto($target, ${_literal(step.value ?? '')});',
            )
            ..writeln('    await tester.pumpAndSettle();');
        case 'submit':
          buffer
            ..writeln('    await manager.submit($target);')
            ..writeln('    await tester.pumpAndSettle();');
        case 'assertText':
          buffer.writeln(
            '    expect(manager.readText($target), ${_literal(step.value ?? '')});',
          );
        case 'assertExists':
          buffer.writeln('    expect(manager.exists($target), isTrue);');
        default:
          buffer.writeln(
            '    // Unsupported recorded action ${_literal(step.action)}, skipped.',
          );
      }
    }

    buffer
      ..writeln('  });')
      ..writeln('}');

    return buffer.toString();
  }

  /// The Dart source for the locator a step replays against.
  ///
  /// A step recorded before locators existed carries only an id, and
  /// `SelfTestLocator.id` is exactly what replaying that means.
  String _locatorExpression(RecordedStep step) {
    final locator = step.target;
    final value = _literal(locator.value);
    final constructor = switch (locator.strategy) {
      LocatorStrategy.id => 'SelfTestLocator.id($value)',
      LocatorStrategy.key => 'SelfTestLocator.key($value)',
      LocatorStrategy.text =>
        locator.exact
            ? 'SelfTestLocator.text($value)'
            : 'SelfTestLocator.text($value, exact: false)',
      LocatorStrategy.semanticsLabel => 'SelfTestLocator.semantics($value)',
      LocatorStrategy.type => 'SelfTestLocator.type($value)',
      LocatorStrategy.tooltip => 'SelfTestLocator.tooltip($value)',
    };
    // `at` is an instance method, so `const X.at(1)` does not compile. Only
    // the plain constructor can be const.
    return locator.index == 0
        ? 'const $constructor'
        : '$constructor.at(${locator.index})';
  }

  /// Serializes the script and its steps to an indented JSON document.
  String generateJsonExport(TestScript script, List<RecordedStep> steps) {
    final jsonData = {
      'script': script.toJson(),
      'steps': steps.map((step) => step.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
      'version': '1.0',
    };
    return const JsonEncoder.withIndent('  ').convert(jsonData);
  }

  /// A filename for [script], e.g. `login_flow_test.dart`.
  String fileNameFor(TestScript script, {required String extension}) {
    final slug = script.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${slug.isEmpty ? 'test' : slug}_test.$extension';
  }

  /// A single-quoted Dart string literal for [value].
  ///
  /// Recorded values are whatever the user typed into the app, so they can
  /// hold quotes, backslashes, newlines or `$`. Interpolating them raw
  /// produced source that either failed to compile or picked up an unintended
  /// interpolation.
  String _literal(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll(r'$', r'\$')
        .replaceAll("'", r"\'")
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n');
    return "'$escaped'";
  }
}
