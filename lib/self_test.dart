library self_test;

export 'annotations.dart';

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Represents a testable node in the widget tree.
class TestNode {
  final String id;
  final VoidCallback? onTap;
  final ValueSetter<String>? onTextChange;
  final BuildContext? context;

  TestNode({
    required this.id,
    this.onTap,
    this.onTextChange,
    this.context,
  });
}

/// Singleton manager for self-testing functionality.
class SelfTestManager {
  static final SelfTestManager _instance = SelfTestManager._internal();
  factory SelfTestManager() => _instance;
  SelfTestManager._internal();

  final Map<String, TestNode> _activeTestNodes = {};
  bool _isSelfTestModeActive = false;
  bool _isTestMode = false; // For testing environments
  GlobalKey<State>? rootKey;

  /// Gets the current self-test mode status.
  bool get isSelfTestModeActive => _isSelfTestModeActive;

  /// Sets the self-test mode status.
  void setSelfTestModeActive(bool value) {
    _isSelfTestModeActive = value;
  }

  /// Gets the test mode status (for testing environments).
  bool get isTestMode => _isTestMode;

  /// Sets the test mode status.
  void setTestMode(bool value) {
    _isTestMode = value;
  }

  /// Restarts the widget tree by setting state on the root key.
  void restartWidgetTree() {
    if (rootKey?.currentState != null) {
      (rootKey!.currentState as dynamic).setState(() {});
    }
  }

  /// Gets the active test nodes (for testing purposes).
  Map<String, TestNode> get activeTestNodes => _activeTestNodes;

  /// Registers a test node.
  void registerTestNode(TestNode node) {
    _activeTestNodes[node.id] = node;
  }

  /// Unregisters a test node.
  void unregisterTestNode(String id) {
    _activeTestNodes.remove(id);
  }

  /// Triggers the tap action for the given id.
  void trigger(String id) {
    final node = _activeTestNodes[id];
    if (node != null && node.onTap != null) {
      node.onTap!();
    } else {
      throw Exception('TestNode with id "$id" not found or has no tap callback.');
    }
  }

  /// Enters text for the given id.
  void enterText(String id, String text) {
    final node = _activeTestNodes[id];
    if (node != null && node.onTextChange != null) {
      node.onTextChange!(text);
    } else {
      throw Exception('TestNode with id "$id" not found or has no text change callback.');
    }
  }

  /// Waits for animations to complete (simulates pumpAndSettle).
  Future<void> waitForAnimations() async {
    // Simple delay; in real implementation, might need more sophisticated logic
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

/// A wrapper widget that makes a child widget testable in self-test mode.
class SelfTestableWidget extends StatefulWidget {
  final String id;
  final Widget child;
  final VoidCallback? onTap;
  final ValueSetter<String>? onTextChange;

  const SelfTestableWidget({
    super.key,
    required this.id,
    required this.child,
    this.onTap,
    this.onTextChange,
  });

  @override
  State<SelfTestableWidget> createState() => _SelfTestableWidgetState();
}

class _SelfTestableWidgetState extends State<SelfTestableWidget> {
  @override
  void initState() {
    super.initState();
    final manager = SelfTestManager();
    if (((kDebugMode || kProfileMode) && manager.isSelfTestModeActive) || manager.isTestMode) {
      final node = TestNode(
        id: widget.id,
        onTap: widget.onTap,
        onTextChange: widget.onTextChange,
        context: context,
      );
      manager.registerTestNode(node);
    }
  }

  @override
  void dispose() {
    final manager = SelfTestManager();
    if (((kDebugMode || kProfileMode) && manager.isSelfTestModeActive) || manager.isTestMode) {
      manager.unregisterTestNode(widget.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A wrapper widget for the root of the app to enable programmatic restart.
class SelfTestRoot extends StatefulWidget {
  final Widget child;

  const SelfTestRoot({super.key, required this.child});

  @override
  State<SelfTestRoot> createState() => _SelfTestRootState();
}

class _SelfTestRootState extends State<SelfTestRoot> {
  @override
  void initState() {
    super.initState();
    SelfTestManager().rootKey ??= GlobalKey<State>(debugLabel: 'SelfTestRoot');
  }

  @override
  Widget build(BuildContext context) {
    return Container(key: SelfTestManager().rootKey, child: widget.child);
  }
}
