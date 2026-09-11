import 'dart:async';

import 'package:flutter/widgets.dart';

/// How the bridge navigates. Implement it for whatever router the app uses.
///
/// The bridge used to take a `GoRouter` directly, which meant a testing bridge
/// that only worked for apps that had picked one particular routing package.
/// Everything the bridge actually needs from a router is on this interface, so
/// an app on Navigator 1.0, `auto_route`, `beamer` or a hand-rolled router can
/// implement it in a few lines.
///
/// [NavigatorStateBridgeNavigator] is the default and needs nothing but the
/// `GlobalKey<NavigatorState>` every Flutter app can hand to `MaterialApp`.
///
/// A go_router app implements it like this:
///
/// ```dart
/// class GoRouterBridgeNavigator implements BridgeNavigator {
///   GoRouterBridgeNavigator(this.router);
///   final GoRouter router;
///
///   @override
///   Future<void> goTo(String location, {bool replace = false}) async =>
///       replace ? router.go(location) : router.push(location);
///
///   @override
///   Future<void> goBack() async => router.pop();
///
///   @override
///   bool get canGoBack => router.canPop();
///
///   @override
///   String? get currentLocation =>
///       router.routerDelegate.currentConfiguration.uri.toString();
///
///   @override
///   List<Map<String, dynamic>> describeRoutes() => const [];
/// }
/// ```
abstract interface class BridgeNavigator {
  /// Goes to [location].
  ///
  /// With [replace] the current entry is replaced rather than stacked on, which
  /// is what the `navigate` command's `replace` flag asks for.
  ///
  /// The returned future completes when the navigation has been started, not
  /// when the destination is later popped. The bridge settles the frame after
  /// calling this, so an implementation does not have to.
  Future<void> goTo(String location, {bool replace = false});

  /// Goes back one entry, if there is one to go back to.
  Future<void> goBack();

  /// Whether [goBack] would do anything.
  ///
  /// The `canPop` command answers with this. Without it the bridge would have
  /// to call [goBack] to find out, which is not a question.
  bool get canGoBack;

  /// Where the app is now, or null when the implementation cannot tell.
  String? get currentLocation;

  /// The routes the implementation knows about, for the `getFlowGraph`
  /// command. Return an empty list when the router cannot enumerate them
  /// rather than guessing.
  List<Map<String, dynamic>> describeRoutes();
}

/// The default [BridgeNavigator], driving the `Navigator` behind a
/// `GlobalKey<NavigatorState>`.
///
/// Every Flutter app has a `Navigator`, so this works without the app adopting
/// any routing package:
///
/// ```dart
/// final navigatorKey = GlobalKey<NavigatorState>();
/// final bridgeNavigator = NavigatorStateBridgeNavigator(navigatorKey);
///
/// MaterialApp(
///   navigatorKey: navigatorKey,
///   navigatorObservers: [bridgeNavigator.observer],
///   routes: {'/': ..., '/settings': ...},
/// );
///
/// SelfTestBridge(navigator: bridgeNavigator);
/// ```
///
/// [observer] is optional. Without it [goTo], [goBack] and [canGoBack] still
/// work, but [currentLocation] can only see the top route and
/// [describeRoutes] has nothing to report.
class NavigatorStateBridgeNavigator implements BridgeNavigator {
  NavigatorStateBridgeNavigator(this.navigatorKey);

  /// The key the app gave its `Navigator`.
  final GlobalKey<NavigatorState> navigatorKey;

  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  /// Add this to `navigatorObservers` to let the bridge see the whole route
  /// stack rather than just the top of it.
  late final NavigatorObserver observer = _BridgeNavigatorObserver(_stack);

  NavigatorState _requireState() {
    final state = navigatorKey.currentState;
    if (state == null) {
      throw StateError(
        'The navigator key passed to NavigatorStateBridgeNavigator is not '
        'attached to a Navigator. Pass the same GlobalKey to MaterialApp '
        '(navigatorKey:) that you passed here.',
      );
    }
    return state;
  }

  @override
  Future<void> goTo(String location, {bool replace = false}) async {
    final state = _requireState();
    // pushNamed's future completes when the pushed route is *popped*, not when
    // it is shown, so awaiting it here would hang until something navigated
    // back. The bridge only needs the push to have been started; it settles
    // the frame itself afterwards.
    if (replace) {
      unawaited(state.pushReplacementNamed<void, void>(location));
    } else {
      unawaited(state.pushNamed<void>(location));
    }
  }

  @override
  Future<void> goBack() async {
    await _requireState().maybePop();
  }

  @override
  bool get canGoBack => navigatorKey.currentState?.canPop() ?? false;

  @override
  String? get currentLocation {
    if (_stack.isNotEmpty) return _stack.last.settings.name;
    // Without the observer the stack is unknown, but popUntil visits the top
    // route first and pops nothing when the predicate returns true, so it can
    // still be read.
    String? name;
    navigatorKey.currentState?.popUntil((route) {
      name ??= route.settings.name;
      return true;
    });
    return name;
  }

  @override
  List<Map<String, dynamic>> describeRoutes() => [
    for (final route in _stack)
      {
        'name': route.settings.name,
        'isFirst': route.isFirst,
        'isCurrent': route.isCurrent,
        if (route.settings.arguments != null)
          'arguments': route.settings.arguments.toString(),
      },
  ];
}

class _BridgeNavigatorObserver extends NavigatorObserver {
  _BridgeNavigatorObserver(this._stack);

  final List<Route<dynamic>> _stack;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index < 0) {
      if (newRoute != null) _stack.add(newRoute);
      return;
    }
    if (newRoute == null) {
      _stack.removeAt(index);
    } else {
      _stack[index] = newRoute;
    }
  }
}
