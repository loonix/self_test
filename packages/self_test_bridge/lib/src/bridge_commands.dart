/// Command sent from MCP server to Flutter app
class BridgeCommand {
  final int id;
  final String command;
  final Map<String, dynamic> params;

  BridgeCommand({
    required this.id,
    required this.command,
    required this.params,
  });

  factory BridgeCommand.fromJson(Map<String, dynamic> json) {
    return BridgeCommand(
      id: json['id'] as int,
      command: json['command'] as String,
      params: (json['params'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'params': params,
  };
}

/// Response sent from Flutter app to MCP server
class BridgeResponse {
  final int id;
  final dynamic result;
  final String? error;

  BridgeResponse({required this.id, this.result, this.error});

  factory BridgeResponse.fromJson(Map<String, dynamic> json) {
    return BridgeResponse(
      id: json['id'] as int,
      result: json['result'],
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'id': id};
    if (error != null) {
      json['error'] = error;
    } else {
      json['result'] = result;
    }
    return json;
  }
}

/// Available bridge commands - Playwright parity
class BridgeCommands {
  // =====================================================================
  // LOCATORS
  // =====================================================================
  static const String getSnapshot = 'getSnapshot';
  static const String getWidgetCatalog = 'getWidgetCatalog';
  static const String getFlowGraph = 'getFlowGraph';
  static const String getScreens = 'getScreens';
  static const String getCurrentState = 'getCurrentState';
  static const String getByRole = 'getByRole';
  static const String getByText = 'getByText';

  // =====================================================================
  // ACTIONS
  // =====================================================================
  static const String tap = 'tap';
  static const String type = 'type';
  static const String clear = 'clear';
  static const String pressKey = 'pressKey';
  static const String scroll = 'scroll';
  static const String scrollTo = 'scrollTo';
  static const String drag = 'drag';
  static const String longPress = 'longPress';
  static const String doubleTap = 'doubleTap';
  static const String hover = 'hover';
  static const String focus = 'focus';
  static const String select = 'select';
  static const String toggle = 'toggle';
  static const String setSlider = 'setSlider';

  // Legacy (kept for compatibility)
  static const String enterText = 'enterText';
  static const String screenshot = 'screenshot';

  // =====================================================================
  // NAVIGATION
  // =====================================================================
  static const String navigate = 'navigate';
  static const String goBack = 'goBack';
  static const String reload = 'reload';
  static const String restart = 'restart';

  // =====================================================================
  // WAITING
  // =====================================================================
  static const String wait = 'wait';
  static const String waitFor = 'waitFor'; // Legacy alias

  // =====================================================================
  // ASSERTIONS
  // =====================================================================
  static const String expect = 'expect';
  static const String expectScreenshot = 'expectScreenshot';
  static const String assertWidget = 'assertWidget'; // Legacy

  // =====================================================================
  // GOLDEN TESTING
  // =====================================================================
  /// Update golden baselines (all or specific ones)
  static const String updateGoldens = 'updateGoldens';

  /// List all golden baseline files
  static const String listGoldens = 'listGoldens';

  // =====================================================================
  // SCREENSHOTS & VIDEO
  // =====================================================================
  static const String recordStart = 'recordStart';
  static const String recordStop = 'recordStop';

  // =====================================================================
  // NETWORK
  // =====================================================================
  static const String mockHttp = 'mockHttp';
  static const String blockHttp = 'blockHttp';
  static const String clearMocks = 'clearMocks';
  static const String networkLog = 'networkLog';
  static const String waitNetwork = 'waitNetwork';

  // =====================================================================
  // CONSOLE & ERRORS
  // =====================================================================
  static const String console = 'console';
  static const String errors = 'errors';

  // =====================================================================
  // TRACING
  // =====================================================================
  static const String traceStart = 'traceStart';
  static const String traceStop = 'traceStop';

  // =====================================================================
  // DEVICE EMULATION
  // =====================================================================
  static const String resize = 'resize';
  static const String setTheme = 'setTheme';
  static const String setLocale = 'setLocale';
  static const String setTextScale = 'setTextScale';

  // =====================================================================
  // DIALOGS & OVERLAYS
  // =====================================================================
  static const String handleDialog = 'handleDialog';
  static const String dismissOverlay = 'dismissOverlay';

  // =====================================================================
  // STORAGE & STATE
  // =====================================================================
  static const String storageGet = 'storageGet';
  static const String storageSet = 'storageSet';
  static const String storageClear = 'storageClear';
  static const String saveState = 'saveState';
  static const String restoreState = 'restoreState';

  // =====================================================================
  // FILES
  // =====================================================================
  static const String filePicker = 'filePicker';

  // =====================================================================
  // SCENARIOS
  // =====================================================================
  static const String runScenario = 'runScenario';

  // =====================================================================
  // ACCESSIBILITY
  // =====================================================================
  static const String accessibilityAudit = 'accessibilityAudit';

  // =====================================================================
  // CLIPBOARD
  // =====================================================================
  static const String clipboardRead = 'clipboardRead';
  static const String clipboardWrite = 'clipboardWrite';

  // =====================================================================
  // HAR EXPORT
  // =====================================================================
  static const String harExport = 'harExport';

  // =====================================================================
  // ANIMATION CONTROL
  // =====================================================================
  static const String animationSpeed = 'animationSpeed';
  static const String pump = 'pump';

  // =====================================================================
  // FRAME BUDGET ANALYSIS
  // =====================================================================
  /// Start frame timing profiling
  static const String frameProfilingStart = 'frameProfilingStart';

  /// Stop frame profiling and get results
  static const String frameProfilingStop = 'frameProfilingStop';

  /// Profile a specific action and get frame analysis
  static const String frameBudgetCheck = 'frameBudgetCheck';

  /// Enable/disable continuous jank detection
  static const String jankDetector = 'jankDetector';

  // =====================================================================
  // STATE MANAGEMENT INSPECTION
  // =====================================================================
  /// Get current state from state management (Riverpod, Bloc, Provider)
  static const String getState = 'getState';

  /// Dispatch an action/event to state management
  static const String dispatchAction = 'dispatchAction';

  /// Subscribe to state changes (returns subscription ID)
  static const String watchState = 'watchState';

  /// Unsubscribe from state changes
  static const String unwatchState = 'unwatchState';

  /// List all available state providers/blocs
  static const String listStateProviders = 'listStateProviders';

  /// Directly inject state into a provider/bloc without UI interaction
  static const String injectState = 'injectState';

  /// Reset a provider to its initial state
  static const String resetState = 'resetState';

  /// Reset all registered providers to initial state
  static const String resetAllState = 'resetAllState';

  /// Get history of state changes for a provider
  static const String stateHistory = 'stateHistory';

  // =====================================================================
  // PLATFORM CHANNEL MOCKING
  // =====================================================================
  /// Mock a platform channel method response
  static const String mockChannel = 'mockChannel';

  /// Clear platform channel mocks
  static const String clearChannelMocks = 'clearChannelMocks';

  /// Get log of platform channel method calls
  static const String channelLog = 'channelLog';

  // =====================================================================
  // SENSOR & DEVICE MOCKING
  // =====================================================================
  /// Set mock GPS coordinates
  static const String setGeolocation = 'setGeolocation';

  /// Set mock permission state
  static const String setPermission = 'setPermission';

  /// Set mock network connectivity state
  static const String setConnectivity = 'setConnectivity';

  // =====================================================================
  // WIDGET REBUILD PROFILING
  // =====================================================================
  /// Start profiling widget rebuilds
  static const String profileRebuildsStart = 'profileRebuildsStart';

  /// Stop profiling widget rebuilds and get results
  static const String profileRebuildsStop = 'profileRebuildsStop';

  /// Get detailed rebuild report with optional threshold filtering
  static const String profileRebuildsReport = 'profileRebuildsReport';

  // =====================================================================
  // SEMANTIC LABEL AUTO-GENERATION
  // =====================================================================
  /// Analyze widgets and suggest semantic labels for accessibility
  static const String suggestSemantics = 'suggestSemantics';

  /// Get semantics coverage report (labeled vs unlabeled widgets)
  static const String semanticsCoverage = 'semanticsCoverage';

  /// Get the full semantics tree with detailed node information
  static const String semanticsTree = 'semanticsTree';

  /// Generate code snippets to apply suggested semantic labels
  static const String applySuggestedSemantics = 'applySuggestedSemantics';

  // =====================================================================
  // APP LIFECYCLE TESTING
  // =====================================================================
  /// Simulate app lifecycle state change (paused, resumed, inactive, detached, hidden)
  static const String simulateLifecycle = 'simulateLifecycle';

  /// Get history of lifecycle events
  static const String lifecycleHistory = 'lifecycleHistory';

  /// Simulate memory pressure warning
  static const String simulateMemoryPressure = 'simulateMemoryPressure';

  /// Simulate system locale change
  static const String simulateLocaleChange = 'simulateLocaleChange';

  /// Simulate system text scale change
  static const String simulateTextScaleChange = 'simulateTextScaleChange';

  /// Simulate system brightness mode change
  static const String simulateBrightnessChange = 'simulateBrightnessChange';

  // =====================================================================
  // STATE DEPENDENCY GRAPH
  // =====================================================================
  /// Get the dependency graph of all state providers
  static const String stateDependencyGraph = 'stateDependencyGraph';

  /// Analyze what would be affected by changing a provider
  static const String stateImpactAnalysis = 'stateImpactAnalysis';

  /// Trace state flow from source to widget
  static const String stateTrace = 'stateTrace';

  /// Find providers that are defined but never used
  static const String orphanStateCheck = 'orphanStateCheck';

  // =====================================================================
  // TIME-TRAVEL STATE SNAPSHOTS
  // =====================================================================
  /// Start recording time-travel snapshots
  static const String timeTravelStart = 'timeTravelStart';

  /// Manually capture a snapshot at the current moment
  static const String timeTravelSnapshot = 'timeTravelSnapshot';

  /// List all captured snapshots
  static const String timeTravelList = 'timeTravelList';

  /// Restore app to a previous snapshot state
  static const String timeTravelGoto = 'timeTravelGoto';

  /// Stop recording snapshots and optionally clear them
  static const String timeTravelStop = 'timeTravelStop';

  /// Compare two snapshots and return differences
  static const String timeTravelDiff = 'timeTravelDiff';

  // =====================================================================
  // BIOMETRIC AUTHENTICATION MOCKING
  // =====================================================================

  /// Set which biometric types are available (faceId, touchId, fingerprint, iris, deviceCredential)
  static const String setBiometricAvailability = 'setBiometricAvailability';

  /// Set what the next biometric auth will return (success, failed, cancelled, etc.)
  static const String setBiometricResult = 'setBiometricResult';

  /// Get history of biometric authentication attempts
  static const String biometricAuthHistory = 'biometricAuthHistory';

  /// Trigger a biometric prompt programmatically
  static const String simulateBiometricPrompt = 'simulateBiometricPrompt';

  /// Reset biometric configuration to defaults
  static const String clearBiometricConfig = 'clearBiometricConfig';

  // =====================================================================
  // MEMORY PROFILING
  // =====================================================================

  /// Get current memory usage snapshot
  static const String memorySnapshot = 'memorySnapshot';

  /// Start memory profiling over time
  static const String memoryProfileStart = 'memoryProfileStart';

  /// Stop profiling and get results
  static const String memoryProfileStop = 'memoryProfileStop';

  /// Force garbage collection
  static const String forceGc = 'forceGc';

  /// Get image cache statistics
  static const String imageCacheStats = 'imageCacheStats';

  /// Clear the image cache
  static const String clearImageCache = 'clearImageCache';

  /// Run heuristic leak detection
  static const String memoryLeakCheck = 'memoryLeakCheck';

  // =====================================================================
  // WIDGET TEST GENERATION
  // =====================================================================
  /// Start recording interactions for test generation
  static const String recordTestStart = 'recordTestStart';

  /// Stop recording and get generated test code
  static const String recordTestStop = 'recordTestStop';

  /// Add an assertion to the recording
  static const String recordAddAssertion = 'recordAddAssertion';

  /// Add a comment to the generated test
  static const String recordAddComment = 'recordAddComment';

  /// Get current recorded steps without stopping
  static const String getRecordedSteps = 'getRecordedSteps';

  /// Generate test from a scenario definition
  static const String generateTestFromScenario = 'generateTestFromScenario';

  // =====================================================================
  // NAVIGATION STACK INSPECTOR
  // =====================================================================
  /// Get the full navigation stack
  static const String navigationStack = 'navigationStack';

  /// Get navigation history
  static const String navigationHistory = 'navigationHistory';

  /// Pop routes until a condition is met
  static const String popUntil = 'popUntil';

  /// Check if current route can be popped
  static const String canPop = 'canPop';

  /// Get registered navigation observers/listeners
  static const String navigationListeners = 'navigationListeners';

  /// Simulate iOS/Android back gesture
  static const String simulateBackGesture = 'simulateBackGesture';

  /// Get settings for current or specific route
  static const String routeSettings = 'routeSettings';

  // =====================================================================
  // DEEP LINK TESTING
  // =====================================================================
  /// Simulate receiving a deep link / universal link
  static const String simulateDeepLink = 'simulateDeepLink';

  /// Get history of deep links received
  static const String deepLinkHistory = 'deepLinkHistory';

  /// Register URL schemes the app handles
  static const String registerDeepLinkSchemes = 'registerDeepLinkSchemes';

  /// Test that a deep link routes correctly
  static const String testDeepLinkRouting = 'testDeepLinkRouting';

  /// Clear deep link history
  static const String clearDeepLinkHistory = 'clearDeepLinkHistory';

  // =====================================================================
  // PUSH NOTIFICATION MOCKING
  // =====================================================================
  /// Simulate receiving a push notification
  static const String simulatePushNotification = 'simulatePushNotification';

  /// Simulate user tapping a notification
  static const String simulateNotificationTap = 'simulateNotificationTap';

  /// Get history of simulated notifications
  static const String notificationHistory = 'notificationHistory';

  /// Register mock notification handlers
  static const String setNotificationHandler = 'setNotificationHandler';

  /// Clear notification history
  static const String clearNotifications = 'clearNotifications';

  /// Get mock FCM token
  static const String getFcmToken = 'getFcmToken';
}

// =====================================================================
// MOCK DATA TYPES
// =====================================================================

/// Mock notification data for push notification testing
class MockNotification {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  String action;

  MockNotification({
    required this.id,
    required this.title,
    required this.body,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    this.action = 'received',
  }) : data = data ?? {},
       timestamp = timestamp ?? DateTime.now();

  factory MockNotification.fromJson(Map<String, dynamic> json) {
    return MockNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      data: (json['data'] as Map<String, dynamic>?) ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      action: json['action'] as String? ?? 'received',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'data': data,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'action': action,
  };

  @override
  String toString() =>
      'MockNotification(id: $id, title: $title, action: $action)';

  /// Create a copy with updated values
  MockNotification copyWith({
    String? id,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    String? action,
  }) {
    return MockNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
    );
  }
}

/// Mock location data for geolocation testing
class MockLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;

  MockLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy = 10.0,
    this.altitude,
    this.speed,
    this.heading,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory MockLocation.fromJson(Map<String, dynamic> json) {
    return MockLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 10.0,
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    if (altitude != null) 'altitude': altitude,
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  @override
  String toString() =>
      'MockLocation(lat: $latitude, lng: $longitude, accuracy: $accuracy)';

  /// Create a copy with updated values
  MockLocation copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    DateTime? timestamp,
  }) {
    return MockLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Permission types that can be mocked
enum MockPermissionType {
  camera,
  microphone,
  location,
  locationAlways,
  locationWhenInUse,
  photos,
  storage,
  contacts,
  calendar,
  reminders,
  notifications,
  bluetooth,
  sensors,
  speech,
  mediaLibrary;

  static MockPermissionType fromString(String value) {
    switch (value) {
      case 'camera':
        return MockPermissionType.camera;
      case 'microphone':
        return MockPermissionType.microphone;
      case 'location':
        return MockPermissionType.location;
      case 'location_always':
        return MockPermissionType.locationAlways;
      case 'location_when_in_use':
        return MockPermissionType.locationWhenInUse;
      case 'photos':
        return MockPermissionType.photos;
      case 'storage':
        return MockPermissionType.storage;
      case 'contacts':
        return MockPermissionType.contacts;
      case 'calendar':
        return MockPermissionType.calendar;
      case 'reminders':
        return MockPermissionType.reminders;
      case 'notifications':
        return MockPermissionType.notifications;
      case 'bluetooth':
        return MockPermissionType.bluetooth;
      case 'sensors':
        return MockPermissionType.sensors;
      case 'speech':
        return MockPermissionType.speech;
      case 'media_library':
        return MockPermissionType.mediaLibrary;
      default:
        throw ArgumentError('Unknown permission type: $value');
    }
  }
}

/// Permission states that can be mocked
enum MockPermissionState {
  granted,
  denied,
  restricted,
  limited,
  permanentDenied,
  provisional;

  static MockPermissionState fromString(String value) {
    switch (value) {
      case 'granted':
        return MockPermissionState.granted;
      case 'denied':
        return MockPermissionState.denied;
      case 'restricted':
        return MockPermissionState.restricted;
      case 'limited':
        return MockPermissionState.limited;
      case 'permanent_denied':
        return MockPermissionState.permanentDenied;
      case 'provisional':
        return MockPermissionState.provisional;
      default:
        throw ArgumentError('Unknown permission state: $value');
    }
  }
}

/// Connectivity states that can be mocked
enum MockConnectivityState {
  wifi,
  mobile,
  ethernet,
  bluetooth,
  vpn,
  none;

  static MockConnectivityState fromString(String value) {
    switch (value) {
      case 'wifi':
        return MockConnectivityState.wifi;
      case 'mobile':
        return MockConnectivityState.mobile;
      case 'ethernet':
        return MockConnectivityState.ethernet;
      case 'bluetooth':
        return MockConnectivityState.bluetooth;
      case 'vpn':
        return MockConnectivityState.vpn;
      case 'none':
        return MockConnectivityState.none;
      default:
        throw ArgumentError('Unknown connectivity state: $value');
    }
  }
}

/// Mock connectivity data
class MockConnectivity {
  final MockConnectivityState state;
  final bool isConnected;

  const MockConnectivity({required this.state, required this.isConnected});

  factory MockConnectivity.fromJson(Map<String, dynamic> json) {
    final state = MockConnectivityState.fromString(json['state'] as String);
    return MockConnectivity(
      state: state,
      isConnected:
          json['isConnected'] as bool? ?? (state != MockConnectivityState.none),
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'isConnected': isConnected,
  };

  @override
  String toString() => 'MockConnectivity($state, connected: $isConnected)';
}

// =====================================================================
// BIOMETRIC MOCK DATA TYPES
// =====================================================================

/// Biometric types that can be mocked
enum MockBiometricType {
  faceId,
  touchId,
  fingerprint,
  iris,
  deviceCredential;

  static MockBiometricType fromString(String value) {
    switch (value) {
      case 'faceId':
        return MockBiometricType.faceId;
      case 'touchId':
        return MockBiometricType.touchId;
      case 'fingerprint':
        return MockBiometricType.fingerprint;
      case 'iris':
        return MockBiometricType.iris;
      case 'deviceCredential':
        return MockBiometricType.deviceCredential;
      default:
        throw ArgumentError('Unknown biometric type: $value');
    }
  }
}

/// Biometric authentication result types
enum MockBiometricResult {
  success,
  failed,
  cancelled,
  notAvailable,
  notEnrolled,
  lockedOut;

  static MockBiometricResult fromString(String value) {
    switch (value) {
      case 'success':
        return MockBiometricResult.success;
      case 'failed':
        return MockBiometricResult.failed;
      case 'cancelled':
        return MockBiometricResult.cancelled;
      case 'notAvailable':
        return MockBiometricResult.notAvailable;
      case 'notEnrolled':
        return MockBiometricResult.notEnrolled;
      case 'lockedOut':
        return MockBiometricResult.lockedOut;
      default:
        throw ArgumentError('Unknown biometric result: $value');
    }
  }
}

/// Record of a biometric authentication attempt
class BiometricAttempt {
  final DateTime timestamp;
  final String type;
  final String result;
  final String? reason;

  BiometricAttempt({
    required this.timestamp,
    required this.type,
    required this.result,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'type': type,
    'result': result,
    if (reason != null) 'reason': reason,
  };

  factory BiometricAttempt.fromJson(Map<String, dynamic> json) {
    return BiometricAttempt(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      type: json['type'] as String,
      result: json['result'] as String,
      reason: json['reason'] as String?,
    );
  }

  @override
  String toString() =>
      'BiometricAttempt($type, $result at $timestamp${reason != null ? ', reason: $reason' : ''})';
}
