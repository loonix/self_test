import 'package:flutter/gestures.dart';

import '../core/test_binding.dart';

/// Advances the clock and lets the framework settle.
///
/// In a widget test this is `tester.pump`. In a real app the driver uses a
/// plain `Future.delayed`, because there the clock runs itself.
typedef ClockAdvance = Future<void> Function(Duration duration);

/// Sends real pointer events into the app.
///
/// Every gesture here goes through [GestureBinding.handlePointerEvent], the
/// same entry point the engine uses for a finger on glass. That means hit
/// testing runs, a widget covered by a dialog is not reachable, a disabled
/// button swallows the tap, and `onTap` fires because the gesture recogniser
/// decided it should, not because we called it.
///
/// The old path, invoking a registered `onTap` callback directly, tested none
/// of that: it passed on buttons the user could not even see.
class PointerDriver {
  const PointerDriver({this.advance});

  /// How to wait. Null means wait for real, which deadlocks under
  /// `flutter_test`, so a test registers `tester.pump` here.
  final ClockAdvance? advance;

  static int _nextPointer = 1;

  /// Dispatches [event] to the framework.
  void send(PointerEvent event) {
    _checkEventsAreDelivered();
    GestureBinding.instance.handlePointerEvent(event);
  }

  static Object? _checkedBinding;

  /// Refuses to dispatch into a binding that will throw the event away.
  ///
  /// `LiveTestWidgetsFlutterBinding`, which `integration_test` uses, drops
  /// every pointer event that did not come from a `WidgetTester` unless
  /// `shouldPropagateDevicePointerEvents` is set. Nothing is logged when it
  /// does: the tap simply has no effect, and the test fails several
  /// assertions later on a screen that never changed. Saying so here costs one
  /// property read and saves that hunt.
  ///
  /// The check is by name because reading the flag needs no import of
  /// `flutter_test`, and a runtime package must not depend on it.
  void _checkEventsAreDelivered() {
    final binding = GestureBinding.instance;
    if (identical(_checkedBinding, binding)) return;

    final name = binding.runtimeType.toString();
    if (name == 'AutomatedTestWidgetsFlutterBinding') {
      _checkedBinding = binding;
      return;
    }

    bool propagates;
    try {
      propagates =
          (binding as dynamic).shouldPropagateDevicePointerEvents as bool;
    } on NoSuchMethodError {
      // Not a test binding at all, so this is a real app and events arrive.
      _checkedBinding = binding;
      return;
    }

    if (!propagates) {
      throw StateError(
        '$name drops pointer events that did not come from a WidgetTester, so '
        'this gesture would do nothing at all. Add this line to main(), '
        'before the tests:\n'
        '  binding.shouldPropagateDevicePointerEvents = true;\n'
        'where binding is what ensureInitialized() returned.',
      );
    }
    _checkedBinding = binding;
  }

  /// A single tap: down then up at the same point.
  ///
  /// The caller pumps afterwards. This cannot pump for you: in a widget test
  /// the test owns the clock, and in a real app there is nothing to pump.
  Future<void> tap(Offset position, {int? viewId}) async {
    final pointer = _nextPointer++;
    send(_down(pointer, position, Duration.zero, viewId));
    send(_up(pointer, position, const Duration(milliseconds: 50), viewId));
  }

  /// Two taps close enough together that a [DoubleTapGestureRecognizer] wins.
  Future<void> doubleTap(Offset position, {int? viewId}) async {
    await tap(position, viewId: viewId);
    await _wait(const Duration(milliseconds: 50));
    await tap(position, viewId: viewId);
  }

  /// Holds a press down for [hold] before letting go.
  ///
  /// Under `flutter_test` this needs a clock: without one the press is never
  /// held, the recogniser's timer never fires, and the gesture silently
  /// degrades to a tap. Pass `tester.pump` as [advance] rather than letting
  /// that happen quietly.
  Future<void> longPress(
    Offset position, {
    Duration hold = const Duration(milliseconds: 600),
    int? viewId,
  }) async {
    if (isRunningUnderTest && advance == null) {
      throw StateError(
        'longPress needs a clock under flutter_test. Call '
        'SelfTestManager().useClock(tester.pump) in the test, or drive the '
        'press yourself with pointerDown/pointerUp and a pump in between.',
      );
    }
    final pointer = _nextPointer++;
    send(_down(pointer, position, Duration.zero, viewId));
    await _wait(hold);
    send(_up(pointer, position, hold, viewId));
  }

  /// Drags from [from] to [to] in [steps] moves.
  ///
  /// The move events carry increasing timestamps, so a scrollable computes a
  /// real velocity from them and flings the way it would for a finger. Raise
  /// [duration] to drag slowly enough that it does not.
  Future<void> drag(
    Offset from,
    Offset to, {
    int steps = 10,
    Duration duration = const Duration(milliseconds: 300),
    int? viewId,
  }) async {
    if (steps < 1) {
      throw ArgumentError.value(
        steps,
        'steps',
        'A drag needs at least one move',
      );
    }
    final pointer = _nextPointer++;
    final delta = to - from;
    final stepDelta = delta / steps.toDouble();
    final stepTime = duration ~/ steps;

    send(_down(pointer, from, Duration.zero, viewId));
    var position = from;
    var elapsed = Duration.zero;
    for (var i = 0; i < steps; i++) {
      position += stepDelta;
      elapsed += stepTime;
      send(
        PointerMoveEvent(
          pointer: pointer,
          position: position,
          delta: stepDelta,
          timeStamp: elapsed,
          kind: PointerDeviceKind.touch,
          viewId: viewId ?? 0,
        ),
      );
    }
    send(_up(pointer, to, elapsed, viewId));
  }

  /// A mouse wheel or trackpad scroll at [position].
  void scroll(Offset position, Offset delta, {int? viewId}) {
    send(
      PointerScrollEvent(
        position: position,
        scrollDelta: delta,
        viewId: viewId ?? 0,
      ),
    );
  }

  /// The down half of a press, for a caller that wants to pump in between.
  int pointerDown(Offset position, {int? viewId}) {
    final pointer = _nextPointer++;
    send(_down(pointer, position, Duration.zero, viewId));
    return pointer;
  }

  /// The up half, matching a [pointerDown].
  void pointerUp(int pointer, Offset position, {int? viewId}) {
    send(_up(pointer, position, Duration.zero, viewId));
  }

  PointerDownEvent _down(
    int pointer,
    Offset position,
    Duration timeStamp,
    int? viewId,
  ) => PointerDownEvent(
    pointer: pointer,
    position: position,
    timeStamp: timeStamp,
    kind: PointerDeviceKind.touch,
    viewId: viewId ?? 0,
  );

  PointerUpEvent _up(
    int pointer,
    Offset position,
    Duration timeStamp,
    int? viewId,
  ) => PointerUpEvent(
    pointer: pointer,
    position: position,
    timeStamp: timeStamp,
    kind: PointerDeviceKind.touch,
    viewId: viewId ?? 0,
  );

  Future<void> _wait(Duration duration) async {
    final advance = this.advance;
    if (advance != null) {
      await advance(duration);
      return;
    }
    if (isRunningUnderTest) return;
    await Future<void>.delayed(duration);
  }
}
