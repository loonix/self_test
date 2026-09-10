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
    activeThumbColor: switchTile.activeThumbColor,
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
      debugPrint(
          '[SelfTest] Recording switch change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      switchTile.onChanged?.call(value);
      widget.onTap?.call();
    },
  );
}

Widget buildRecordingSwitch(Switch switchWidget, widget) {
  return Switch(
    key: switchWidget.key,
    value: switchWidget.value,
    onChanged: (value) async {
      debugPrint(
          '[SelfTest] Recording switch change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      switchWidget.onChanged?.call(value);
      widget.onTap?.call();
    },
    activeThumbColor: switchWidget.activeThumbColor,
    activeTrackColor: switchWidget.activeTrackColor,
    inactiveThumbColor: switchWidget.inactiveThumbColor,
    inactiveTrackColor: switchWidget.inactiveTrackColor,
    activeThumbImage: switchWidget.activeThumbImage,
    onActiveThumbImageError: switchWidget.onActiveThumbImageError,
    inactiveThumbImage: switchWidget.inactiveThumbImage,
    onInactiveThumbImageError: switchWidget.onInactiveThumbImageError,
    thumbColor: switchWidget.thumbColor,
    trackColor: switchWidget.trackColor,
    thumbIcon: switchWidget.thumbIcon,
    materialTapTargetSize: switchWidget.materialTapTargetSize,
    dragStartBehavior: switchWidget.dragStartBehavior,
    mouseCursor: switchWidget.mouseCursor,
    focusColor: switchWidget.focusColor,
    hoverColor: switchWidget.hoverColor,
    overlayColor: switchWidget.overlayColor,
    splashRadius: switchWidget.splashRadius,
    focusNode: switchWidget.focusNode,
    onFocusChange: switchWidget.onFocusChange,
    autofocus: switchWidget.autofocus,
  );
}
