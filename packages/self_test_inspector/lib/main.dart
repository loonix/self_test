import 'package:flutter/material.dart';
import 'package:self_test_inspector/src/self_test_inspector.dart';

void main() {
  runApp(const SelfTestInspectorApp());
}

class SelfTestInspectorApp extends StatelessWidget {
  const SelfTestInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self-Test Inspector',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SelfTestInspector(),
    );
  }
}
