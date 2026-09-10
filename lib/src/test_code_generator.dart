import 'dart:convert';

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
  String generateTestCode(TestScript script, List<RecordedStep> steps) {
    final buffer = StringBuffer()
      ..writeln("import 'package:flutter_test/flutter_test.dart';")
      ..writeln("import 'package:self_test/self_test.dart';")
      ..writeln()
      ..writeln('void main() {')
      ..writeln('  late SelfTestManager manager;')
      ..writeln()
      ..writeln('  setUp(() {')
      ..writeln('    manager = SelfTestManager();')
      ..writeln('    manager.setTestMode(true);')
      ..writeln('    // Pump your app here so its widgets register themselves.')
      ..writeln('  });')
      ..writeln()
      ..writeln('  test(${_literal(script.name)}, () async {');

    if (steps.isEmpty) {
      buffer.writeln('    // Nothing was recorded for this script.');
    }

    // Assertion locals get numbered names: two assertText steps in one test
    // body would otherwise both declare `node` and the generated file would
    // not compile.
    var localIndex = 0;
    for (final step in steps) {
      final target = _literal(step.targetId);
      switch (step.action) {
        case 'trigger':
          buffer
            ..writeln('    await manager.trigger($target);')
            ..writeln('    await manager.waitForAnimations();');
        case 'enterText':
          buffer
            ..writeln(
                '    await manager.enterText($target, ${_literal(step.value ?? '')});')
            ..writeln('    await manager.waitForAnimations();');
        case 'assertText':
          final local = 'node${localIndex++}';
          buffer
            ..writeln('    final $local = manager.activeTestNodes[$target];')
            ..writeln(
                '    expect($local?.currentText, ${_literal(step.value ?? '')});');
        case 'assertExists':
          buffer.writeln(
              '    expect(manager.activeTestNodes.containsKey($target), isTrue);');
        default:
          buffer.writeln(
              '    // Unsupported recorded action ${_literal(step.action)}, skipped.');
      }
    }

    buffer
      ..writeln('  });')
      ..writeln('}');

    return buffer.toString();
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
