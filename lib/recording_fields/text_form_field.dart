import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

/// Builds a recording-enabled TextFormField.
Widget buildRecordingTextFormField(TextFormField textField, SelfTestableWidget widget) {
  return TextFormField(
    controller: textField.controller,
    initialValue: textField.initialValue,
    onChanged: (value) async {
      debugPrint('[SelfTest] Recording text change for "${widget.id}": "$value"');
      await SelfTestManager().enterText(widget.id, value);
      textField.onChanged?.call(value);
      widget.onTextChange?.call(value);
    },
    onSaved: textField.onSaved,
    validator: textField.validator,
    enabled: textField.enabled,
    // Note: Other properties like decoration, keyboardType, etc. are not accessible as getters on TextFormField
    // Developers should use SelfTestableWidget around TextFormField and handle styling separately if needed
  );
}
