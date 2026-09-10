import 'package:flutter/widgets.dart';

import '../core/manager.dart';

/// Marks the subtree that [SelfTestManager.captureScreenshot] photographs.
///
/// Wrap the app (or the one screen you care about) in this widget. It installs
/// a real [RepaintBoundary] and hands its key to the manager, which is what
/// makes the capture deterministic: without a boundary the manager has to walk
/// the render tree and photograph the first one it finds, which may not be the
/// subtree under test.
class ScreenshotBoundary extends StatefulWidget {
  final Widget child;

  const ScreenshotBoundary({super.key, required this.child});

  @override
  State<ScreenshotBoundary> createState() => _ScreenshotBoundaryState();
}

class _ScreenshotBoundaryState extends State<ScreenshotBoundary> {
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SelfTestManager().setScreenshotKey(_boundaryKey);
      if (SelfTestManager.verboseLogging) {
        debugPrint('[SelfTest] ScreenshotBoundary key registered');
      }
    });
  }

  @override
  void dispose() {
    SelfTestManager().clearScreenshotKey(_boundaryKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _boundaryKey, child: widget.child);
  }
}
