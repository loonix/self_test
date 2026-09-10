import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:self_test_devtools_extension/src/self_test_extension.dart';

void main() {
  runApp(const SelfTestDevToolsExtension());
}

class SelfTestDevToolsExtension extends StatelessWidget {
  const SelfTestDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return DevToolsExtension(child: SelfTestExtension());
  }
}
