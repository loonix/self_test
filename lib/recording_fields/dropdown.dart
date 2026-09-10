// import 'package:flutter/material.dart';
// import 'package:self_test/self_test.dart';

// Widget buildRecordingDropdownButtonFormField(DropdownButtonFormField dropdown, widget) {
//   return DropdownButtonFormField(
//     key: dropdown.key,
//     decoration: dropdown.decoration,
//     value: dropdown.value,
//     items: dropdown.items,
//     onChanged: (value) async {
//       debugPrint('[SelfTest] Recording dropdown change for "${widget.id}": $value');
//       await SelfTestManager().recordTap(widget.id);
//       dropdown.onChanged?.call(value);
//       widget.onTextChange?.call(value.toString());
//     },
//     onSaved: dropdown.onSaved,
//     validator: dropdown.validator,
//     autovalidateMode: dropdown.autovalidateMode,
//     enabled: dropdown.enabled,
//     style: dropdown.style,
//     icon: dropdown.icon,
//     iconDisabledColor: dropdown.iconDisabledColor,
//     iconEnabledColor: dropdown.iconEnabledColor,
//     iconSize: dropdown.iconSize,
//     isDense: dropdown.isDense,
//     isExpanded: dropdown.isExpanded,
//     itemHeight: dropdown.itemHeight,
//     focusColor: dropdown.focusColor,
//     focusNode: dropdown.focusNode,
//     autofocus: dropdown.autofocus,
//     dropdownColor: dropdown.dropdownColor,
//     menuMaxHeight: dropdown.menuMaxHeight,
//     enableFeedback: dropdown.enableFeedback,
//     alignment: dropdown.alignment,
//     borderRadius: dropdown.borderRadius,
//     elevation: dropdown.elevation,
//   );
// }
