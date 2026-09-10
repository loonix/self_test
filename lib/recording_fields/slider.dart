import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

Widget buildRecordingSlider(Slider slider, dynamic widget) {
  return Slider(
    value: slider.value,
    onChanged: (value) async {
      debugPrint(
        '[SelfTest] Recording slider change for "${widget.id}": $value',
      );
      // Use enterText to capture the slider value for playback
      await SelfTestManager().enterText(widget.id, value.toString());
      slider.onChanged?.call(value);
      widget.onTextChange?.call(value.toString());
    },
    onChangeStart: slider.onChangeStart,
    onChangeEnd: slider.onChangeEnd,
    min: slider.min,
    max: slider.max,
    divisions: slider.divisions,
    label: slider.label,
    activeColor: slider.activeColor,
    inactiveColor: slider.inactiveColor,
    secondaryActiveColor: slider.secondaryActiveColor,
    secondaryTrackValue: slider.secondaryTrackValue,
    semanticFormatterCallback: slider.semanticFormatterCallback,
    focusNode: slider.focusNode,
    autofocus: slider.autofocus,
    mouseCursor: slider.mouseCursor,
  );
}
