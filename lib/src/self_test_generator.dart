import 'dart:async';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:self_test/annotations.dart';

class SelfTestGenerator extends Generator {
  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    final controllers = <String, Map<String, String>>{};

    // Collect annotations
    for (final annotatedElement in library.annotatedWith(TypeChecker.fromRuntime(SelfTestButton))) {
      final element = annotatedElement.element;
      final annotation = annotatedElement.annotation;
      final id = _getAnnotationId(annotation);
      final className = _getEnclosingClassName(element);
      if (className != null) {
        controllers.putIfAbsent(className, () => {});
        controllers[className]!['tap_$id'] = id;
      }
    }

    for (final annotatedElement in library.annotatedWith(TypeChecker.fromRuntime(SelfTestInput))) {
      final element = annotatedElement.element;
      final annotation = annotatedElement.annotation;
      final id = _getAnnotationId(annotation);
      final className = _getEnclosingClassName(element);
      if (className != null) {
        controllers.putIfAbsent(className, () => {});
        controllers[className]!['enterText_$id'] = id;
      }
    }

    // Generate controller classes
    final generated = controllers.entries.map((entry) {
      final className = entry.key;
      final methods = entry.value;
      return _generateController(className, methods);
    }).join('\n\n');

    return generated;
  }

  String _getAnnotationId(ConstantReader annotation) {
    return annotation.read('id').stringValue;
  }

  String? _getEnclosingClassName(Element element) {
    Element? current = element;
    while (current != null) {
      if (current is ClassElement) {
        return current.name;
      }
      current = current.enclosingElement;
    }
    return null;
  }

  String _generateController(String className, Map<String, String> methods) {
    final methodDefs = <String>[];

    // Action methods
    for (final entry in methods.entries) {
      final methodName = entry.key;
      final id = entry.value;
      if (methodName.startsWith('tap_')) {
        methodDefs.add('''
  void $methodName() {
    SelfTestManager().trigger('$id');
  }''');
      } else if (methodName.startsWith('enterText_')) {
        methodDefs.add('''
  void $methodName(String text) {
    SelfTestManager().enterText('$id', text);
  }''');
      }
    }

    // Assertion methods
    final ids = methods.values.toSet();
    for (final id in ids) {
      methodDefs.add('''
  void expectExists_$id() {
    if (!SelfTestManager().activeTestNodes.containsKey('$id')) {
      throw Exception('TestNode with id "$id" does not exist');
    }
  }
  
  void expectNotExists_$id() {
    if (SelfTestManager().activeTestNodes.containsKey('$id')) {
      throw Exception('TestNode with id "$id" should not exist');
    }
  }''');
    }

    // For text inputs, add text assertions (placeholder)
    final textIds = methods.entries.where((e) => e.key.startsWith('enterText_')).map((e) => e.value);
    for (final id in textIds) {
      methodDefs.add('''
  void expectText_$id(String expectedText) {
    // TODO: Implement text retrieval from widget
    // For now, this is a placeholder
    throw UnimplementedError('Text assertion not yet implemented');
  }''');
    }

    return '''
class ${className}TestController {
${methodDefs.join('\n')}
}''';
  }
}
