part of '../bridge_service.dart';

// Helpers with no bridge state behind them.
//
// Top-level rather than statics on SelfTestBridge: a static of
// the extended type cannot be named unqualified from an
// extension, and every one of these is called from one.

/// Returned by a command group that does not own the command,
/// so the dispatcher knows to try the next group. A private
/// object rather than null, because null is a real result.
const Object _unhandled = Object();

/// What every navigation command answers when no [BridgeNavigator] was
/// configured. Reporting success for a move that never happened is how an
/// agent ends up asserting against the wrong screen.
const Map<String, dynamic> _navigatorMissing = {
  'error':
      'No BridgeNavigator is configured, so the bridge cannot navigate. '
      'Pass one to SelfTestBridge(navigator:) - '
      'NavigatorStateBridgeNavigator(yourNavigatorKey) works for any app.',
};

/// Default golden directory (relative to project root)
const String _defaultGoldensDir = 'test/goldens';

String _generateToken() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Compares without leaking where the difference is through timing.
bool _secretsMatch(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

/// The commands that drive the app rather than merely question it.
///
/// Time-travel capture and test recording both need to know when one runs,
/// and listing them once here is what stopped both features being wired to
/// nothing.
const Set<String> _interactionCommands = {
  'tap',
  'doubleTap',
  'longPress',
  'type',
  'enterText',
  'clear',
  'drag',
  'scroll',
  'scrollTo',
  'hover',
  'focus',
  'select',
  'toggle',
  'setSlider',
  'pressKey',
  'submit',
};

String _describeJsonValue(Object? value) =>
    value is String ? '"$value"' : '$value';

String _requireString(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is! String) {
    throw Exception('This command needs a "$key" parameter.');
  }
  return value;
}

Offset _scrollOffset(String direction, double delta) {
  switch (direction) {
    // A scroll gesture moves the content the opposite way to the travel, so
    // scrolling down drags the content up.
    case 'down':
      return Offset(0, -delta);
    case 'up':
      return Offset(0, delta);
    case 'left':
      return Offset(delta, 0);
    case 'right':
      return Offset(-delta, 0);
    default:
      throw Exception('Unknown scroll direction: $direction');
  }
}
