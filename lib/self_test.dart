/// A Flutter package for automated regression testing through direct callback invocation.
///
/// This library provides tools for recording and replaying user interactions
/// in Flutter applications, enabling fast and reliable testing in development
/// and pre-production environments without UI simulation.
library self_test;

// Public exports
export 'annotations.dart';
export 'src/test_code_generator.dart';
export 'src/models.dart' show TestScript, TestStep;
export 'src/core/recording_mode.dart';
export 'src/core/test_node.dart';
export 'src/core/manager.dart';
export 'src/widgets/self_testable_widget.dart';
export 'src/widgets/self_test_root.dart';
export 'src/widgets/control_panel.dart';

// Internal imports for initialization
import 'package:flutter/material.dart';
import 'src/core/manager.dart';
import 'recording_fields/button.dart';
import 'recording_fields/checkbox.dart';
import 'recording_fields/floating_action_button.dart';
import 'recording_fields/list_tile.dart';
import 'recording_fields/radio.dart';
import 'recording_fields/slider.dart';
import 'recording_fields/switch.dart';
import 'recording_fields/text_field.dart';
import 'recording_fields/text_form_field.dart';

/// Initializes the self_test package by registering built-in recording builders.
///
/// This is called automatically when [SelfTestManager] is first accessed,
/// but can be called explicitly to ensure initialization.
void initializeSelfTest() {
  _registerBuiltInBuilders();
}

bool _buildersRegistered = false;

void _registerBuiltInBuilders() {
  if (_buildersRegistered) return;
  _buildersRegistered = true;

  final manager = SelfTestManager();

  manager.registerRecordingBuilder<TextField>(
      (child, widget) => buildRecordingTextField(child as TextField, widget));
  manager.registerRecordingBuilder<ElevatedButton>(
      (child, widget) => buildRecordingButton(child, widget));
  manager.registerRecordingBuilder<TextButton>(
      (child, widget) => buildRecordingButton(child, widget));
  manager.registerRecordingBuilder<OutlinedButton>(
      (child, widget) => buildRecordingButton(child, widget));
  manager.registerRecordingBuilder<IconButton>(
      (child, widget) => buildRecordingButton(child, widget));
  manager.registerRecordingBuilder<CheckboxListTile>(
      (child, widget) => buildRecordingCheckboxListTile(child as CheckboxListTile, widget));
  manager.registerRecordingBuilder<RadioListTile>(
      (child, widget) => buildRecordingRadioListTile(child as RadioListTile, widget));
  manager.registerRecordingBuilder<Slider>(
      (child, widget) => buildRecordingSlider(child as Slider, widget));
  manager.registerRecordingBuilder<SwitchListTile>(
      (child, widget) => buildRecordingSwitchListTile(child as SwitchListTile, widget));
  manager.registerRecordingBuilder<ListTile>(
      (child, widget) => buildRecordingListTile(child as ListTile, widget));
  manager.registerRecordingBuilder<Switch>(
      (child, widget) => buildRecordingSwitch(child as Switch, widget));
  manager.registerRecordingBuilder<Checkbox>(
      (child, widget) => buildRecordingCheckbox(child as Checkbox, widget));
  manager.registerRecordingBuilder<Radio>(
      (child, widget) => buildRecordingRadio(child as Radio, widget));
  manager.registerRecordingBuilder<FloatingActionButton>(
      (child, widget) => buildRecordingFloatingActionButton(child as FloatingActionButton, widget));
  manager.registerRecordingBuilder<TextFormField>(
      (child, widget) => buildRecordingTextFormField(child as TextFormField, widget));
}

// Auto-initialize when the library is imported
// ignore: unused_element
final bool _initialized = () {
  _registerBuiltInBuilders();
  return true;
}();
