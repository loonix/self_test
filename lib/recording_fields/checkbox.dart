import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

Widget buildRecordingCheckboxListTile(CheckboxListTile checkbox, widget) {
  return CheckboxListTile(
    title: checkbox.title,
    subtitle: checkbox.subtitle,
    isThreeLine: checkbox.isThreeLine,
    dense: checkbox.dense,
    contentPadding: checkbox.contentPadding,
    secondary: checkbox.secondary,
    selected: checkbox.selected,
    controlAffinity: checkbox.controlAffinity,
    autofocus: checkbox.autofocus,
    shape: checkbox.shape,
    side: checkbox.side,
    value: checkbox.value,
    onChanged: (value) async {
      debugPrint(
          '[SelfTest] Recording checkbox change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      checkbox.onChanged?.call(value);
      widget.onTap?.call();
    },
    activeColor: checkbox.activeColor,
    checkColor: checkbox.checkColor,
    fillColor: checkbox.fillColor,
    hoverColor: checkbox.hoverColor,
    overlayColor: checkbox.overlayColor,
    splashRadius: checkbox.splashRadius,
    materialTapTargetSize: checkbox.materialTapTargetSize,
    visualDensity: checkbox.visualDensity,
    focusNode: checkbox.focusNode,
    enableFeedback: checkbox.enableFeedback,
    tristate: checkbox.tristate,
  );
}

Widget buildRecordingCheckbox(Checkbox checkbox, widget) {
  return Checkbox(
    key: checkbox.key,
    value: checkbox.value,
    onChanged: (value) async {
      debugPrint(
          '[SelfTest] Recording checkbox change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      checkbox.onChanged?.call(value);
      widget.onTap?.call();
    },
    tristate: checkbox.tristate,
    activeColor: checkbox.activeColor,
    checkColor: checkbox.checkColor,
    fillColor: checkbox.fillColor,
    focusColor: checkbox.focusColor,
    hoverColor: checkbox.hoverColor,
    overlayColor: checkbox.overlayColor,
    splashRadius: checkbox.splashRadius,
    materialTapTargetSize: checkbox.materialTapTargetSize,
    visualDensity: checkbox.visualDensity,
    focusNode: checkbox.focusNode,
    autofocus: checkbox.autofocus,
    shape: checkbox.shape,
    side: checkbox.side,
    isError: checkbox.isError,
    semanticLabel: checkbox.semanticLabel,
  );
}
