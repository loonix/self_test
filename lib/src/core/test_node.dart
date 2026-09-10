import 'package:flutter/widgets.dart';

/// Represents a testable node in the widget tree.
class TestNode {
  final String id;
  final VoidCallback? onTap;
  final ValueSetter<String>? onTextChange;
  final BuildContext? context;
  String? currentText; // For text assertions

  TestNode({
    required this.id,
    this.onTap,
    this.onTextChange,
    this.context,
    this.currentText,
  });
}
