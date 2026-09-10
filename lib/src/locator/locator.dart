import 'package:flutter/widgets.dart';

/// How a [SelfTestLocator] decides whether an element is the one you meant.
enum LocatorStrategy {
  /// The `id` of a `SelfTestableWidget`, or a `ValueKey<String>` holding it.
  ///
  /// Kept first so a script recorded before universal locators existed still
  /// resolves without being rewritten.
  id,

  /// A `ValueKey<String>` whose value equals the locator value.
  key,

  /// The text a `Text`, `SelectableText` or `RichText` paints.
  text,

  /// A semantics label: `Semantics(label:)`, `Text(semanticsLabel:)`,
  /// `Image(semanticLabel:)`, or a tooltip, which is how a11y sees a button
  /// that shows nothing but an icon.
  semanticsLabel,

  /// The runtime type name of the widget, for example `ElevatedButton`.
  type,

  /// A `Tooltip(message:)`, or the `tooltip:` of an `IconButton` or a
  /// `FloatingActionButton`.
  tooltip,
}

/// Points at a widget in the running app.
///
/// A locator is a value, not a live reference: it describes what to look for
/// and is resolved against the element tree at the moment it is used, so it
/// survives a rebuild that replaces the widget it names. It is also
/// JSON-serialisable in both directions, which is what lets an agent on the
/// other end of the bridge send one.
///
/// ```dart
/// await SelfTestManager().tap(SelfTestLocator.text('Sign in'));
/// await SelfTestManager().tap(SelfTestLocator.semantics('Delete').at(2));
/// ```
///
/// Nothing here requires the app to wrap anything in a `SelfTestableWidget`.
class SelfTestLocator {
  const SelfTestLocator._(
    this.strategy,
    this.value, {
    this.exact = true,
    this.index = 0,
  });

  /// Matches a `SelfTestableWidget` with this id, or a `ValueKey<String>`
  /// holding it.
  const SelfTestLocator.id(String id) : this._(LocatorStrategy.id, id);

  /// Matches a `ValueKey<String>` holding [key].
  const SelfTestLocator.key(String key) : this._(LocatorStrategy.key, key);

  /// Matches painted text.
  ///
  /// With [exact] false the widget matches when its text merely contains
  /// [text], which is what you want for a label that carries a count or a
  /// name in it.
  const SelfTestLocator.text(String text, {bool exact = true})
    : this._(LocatorStrategy.text, text, exact: exact);

  /// Matches a semantics label, including tooltips.
  const SelfTestLocator.semantics(String label)
    : this._(LocatorStrategy.semanticsLabel, label);

  /// Matches a widget by runtime type name, for example `Switch`.
  const SelfTestLocator.type(String typeName)
    : this._(LocatorStrategy.type, typeName);

  /// Matches a tooltip message.
  const SelfTestLocator.tooltip(String message)
    : this._(LocatorStrategy.tooltip, message);

  /// How to match.
  final LocatorStrategy strategy;

  /// What to match against.
  final String value;

  /// Whether [value] must equal the candidate exactly. Only [LocatorStrategy.text]
  /// reads this.
  final bool exact;

  /// Which match to take when more than one widget matches, in the order the
  /// element tree is walked (top-left first, roughly reading order).
  final int index;

  /// The same locator, resolving to the match at [index] instead of the first.
  ///
  /// Throws [RangeError] for a negative index: silently resolving to the wrong
  /// widget is worse than failing here.
  SelfTestLocator at(int index) {
    if (index < 0) {
      throw RangeError.value(
        index,
        'index',
        'A locator index cannot be negative',
      );
    }
    return SelfTestLocator._(strategy, value, exact: exact, index: index);
  }

  /// Rebuilds a locator sent over the bridge.
  ///
  /// Unknown strategies throw rather than falling back to a default: an agent
  /// that asks for something we cannot do should be told so, not quietly given
  /// a different widget.
  factory SelfTestLocator.fromJson(Map<String, dynamic> json) {
    final name = json['by'] as String?;
    if (name == null) {
      throw ArgumentError.value(json, 'json', 'Locator is missing "by"');
    }
    final strategy = LocatorStrategy.values.where((s) => s.name == name);
    if (strategy.isEmpty) {
      throw ArgumentError.value(
        name,
        'by',
        'Unknown locator strategy. Known: '
            '${LocatorStrategy.values.map((s) => s.name).join(', ')}',
      );
    }
    final value = json['value'];
    if (value is! String) {
      throw ArgumentError.value(
        json,
        'json',
        'Locator "value" must be a String',
      );
    }
    return SelfTestLocator._(
      strategy.first,
      value,
      exact: json['exact'] as bool? ?? true,
      index: json['index'] as int? ?? 0,
    );
  }

  /// The wire form, matching [SelfTestLocator.fromJson].
  Map<String, dynamic> toJson() => {
    'by': strategy.name,
    'value': value,
    if (!exact) 'exact': false,
    if (index != 0) 'index': index,
  };

  @override
  String toString() {
    final suffix = <String>[
      if (!exact) 'contains',
      if (index != 0) 'index: $index',
    ];
    final tail = suffix.isEmpty ? '' : ' (${suffix.join(', ')})';
    return '${strategy.name}: "$value"$tail';
  }

  @override
  bool operator ==(Object other) =>
      other is SelfTestLocator &&
      other.strategy == strategy &&
      other.value == value &&
      other.exact == exact &&
      other.index == index;

  @override
  int get hashCode => Object.hash(strategy, value, exact, index);
}

/// Implemented by a widget that carries a self-test id.
///
/// Lives here so the locator can recognise `SelfTestableWidget` without the
/// two files importing each other. It implements [Widget] so that a
/// `widget is SelfTestIdentified` check promotes: Dart only promotes to a
/// type that is a subtype of the declared one.
abstract interface class SelfTestIdentified implements Widget {
  /// The id the app gave this widget.
  String get selfTestId;
}

/// Thrown when a locator matches nothing, or fewer widgets than its index asks
/// for.
///
/// The message lists what was on screen, because "not found" without that is
/// a fifteen-minute debugging session every time.
class WidgetNotFoundError extends Error {
  WidgetNotFoundError(this.locator, this.matchCount, this.candidates);

  /// The locator that failed.
  final SelfTestLocator locator;

  /// How many widgets it did match.
  final int matchCount;

  /// A description of what was on screen when it failed.
  final List<String> candidates;

  @override
  String toString() {
    final head = matchCount == 0
        ? 'No widget matches $locator.'
        : 'Locator $locator asked for index ${locator.index} '
              'but only $matchCount widget(s) match.';
    if (candidates.isEmpty) return head;
    return '$head\nOn screen now:\n  ${candidates.join('\n  ')}';
  }
}
