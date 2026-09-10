import 'dart:convert';
import 'package:dart_style/dart_style.dart';
import 'models.dart';

/// Turns a recorded [TestScript] into source a developer can commit.
///
/// Every method returns a string and touches no filesystem. Deciding where
/// generated code goes belongs to the host app, which is also why this class
/// pulls in no path or storage dependency.
class TestCodeGenerator {
  final DartFormatter _formatter = DartFormatter();

  /// Generates Dart test code for a given TestScript and its steps.
  String generateTestCode(TestScript script, List<RecordedStep> steps) {
    final buffer = StringBuffer();

    buffer.writeln("import 'package:flutter_test/flutter_test.dart';");
    buffer.writeln("import 'package:self_test/self_test.dart';");
    buffer.writeln();
    buffer.writeln("void main() {");
    buffer.writeln("  late SelfTestManager manager;");
    buffer.writeln();
    buffer.writeln("  setUp(() async {");
    buffer.writeln("    manager = SelfTestManager();");
    buffer.writeln("    manager.setTestMode(true);");
    buffer.writeln("    // Initialize your app here if needed");
    buffer.writeln("  });");
    buffer.writeln();
    buffer.writeln("  test('${script.name}', () async {");
    buffer.writeln("    // Recorded test steps");

    for (final step in steps) {
      switch (step.action) {
        case 'trigger':
          buffer.writeln("    await manager.trigger('${step.targetId}');");
          buffer.writeln("    await manager.waitForAnimations();");
          break;
        case 'enterText':
          buffer.writeln("    await manager.enterText('${step.targetId}', '${step.value}');");
          buffer.writeln("    await manager.waitForAnimations();");
          break;
        case 'assertText':
          buffer.writeln("    final node = manager.activeTestNodes['${step.targetId}'];");
          buffer.writeln("    expect(node?.currentText, '${step.value}');");
          break;
        case 'assertExists':
          buffer.writeln("    expect(manager.activeTestNodes.containsKey('${step.targetId}'), true);");
          break;
      }
    }

    buffer.writeln("  });");
    buffer.writeln("}");

    return _formatter.format(buffer.toString());
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
}
