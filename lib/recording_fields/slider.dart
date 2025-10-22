import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';

Widget buildRecordingSlider(Slider slider, widget) {
  return Slider(
    value: slider.value,
    onChanged: (value) async {
      debugPrint('[SelfTest] Recording slider change for "${widget.id}": $value');
      await SelfTestManager().trigger(widget.id);
      slider.onChanged?.call(value);
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
