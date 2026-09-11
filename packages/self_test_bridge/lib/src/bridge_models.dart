part of 'bridge_service.dart';

/// Data class for semantic label suggestions
class _SemanticSuggestion {
  final String widgetType;
  final String? currentLabel;
  final String suggestedLabel;
  final double confidence;
  final String location;
  final String reason;
  final Element? element;

  _SemanticSuggestion({
    required this.widgetType,
    this.currentLabel,
    required this.suggestedLabel,
    required this.confidence,
    required this.location,
    required this.reason,
    this.element,
  });

  Map<String, dynamic> toJson() => {
    'widgetType': widgetType,
    'currentLabel': currentLabel,
    'suggestedLabel': suggestedLabel,
    'confidence': confidence,
    'location': location,
    'reason': reason,
  };
}

class AppLifecycleEvent {
  final AppLifecycleState state;
  final DateTime timestamp;

  AppLifecycleEvent({required this.state, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };
}

/// Configuration for a state provider
class _StateProviderConfig {
  final String id;
  final String type;
  final Map<String, dynamic> Function() getState;
  final void Function(String action, dynamic payload)? dispatchAction;
  final Stream<Map<String, dynamic>>? stateStream;

  const _StateProviderConfig({
    required this.id,
    required this.type,
    required this.getState,
    this.dispatchAction,
    this.stateStream,
  });
}

/// Subscription for watching state changes
class _StateWatchSubscription {
  final String id;
  final String providerId;
  final List<Map<String, dynamic>> changes;
  final int debounceMs;
  StreamSubscription<Map<String, dynamic>>? streamSubscription;
  Timer? pollTimer;

  _StateWatchSubscription({
    required this.id,
    required this.providerId,
    required this.changes,
    required this.debounceMs,
  });
}

/// Configuration for a mocked platform channel method
class _ChannelMockConfig {
  final dynamic response;
  final String? errorCode;
  final String? errorMessage;

  const _ChannelMockConfig({this.response, this.errorCode, this.errorMessage});
}

/// Test pointer for simulating gestures
class TestPointer {
  final PointerDeviceKind kind;
  int _pointer = 0;

  TestPointer({this.kind = PointerDeviceKind.touch});

  PointerDownEvent down(Offset position) {
    _pointer++;
    return PointerDownEvent(pointer: _pointer, position: position, kind: kind);
  }

  PointerMoveEvent move(Offset position) {
    return PointerMoveEvent(pointer: _pointer, position: position, kind: kind);
  }

  PointerUpEvent up() {
    return PointerUpEvent(pointer: _pointer, kind: kind);
  }

  PointerHoverEvent hover(Offset position) {
    return PointerHoverEvent(position: position, kind: kind);
  }
}

/// Rebuild tracking information for a widget
class _RebuildInfo {
  int count = 0;
  final Set<String> reasons = {};
  String? location;

  Map<String, dynamic> toJson() => {
    'count': count,
    'reasons': reasons.toList(),
    if (location != null) 'location': location,
  };
}

/// Memory sample for profiling
class _MemorySample {
  final DateTime timestamp;
  final int heapUsed;

  _MemorySample({required this.timestamp, required this.heapUsed});

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'heapUsed': heapUsed,
  };
}

/// Deep link event for tracking deep link history
class DeepLinkEvent {
  final String url;
  final DateTime timestamp;
  final String source;
  bool handled;
  String? route;
  String? handledBy;

  DeepLinkEvent({
    required this.url,
    required this.timestamp,
    required this.source,
    this.handled = false,
    this.route,
    this.handledBy,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'source': source,
    'handled': handled,
    'route': route,
    'handledBy': handledBy,
  };
}

/// Recorded step for test generation
class _RecordedStep {
  final String type; // 'interaction', 'assertion', 'comment'
  final String action;
  final String? widgetId;
  final Map<String, dynamic> params;
  final DateTime timestamp;
  final String? comment;

  _RecordedStep({
    required this.type,
    required this.action,
    this.widgetId,
    required this.params,
    required this.timestamp,
    this.comment,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'action': action,
    if (widgetId != null) 'widgetId': widgetId,
    'params': params,
    'timestamp': timestamp.millisecondsSinceEpoch,
    if (comment != null) 'comment': comment,
  };
}

/// Navigation event for history tracking
class NavigationEvent {
  final String action;
  final String? from;
  final String to;
  final DateTime timestamp;
  final dynamic arguments;

  NavigationEvent({
    required this.action,
    this.from,
    required this.to,
    required this.timestamp,
    this.arguments,
  });

  Map<String, dynamic> toJson() => {
    'action': action,
    'from': from,
    'to': to,
    'timestamp': timestamp.millisecondsSinceEpoch,
    if (arguments != null) 'arguments': arguments,
  };
}

/// Navigation observer that reports events to the bridge
class NavigationInspectorObserver extends NavigatorObserver {
  final void Function(Route<dynamic>, Route<dynamic>?)? onPush;
  final void Function(Route<dynamic>, Route<dynamic>?)? onPop;
  final void Function(Route<dynamic>?, Route<dynamic>?)? onReplace;
  final void Function(Route<dynamic>, Route<dynamic>?)? onRemove;

  NavigationInspectorObserver({
    this.onPush,
    this.onPop,
    this.onReplace,
    this.onRemove,
  });

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPush?.call(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPop?.call(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onReplace?.call(newRoute, oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRemove?.call(route, previousRoute);
  }
}

/// Time-travel snapshot representing app state at a point in time
class _AppSnapshot {
  final String id;
  final String? label;
  final DateTime timestamp;
  final String currentRoute;
  final Map<String, Map<String, dynamic>> providerStates;
  final Map<String, dynamic> storageSnapshot;
  final String? widgetTreeDigest;

  _AppSnapshot({
    required this.id,
    this.label,
    required this.timestamp,
    required this.currentRoute,
    required this.providerStates,
    required this.storageSnapshot,
    this.widgetTreeDigest,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'currentRoute': currentRoute,
    'providerStates': providerStates,
    'storageSnapshot': storageSnapshot,
    'widgetTreeDigest': widgetTreeDigest,
  };
}
