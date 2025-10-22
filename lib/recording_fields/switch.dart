import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

Widget buildRecordingSwitchListTile(SwitchListTile switchTile, widget) {
  return SwitchListTile(
    title: switchTile.title,
    subtitle: switchTile.subtitle,
    isThreeLine: switchTile.isThreeLine,
    dense: switchTile.dense,
    contentPadding: switchTile.contentPadding,
    secondary: switchTile.secondary,
    selected: switchTile.selected,
    controlAffinity: switchTile.controlAffinity,
    autofocus: switchTile.autofocus,
    shape: switchTile.shape,
    tileColor: switchTile.tileColor,
    selectedTileColor: switchTile.selectedTileColor,
    activeColor: switchTile.activeColor,
    activeTrackColor: switchTile.activeTrackColor,
    inactiveThumbColor: switchTile.inactiveThumbColor,
    inactiveTrackColor: switchTile.inactiveTrackColor,
    activeThumbImage: switchTile.activeThumbImage,
    onActiveThumbImageError: switchTile.onActiveThumbImageError,
    inactiveThumbImage: switchTile.inactiveThumbImage,
    onInactiveThumbImageError: switchTile.onInactiveThumbImageError,
    thumbColor: switchTile.thumbColor,
    trackColor: switchTile.trackColor,
    splashRadius: switchTile.splashRadius,
    materialTapTargetSize: switchTile.materialTapTargetSize,
    visualDensity: switchTile.visualDensity,
    focusNode: switchTile.focusNode,
    onFocusChange: switchTile.onFocusChange,
    enableFeedback: switchTile.enableFeedback,
    hoverColor: switchTile.hoverColor,
    value: switchTile.value,
    onChanged: (value) async {
      debugPrint('[SelfTest] Recording switch change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      switchTile.onChanged?.call(value);
      widget.onTap?.call();
    },
  );
}
