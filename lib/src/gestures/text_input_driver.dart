import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Types into a real text field.
///
/// The value goes in through [EditableTextState.updateEditingValue], which is
/// the method the platform's text input plugin calls when a key is pressed on
/// the soft keyboard. So the field's formatters run, its controller updates,
/// `onChanged` fires, and a `TextFormField` validates, all exactly as they do
/// for a person typing.
///
/// Setting `controller.text` directly, which is the shortcut everyone reaches
/// for, skips the formatters and lets a maxLength or an uppercase formatter
/// pass a test it would fail in the app.
class TextInputDriver {
  const TextInputDriver();

  /// Replaces the contents of the field at or under [element].
  ///
  /// Throws [StateError] when there is no text field there, naming the widget
  /// that was found instead.
  void enterText(Element element, String text) {
    final state = _editableStateIn(element);
    if (state == null) {
      throw StateError(
        'No text field at or under ${element.widget.runtimeType}. '
        'A locator for text entry has to point at a TextField, a '
        'TextFormField, or another widget built on EditableText.',
      );
    }
    state.widget.focusNode.requestFocus();
    state.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  /// Empties the field at or under [element].
  void clear(Element element) => enterText(element, '');

  /// Fires the field's keyboard action, the way the Done or Search key does.
  void submit(
    Element element, {
    TextInputAction action = TextInputAction.done,
  }) {
    final state = _editableStateIn(element);
    if (state == null) {
      throw StateError(
        'No text field at or under ${element.widget.runtimeType} to submit.',
      );
    }
    state.performAction(action);
  }

  /// The current contents of the field at or under [element], or null when
  /// there is no field there.
  String? textOf(Element element) =>
      _editableStateIn(element)?.textEditingValue.text;

  /// The field at [element], or the one the label at [element] belongs to.
  ///
  /// Looking down finds the field when the locator pointed at a `TextField`.
  /// Looking up is what makes "type into Username" work: a label lives in the
  /// decoration beside the field, not above it, so the only way from the word
  /// on screen to the field is through their nearest common ancestor. The walk
  /// stops at the first ancestor that holds a field, and refuses one that
  /// holds two, because picking either of them would be a guess.
  EditableTextState? _editableStateIn(Element element) {
    final below = _statesIn(element, limit: 1);
    if (below.isNotEmpty) return below.first;

    EditableTextState? found;
    element.visitAncestorElements((ancestor) {
      final states = _statesIn(ancestor, limit: 2);
      if (states.isEmpty) return true;
      if (states.length == 1) found = states.first;
      return false;
    });
    return found;
  }

  List<EditableTextState> _statesIn(Element element, {required int limit}) {
    final found = <EditableTextState>[];
    void visit(Element candidate) {
      if (found.length >= limit) return;
      if (candidate is StatefulElement &&
          candidate.state is EditableTextState) {
        found.add(candidate.state as EditableTextState);
        return;
      }
      candidate.visitChildren(visit);
    }

    visit(element);
    return found;
  }
}
