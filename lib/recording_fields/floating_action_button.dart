import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

/// Builds a recording-enabled FloatingActionButton.
Widget buildRecordingFloatingActionButton(FloatingActionButton fab, SelfTestableWidget widget) {
  return FloatingActionButton(
    key: fab.key,
    child: fab.child,
    tooltip: fab.tooltip,
    foregroundColor: fab.foregroundColor,
    backgroundColor: fab.backgroundColor,
    focusColor: fab.focusColor,
    hoverColor: fab.hoverColor,
    splashColor: fab.splashColor,
    elevation: fab.elevation,
    focusElevation: fab.focusElevation,
    hoverElevation: fab.hoverElevation,
    highlightElevation: fab.highlightElevation,
    disabledElevation: fab.disabledElevation,
    onPressed: fab.onPressed != null
        ? () async {
            debugPrint('[SelfTest] Recording FloatingActionButton tap for "${widget.id}"');
            await SelfTestManager().trigger(widget.id);
            fab.onPressed!();
            widget.onTap?.call();
          }
        : null,
    mouseCursor: fab.mouseCursor,
    mini: fab.mini,
    shape: fab.shape,
    clipBehavior: fab.clipBehavior,
    focusNode: fab.focusNode,
    autofocus: fab.autofocus,
    materialTapTargetSize: fab.materialTapTargetSize,
    isExtended: fab.isExtended,
    enableFeedback: fab.enableFeedback,
  );
}
