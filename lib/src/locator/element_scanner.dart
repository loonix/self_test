import 'package:flutter/material.dart';

import 'locator.dart';

/// What the scanner found for one widget: enough to act on it and enough to
/// tell a human (or an agent) why it was picked.
class WidgetSnapshot {
  WidgetSnapshot({
    required this.element,
    required this.typeName,
    required this.bounds,
    this.id,
    this.keyValue,
    this.text,
    this.semanticsLabel,
    this.tooltip,
    required this.isEnabled,
    required this.isInteractive,
    required this.isOnScreen,
  });

  /// The live element. Stale the moment the tree rebuilds, so resolve again
  /// rather than storing one.
  final Element element;

  /// The widget's runtime type, for example `ElevatedButton`.
  final String typeName;

  /// Where the widget is, in global (screen) coordinates. [Rect.zero] when the
  /// widget has no attached box, which is how an off-tree match is spotted.
  final Rect bounds;

  /// The `SelfTestableWidget` id, when there is one.
  final String? id;

  /// The value of a `ValueKey<String>`, when there is one.
  final String? keyValue;

  /// The text the widget paints, when it paints any.
  final String? text;

  /// The label accessibility would read out.
  final String? semanticsLabel;

  /// The tooltip message, when there is one.
  final String? tooltip;

  /// Best effort: false when the widget exposes a null `onPressed`/`onTap`, or
  /// sits under an `IgnorePointer`/`AbsorbPointer`. A widget that exposes no
  /// callback at all reads as enabled.
  final bool isEnabled;

  /// Whether this is something a user could act on, as opposed to a label.
  final bool isInteractive;

  /// Whether any part of the widget is inside the view.
  ///
  /// A list keeps items built for a while after they scroll away, so being in
  /// the element tree is not the same as being on screen, and tapping the
  /// coordinates of one that is not would land on whatever is drawn there
  /// instead.
  final bool isOnScreen;

  /// Whether the widget occupies a non-empty area, and so can be tapped.
  bool get hasSize => !bounds.isEmpty;

  /// The point a tap should land on.
  Offset get center => bounds.center;

  /// The wire form, for the bridge and the MCP server.
  Map<String, dynamic> toJson() => {
    'type': typeName,
    if (id != null) 'id': id,
    if (keyValue != null) 'key': keyValue,
    if (text != null) 'text': text,
    if (semanticsLabel != null) 'semantics': semanticsLabel,
    if (tooltip != null) 'tooltip': tooltip,
    'enabled': isEnabled,
    'interactive': isInteractive,
    'onScreen': isOnScreen,
    'rect': {
      'x': bounds.left,
      'y': bounds.top,
      'w': bounds.width,
      'h': bounds.height,
    },
  };

  @override
  String toString() {
    final parts = <String>[typeName];
    if (id != null) parts.add('id: "$id"');
    if (keyValue != null) parts.add('key: "$keyValue"');
    if (text != null) parts.add('text: "$text"');
    if (semanticsLabel != null) parts.add('semantics: "$semanticsLabel"');
    if (!isEnabled) parts.add('disabled');
    if (!isOnScreen && hasSize) parts.add('off screen');
    return parts.join(', ');
  }
}

/// Finds widgets in the running app by walking the element tree.
///
/// This is what makes the package work on an app that has never heard of it:
/// no wrapper widget, no registration, no code generation. The tree is already
/// there, and every property a locator matches on is already on it.
class ElementScanner {
  const ElementScanner();

  /// The element the walk starts from. Overridable so a test can scan a
  /// subtree.
  ///
  /// Null when there is no binding at all. A plain `test()` that registers a
  /// node and drives it by id never builds a widget tree, and that worked
  /// before locators existed, so it has to keep working: asking for
  /// `WidgetsBinding.instance` there throws.
  Element? get rootElement {
    try {
      return WidgetsBinding.instance.rootElement;
    } catch (_) {
      return null;
    }
  }

  /// Every widget the locator matches, in element-tree order (depth first,
  /// which for a normal layout reads top to bottom).
  ///
  /// A text match keeps only the outermost widget. `Text` builds a `RichText`
  /// that paints the same string, so without that rule every label on screen
  /// matches twice and `.at(1)` means "the same label again" instead of "the
  /// next one". Only text collapses this way: nested `Column`s or two
  /// `Semantics` with the same label really are two widgets.
  List<WidgetSnapshot> findAll(SelfTestLocator locator, {Element? from}) {
    final matches = <WidgetSnapshot>[];
    final collapse = locator.strategy == LocatorStrategy.text;

    void walk(Element element, bool ancestorMatched) {
      final matched = _matches(element, locator);
      if (matched && !(collapse && ancestorMatched)) {
        matches.add(describe(element));
      }
      element.visitChildren((child) => walk(child, ancestorMatched || matched));
    }

    final root = from ?? rootElement;
    if (root != null) walk(root, false);
    return matches;
  }

  /// The single widget [locator] points at.
  ///
  /// Throws [WidgetNotFoundError] when nothing matches, listing what was on
  /// screen instead. Matches with no size are kept: a widget that is in the
  /// tree but has collapsed to nothing is a different bug from one that is not
  /// there at all, and the caller gets to tell them apart.
  WidgetSnapshot resolve(SelfTestLocator locator, {Element? from}) {
    final matches = findAll(locator, from: from);
    if (matches.length <= locator.index) {
      throw WidgetNotFoundError(
        locator,
        matches.length,
        describeInteractive(from: from).map((s) => s.toString()).toList(),
      );
    }
    return matches[locator.index];
  }

  /// The single widget [locator] points at, or null when it matches nothing.
  WidgetSnapshot? tryResolve(SelfTestLocator locator, {Element? from}) {
    final matches = findAll(locator, from: from);
    if (matches.length <= locator.index) return null;
    return matches[locator.index];
  }

  /// Everything on screen a user could act on, plus the text labels around it.
  ///
  /// This is the answer to "what can I do here?", which is the first question
  /// an agent driving the app has to ask. It needs no registration: the
  /// widgets are read straight off the element tree.
  ///
  /// Two kinds of duplicate are dropped, because an agent paying by the token
  /// should not read the same button three times: the `RichText` a `Text`
  /// builds, and the `InkWell` and `GestureDetector` a button builds over
  /// exactly its own rect. A bare `InkWell` an app wrote itself has no
  /// interactive ancestor covering it, so it survives.
  List<WidgetSnapshot> describeInteractive({Element? from}) {
    final found = <WidgetSnapshot>[];

    void walk(Element element, String? ancestorText, Rect? ancestorRect) {
      final snapshot = describe(element);
      var nextText = ancestorText;
      var nextRect = ancestorRect;

      if (snapshot.isOnScreen) {
        final duplicateText =
            snapshot.text != null && snapshot.text == ancestorText;
        final duplicateHitTarget =
            snapshot.isInteractive && snapshot.bounds == ancestorRect;
        if (!duplicateText && !duplicateHitTarget) {
          if (snapshot.isInteractive ||
              snapshot.text != null ||
              snapshot.id != null) {
            found.add(snapshot);
          }
        }
        if (snapshot.text != null) nextText = snapshot.text;
        if (snapshot.isInteractive) nextRect = snapshot.bounds;
      }

      element.visitChildren((child) => walk(child, nextText, nextRect));
    }

    final root = from ?? rootElement;
    if (root != null) walk(root, null, null);
    return found;
  }

  /// Reads everything a locator can match off a single element.
  WidgetSnapshot describe(Element element) {
    final widget = element.widget;
    final bounds = _globalBounds(element);
    return WidgetSnapshot(
      element: element,
      typeName: widget.runtimeType.toString(),
      bounds: bounds,
      id: widget is SelfTestIdentified ? widget.selfTestId : null,
      keyValue: _keyValue(widget),
      text: _textOf(widget),
      semanticsLabel: _semanticsLabelOf(widget),
      tooltip: _tooltipOf(widget),
      isEnabled: _isEnabled(widget),
      isInteractive: _isInteractive(widget),
      isOnScreen: _isOnScreen(bounds),
    );
  }

  /// The area the app is drawn into, in global coordinates.
  Rect get viewBounds {
    final view = rootElement?.renderObject;
    return view == null ? Rect.zero : view.paintBounds;
  }

  bool _isOnScreen(Rect bounds) {
    if (bounds.isEmpty) return false;
    final view = viewBounds;
    if (view.isEmpty) return true;
    return bounds.overlaps(view);
  }

  // ---------------------------------------------------------------------------
  // Matching
  // ---------------------------------------------------------------------------

  bool _matches(Element element, SelfTestLocator locator) {
    final widget = element.widget;
    switch (locator.strategy) {
      case LocatorStrategy.id:
        if (widget is SelfTestIdentified &&
            widget.selfTestId == locator.value) {
          return true;
        }
        return _keyValue(widget) == locator.value;
      case LocatorStrategy.key:
        return _keyValue(widget) == locator.value;
      case LocatorStrategy.text:
        final text = _textOf(widget);
        if (text == null) return false;
        return locator.exact
            ? text == locator.value
            : text.contains(locator.value);
      case LocatorStrategy.semanticsLabel:
        return _semanticsLabelOf(widget) == locator.value;
      case LocatorStrategy.type:
        return widget.runtimeType.toString() == locator.value;
      case LocatorStrategy.tooltip:
        return _tooltipOf(widget) == locator.value;
    }
  }

  // ---------------------------------------------------------------------------
  // Property readers
  // ---------------------------------------------------------------------------

  String? _keyValue(Widget widget) {
    final key = widget.key;
    if (key is ValueKey<String>) return key.value;
    if (key is GlobalObjectKey) return key.value.toString();
    return null;
  }

  String? _textOf(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is SelectableText) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is EditableText) {
      return widget.controller.text;
    }
    return null;
  }

  String? _semanticsLabelOf(Widget widget) {
    if (widget is Semantics) return widget.properties.label;
    if (widget is Text) return widget.semanticsLabel;
    if (widget is Image) return widget.semanticLabel;
    if (widget is Icon) return widget.semanticLabel;
    // A tooltip is what a screen reader reads for an icon-only button, so a
    // locator by semantics has to see it too.
    return _tooltipOf(widget);
  }

  String? _tooltipOf(Widget widget) {
    if (widget is Tooltip) return widget.message;
    if (widget is IconButton) return widget.tooltip;
    if (widget is FloatingActionButton) return widget.tooltip;
    return null;
  }

  bool _isEnabled(Widget widget) {
    if (widget is IgnorePointer) return !widget.ignoring;
    if (widget is AbsorbPointer) return !widget.absorbing;
    // A field is not disabled for having no onChanged: it writes to its
    // controller either way. Ask it the way it says so itself.
    if (widget is TextField) return widget.enabled ?? true;
    if (widget is FormField) return widget.enabled;
    if (widget is EditableText) return !widget.readOnly;
    // Every material button, every field and every tile exposes its disabled
    // state as a null callback, but they share no common supertype that
    // declares one. Asking dynamically covers all of them, including the ones
    // an app wrote itself, and costs a caught error on the widgets that have
    // no such property.
    for (final read in <Object? Function()>[
      () => (widget as dynamic).onPressed,
      () => (widget as dynamic).onChanged,
      () => (widget as dynamic).enabled,
    ]) {
      try {
        final value = read();
        if (value == null) return false;
        if (value is bool) return value;
      } on NoSuchMethodError {
        continue;
      }
    }
    return true;
  }

  static const _interactiveTypes = <Type>{
    ElevatedButton,
    TextButton,
    OutlinedButton,
    FilledButton,
    IconButton,
    FloatingActionButton,
    GestureDetector,
    InkWell,
    Switch,
    Checkbox,
    Slider,
    ListTile,
    TextField,
    TextFormField,
    EditableText,
    DropdownButton,
    PopupMenuButton,
    Radio,
  };

  bool _isInteractive(Widget widget) {
    if (widget is SelfTestIdentified) return true;
    if (_interactiveTypes.contains(widget.runtimeType)) return true;
    // Generic types (Radio<int>, DropdownButton<String>, PopupMenuButton<T>)
    // have a runtimeType that carries the argument, so the set above misses
    // them. Match on the name up to the first angle bracket.
    final name = widget.runtimeType.toString();
    final bare = name.split('<').first;
    return _interactiveTypes.any((t) => t.toString().split('<').first == bare);
  }

  // ---------------------------------------------------------------------------
  // Geometry and walking
  // ---------------------------------------------------------------------------

  Rect _globalBounds(Element element) {
    final object = element.renderObject;
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return Rect.zero;
    }
    final topLeft = object.localToGlobal(Offset.zero);
    return topLeft & object.size;
  }
}
