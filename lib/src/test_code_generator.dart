import 'dart:convert';
import 'dart:io';
import 'package:dart_style/dart_style.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class TestCodeGenerator {
  final DartFormatter _formatter = DartFormatter();

  /// Generates Dart test code for a given TestScript and its steps.
  String generateTestCode(TestScript script, List<TestStep> steps) {
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

  /// Exports the test script and steps to JSON format.
  Future<void> exportToJson(TestScript script, List<TestStep> steps) async {
    try {
      debugPrint('[TestCodeGenerator] Exporting script to JSON: ${script.name}');
      final jsonData = {
        'script': script.toJson(),
        'steps': steps.map((step) => step.toJson()).toList(),
        'exportedAt': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      final fileName = '${script.name.replaceAll(' ', '_').toLowerCase()}_test.json';
      final dir = await getApplicationDocumentsDirectory();
      final testDir = Directory('${dir.path}/test_generated');
      if (!testDir.existsSync()) {
        testDir.createSync(recursive: true);
        debugPrint('[TestCodeGenerator] Created test_generated directory in documents');
      }
      final file = File(path.join(testDir.path, fileName));
      await file.writeAsString(jsonString);
      debugPrint('[TestCodeGenerator] Exported test to JSON: ${file.path}');
    } catch (e, stackTrace) {
      debugPrint('[TestCodeGenerator] ERROR exporting to JSON: $e');
      debugPrint('[TestCodeGenerator] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Exports the test script and steps to Dart test code format.
  Future<void> exportToDart(TestScript script, List<TestStep> steps) async {
    try {
      debugPrint('[TestCodeGenerator] Exporting script to Dart: ${script.name}');
      final dartCode = generateTestCode(script, steps);
      final fileName = '${script.name.replaceAll(' ', '_').toLowerCase()}_test.dart';
      final dir = await getApplicationDocumentsDirectory();
      final testDir = Directory('${dir.path}/test_generated');
      if (!testDir.existsSync()) {
        testDir.createSync(recursive: true);
        debugPrint('[TestCodeGenerator] Created test_generated directory in documents');
      }
      final file = File(path.join(testDir.path, fileName));
      await file.writeAsString(dartCode);
      debugPrint('[TestCodeGenerator] Exported test to Dart: ${file.path}');
    } catch (e, stackTrace) {
      debugPrint('[TestCodeGenerator] ERROR exporting to Dart: $e');
      debugPrint('[TestCodeGenerator] Stack trace: $stackTrace');
      rethrow;
    }
  }
}
