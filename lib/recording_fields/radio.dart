// ignore_for_file: deprecated_member_use
// Radio groupValue/onChanged are deprecated in Flutter 3.32+ in favor of RadioGroup.
// We suppress this warning to maintain backwards compatibility with older Flutter versions.
import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

Widget buildRecordingRadioListTile(RadioListTile radio, widget) {
  return RadioListTile(
    title: radio.title,
    subtitle: radio.subtitle,
    isThreeLine: radio.isThreeLine,
    dense: radio.dense,
    contentPadding: radio.contentPadding,
    secondary: radio.secondary,
    selected: radio.selected,
    controlAffinity: radio.controlAffinity,
    autofocus: radio.autofocus,
    shape: radio.shape,
    tileColor: radio.tileColor,
    selectedTileColor: radio.selectedTileColor,
    activeColor: radio.activeColor,
    fillColor: radio.fillColor,
    hoverColor: radio.hoverColor,
    overlayColor: radio.overlayColor,
    splashRadius: radio.splashRadius,
    materialTapTargetSize: radio.materialTapTargetSize,
    visualDensity: radio.visualDensity,
    focusNode: radio.focusNode,
    enableFeedback: radio.enableFeedback,
    value: radio.value,
    groupValue: radio.groupValue,
    onChanged: (value) async {
      debugPrint(
          '[SelfTest] Recording radio change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      radio.onChanged?.call(value);
      widget.onTap?.call();
    },
    toggleable: radio.toggleable,
  );
}

Widget buildRecordingRadio(Radio radio, widget) {
  return Radio(
    key: radio.key,
    value: radio.value,
    groupValue: radio.groupValue,
    onChanged: (value) async {
      debugPrint(
          '[SelfTest] Recording radio change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      radio.onChanged?.call(value);
      widget.onTap?.call();
    },
    activeColor: radio.activeColor,
    fillColor: radio.fillColor,
    focusColor: radio.focusColor,
    hoverColor: radio.hoverColor,
    overlayColor: radio.overlayColor,
    splashRadius: radio.splashRadius,
    materialTapTargetSize: radio.materialTapTargetSize,
    visualDensity: radio.visualDensity,
    focusNode: radio.focusNode,
    autofocus: radio.autofocus,
    toggleable: radio.toggleable,
  );
}
