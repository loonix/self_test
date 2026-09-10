/// Automated regression testing for Flutter, driven from outside the app.
///
/// The package registers the widgets you mark as testable, then lets a test,
/// a recording session, or an external agent over the WebSocket bridge act on
/// them by id. See the README for a quickstart.
library self_test;

export 'annotations.dart';
export 'src/catalog.dart';
export 'src/core/manager.dart';
export 'src/core/recording_mode.dart';
export 'src/core/test_node.dart';
export 'src/models.dart' show TestScript, RecordedStep;
export 'src/persistence/recording_store.dart';
export 'src/scenario/test_scenario.dart';
export 'src/test_code_generator.dart';
export 'src/widgets/control_panel.dart';
export 'src/widgets/screenshot_boundary.dart';
export 'src/widgets/self_test_root.dart';
export 'src/widgets/self_testable_widget.dart';

import 'package:flutter/material.dart';

import 'recording_fields/button.dart';
import 'recording_fields/checkbox.dart';
import 'recording_fields/floating_action_button.dart';
import 'recording_fields/list_tile.dart';
import 'recording_fields/radio.dart';
import 'recording_fields/slider.dart';
import 'recording_fields/switch.dart';
import 'recording_fields/text_field.dart';
import 'recording_fields/text_form_field.dart';
import 'src/core/manager.dart';

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
