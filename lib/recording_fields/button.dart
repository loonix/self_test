import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

Widget buildRecordingButton(Widget button, widget) {
  if (button is ElevatedButton) {
    return ElevatedButton(
      onPressed: () async {
        debugPrint('[SelfTest] Recording tap for "${widget.id}"');
        await SelfTestManager().recordTap(widget.id);
        (button.onPressed ?? widget.onTap)?.call();
      },
      onLongPress: button.onLongPress,
      onHover: button.onHover,
      onFocusChange: button.onFocusChange,
      style: button.style,
      focusNode: button.focusNode,
      autofocus: button.autofocus,
      clipBehavior: button.clipBehavior,
      child: button.child ?? const SizedBox(),
    );
  } else if (button is TextButton) {
    return TextButton(
      onPressed: () async {
        debugPrint('[SelfTest] Recording tap for "${widget.id}"');
        await SelfTestManager().recordTap(widget.id);
        (button.onPressed ?? widget.onTap)?.call();
      },
      onLongPress: button.onLongPress,
      onHover: button.onHover,
      onFocusChange: button.onFocusChange,
      style: button.style,
      focusNode: button.focusNode,
      autofocus: button.autofocus,
      clipBehavior: button.clipBehavior,
      child: button.child ?? const SizedBox(),
    );
  } else if (button is OutlinedButton) {
    return OutlinedButton(
      onPressed: () async {
        debugPrint('[SelfTest] Recording tap for "${widget.id}"');
        await SelfTestManager().recordTap(widget.id);
        (button.onPressed ?? widget.onTap)?.call();
      },
      onLongPress: button.onLongPress,
      onHover: button.onHover,
      onFocusChange: button.onFocusChange,
      style: button.style,
      focusNode: button.focusNode,
      autofocus: button.autofocus,
      clipBehavior: button.clipBehavior,
      child: button.child ?? const SizedBox(),
    );
  } else if (button is IconButton) {
    return IconButton(
      onPressed: () async {
        debugPrint('[SelfTest] Recording tap for "${widget.id}"');
        await SelfTestManager().recordTap(widget.id);
        (button.onPressed ?? widget.onTap)?.call();
      },
      icon: button.icon,
      iconSize: button.iconSize,
      visualDensity: button.visualDensity,
      padding: button.padding,
      alignment: button.alignment,
      splashRadius: button.splashRadius,
      color: button.color,
      focusColor: button.focusColor,
      hoverColor: button.hoverColor,
      highlightColor: button.highlightColor,
      splashColor: button.splashColor,
      disabledColor: button.disabledColor,
      onHover: button.onHover,
      focusNode: button.focusNode,
      autofocus: button.autofocus,
      tooltip: button.tooltip,
      enableFeedback: button.enableFeedback,
      constraints: button.constraints,
      style: button.style,
      isSelected: button.isSelected,
      selectedIcon: button.selectedIcon,
    );
  } else {
    // Fallback for other widgets
    return GestureDetector(
      onTap: () async {
        debugPrint('[SelfTest] Recording tap for "${widget.id}"');
        await SelfTestManager().recordTap(widget.id);
        widget.onTap?.call();
      },
      child: button,
    );
  }
}
