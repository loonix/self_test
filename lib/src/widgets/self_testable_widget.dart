import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/manager.dart';
import '../core/recording_mode.dart';
import '../core/test_node.dart';

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
  bool _wasRegistered = false;

  @override
  void initState() {
    super.initState();
    _updateRegistration();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRegistration();
  }

  @override
  void didUpdateWidget(SelfTestableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      // ID changed, need to unregister old and register new
      _unregisterIfNeeded();
      _updateRegistration();
    }
  }

  void _updateRegistration() {
    try {
      final manager = SelfTestManager();
      final shouldBeRegistered =
          ((kDebugMode || kProfileMode) && manager.isSelfTestModeActive) ||
          manager.isTestMode;

      if (shouldBeRegistered && !_wasRegistered) {
        if (SelfTestManager.verboseLogging) {
          debugPrint(
            '[SelfTest] SelfTestableWidget "${widget.id}" registering (mode active: ${manager.isSelfTestModeActive}, test mode: ${manager.isTestMode})',
          );
        }
        final node = TestNode(
          id: widget.id,
          onTap: widget.onTap,
          onTextChange: widget.onTextChange,
          context: context,
        );
        manager.registerTestNode(node);
        _wasRegistered = true;
      } else if (!shouldBeRegistered && _wasRegistered) {
        if (SelfTestManager.verboseLogging) {
          debugPrint(
            '[SelfTest] SelfTestableWidget "${widget.id}" unregistering due to mode change',
          );
        }
        manager.unregisterTestNode(widget.id);
        _wasRegistered = false;
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[SelfTest] ERROR in _updateRegistration for "${widget.id}": $e',
      );
      debugPrint('[SelfTest] Stack trace: $stackTrace');
    }
  }

  void _unregisterIfNeeded() {
    if (_wasRegistered) {
      SelfTestManager().unregisterTestNode(widget.id);
      _wasRegistered = false;
    }
  }

  @override
  void dispose() {
    _unregisterIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ensure registration is up to date on every build
    _updateRegistration();

    final manager = SelfTestManager();
    final isRecording = manager.recordingMode == RecordingMode.recording;
    final isAsserting = manager.recordingMode == RecordingMode.asserting;
    final child = widget.child;

    if (isAsserting) {
      debugPrint(
        '[SelfTest] Building SelfTestableWidget "${widget.id}" with assertion highlight',
      );
      return GestureDetector(
        onTap: () => manager.addAssertion(widget.id),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFF0000), width: 2),
          ),
          child: child,
        ),
      );
    }

    // Intercept interactions for recording or testing
    if (isRecording || manager.isTestMode) {
      // First, check if there's a registered builder for this widget type
      final registeredBuilder = manager.getRecordingBuilder(child.runtimeType);
      if (registeredBuilder != null) {
        return registeredBuilder(child, widget);
      }

      // Final fallback: wrap in GestureDetector if onTap is provided, otherwise return as-is with warning
      if (widget.onTap != null) {
        SelfTestManager.printWarning(
          'No recording builder found for ${child.runtimeType}, wrapping in GestureDetector for tap recording',
        );
        return GestureDetector(
          onTap: () async {
            await manager.trigger(widget.id);
            widget.onTap!();
          },
          child: child,
        );
      } else {
        SelfTestManager.printWarning(
          'No recording builder found for ${child.runtimeType} and no onTap provided - interactions will not be recorded',
        );
        return child;
      }
    }

    return child;
  }
}
