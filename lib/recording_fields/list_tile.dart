import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

Widget buildRecordingListTile(ListTile listTile, widget) {
  return ListTile(
    key: listTile.key,
    leading: listTile.leading,
    title: listTile.title,
    subtitle: listTile.subtitle,
    trailing: listTile.trailing,
    isThreeLine: listTile.isThreeLine,
    dense: listTile.dense,
    visualDensity: listTile.visualDensity,
    shape: listTile.shape,
    selectedColor: listTile.selectedColor,
    iconColor: listTile.iconColor,
    textColor: listTile.textColor,
    contentPadding: listTile.contentPadding,
    enabled: listTile.enabled,
    onTap: () async {
      debugPrint('[SelfTest] Recording tap for "${widget.id}"');
      await SelfTestManager().recordTap(widget.id);
      (listTile.onTap ?? widget.onTap)?.call();
    },
    onLongPress: listTile.onLongPress,
    mouseCursor: listTile.mouseCursor,
    selected: listTile.selected,
    focusColor: listTile.focusColor,
    hoverColor: listTile.hoverColor,
    splashColor: listTile.splashColor,
    focusNode: listTile.focusNode,
    autofocus: listTile.autofocus,
    tileColor: listTile.tileColor,
    selectedTileColor: listTile.selectedTileColor,
    enableFeedback: listTile.enableFeedback,
    horizontalTitleGap: listTile.horizontalTitleGap,
    minVerticalPadding: listTile.minVerticalPadding,
    minLeadingWidth: listTile.minLeadingWidth,
  );
}
