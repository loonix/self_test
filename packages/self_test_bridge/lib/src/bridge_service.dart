import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:self_test/self_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bridge_commands.dart';
import 'bridge_message.dart';
import 'mock_types.dart';
import 'bridge_navigator.dart';
import 'http_interceptor.dart';

// This file holds the bridge's state and its public surface. Every command
// implementation lives in a part file below, grouped by concern.
//
// Parts rather than separate libraries, and private extensions rather than
// separate classes, so each group reaches the state below directly and none
// of that state has to become public to make the split possible. Anything
// public stays declared on the class itself: a public member moved into a
// private extension would vanish from the package's API.
part 'bridge/shared.dart';
part 'bridge/accessibility.dart';
part 'bridge/actions.dart';
part 'bridge/assertions.dart';
part 'bridge/device.dart';
part 'bridge/discovery.dart';
part 'bridge/goldens.dart';
part 'bridge/memory.dart';
part 'bridge/mocks.dart';
part 'bridge/navigation.dart';
part 'bridge/network.dart';
part 'bridge/profiling.dart';
part 'bridge/server.dart';
part 'bridge/state.dart';
part 'bridge/storage.dart';
part 'bridge/test_recording.dart';
part 'bridge/time_travel.dart';
part 'bridge_models.dart';

/// WebSocket bridge service that enables MCP server communication.
///
/// This service runs inside the Flutter app and:
/// - Starts a WebSocket server on a specified port
/// - Receives commands from the MCP server
/// - Executes SelfTestManager operations
/// - Returns results to the MCP server
///
/// Implements Playwright feature parity for AI-powered testing.
class SelfTestBridge {
  /// The WebSocket server
  HttpServer? _server;

  /// Connected clients
  final List<WebSocket> _clients = [];

  /// Port to listen on
  final int port;

  /// The interface to listen on. Loopback unless the app says otherwise.
  ///
  /// The bridge can read the whole widget tree, tap anything, type anything
  /// and photograph the screen. Bound to every interface, which is what it did
  /// until now, that is offered to everyone on the same wifi.
  final InternetAddress host;

  /// The shared secret a client has to present as `?token=` to connect.
  ///
  /// Generated per instance when the app does not supply one, so a bridge left
  /// running is not open by default. It is printed once at startup.
  final String token;

  /// Whether this bridge may run in a release build.
  final bool allowInReleaseBuilds;

  /// How this bridge navigates, or null when the app configured nothing.
  ///
  /// Null is honest rather than convenient: the navigation commands answer with
  /// an error instead of reporting success for a move that never happened.
  final BridgeNavigator? navigator;

  /// Whether the bridge is running
  bool get isRunning => _server != null;

  /// Console messages buffer
  final List<Map<String, dynamic>> _consoleMessages = [];

  /// Error buffer
  final List<Map<String, dynamic>> _errors = [];

  /// Network requests log
  final List<Map<String, dynamic>> _networkLog = [];

  /// HTTP mocks
  final Map<String, Map<String, dynamic>> _httpMocks = {};

  /// Blocked HTTP patterns
  final Set<String> _blockedPatterns = {};

  /// Pending network requests for waitNetwork
  final Map<String, Completer<Map<String, dynamic>>> _pendingNetworkWaits = {};

  /// Tracing state
  bool _isTracing = false;

  String? _traceName;

  bool _traceScreenshots = false;

  final List<Map<String, dynamic>> _traceEvents = [];

  /// Recording state
  bool _isRecording = false;

  String? _recordingName;

  final List<Uint8List> _recordingFrames = [];

  Timer? _recordingTimer;

  /// State snapshots
  final Map<String, Map<String, dynamic>> _savedStates = {};

  /// File picker mock files
  List<String>? _filePickerMockFiles;

  /// The paths the `filePicker` command last staged, or null when none were.
  ///
  /// The bridge cannot reach into a plugin's picker, so the app has to read
  /// this and return it from its own picker call. Without this getter the
  /// command was staging a list nothing could ever read.
  List<String>? get filePickerMockFiles => _filePickerMockFiles == null
      ? null
      : List<String>.unmodifiable(_filePickerMockFiles!);

  /// Project root directory (for relative golden paths)
  String? _projectRoot;

  /// HTTP interceptor instance (lazily created)
  SelfTestHttpInterceptor? _httpInterceptor;

  /// Platform channel mocks: Map<channelName, Map<methodName, mockConfig>>
  final Map<String, Map<String, _ChannelMockConfig>> _channelMocks = {};

  /// Platform channel call log
  final List<Map<String, dynamic>> _channelCallLog = [];

  /// Whether channel mocking is initialized
  bool _channelMockingInitialized = false;

  // ===========================================================================
  // FRAME BUDGET ANALYSIS STATE
  // ===========================================================================

  /// Frame timing data collected during profiling
  final List<FrameTiming> _frameTimings = [];

  /// Whether frame profiling is active
  bool _isProfilingFrames = false;

  /// Frame budget in milliseconds (default 16.67ms for 60fps)
  double _frameBudgetMs = 16.67;

  /// Jank detector state
  bool _jankDetectorEnabled = false;

  double _jankThresholdMs = 16.67;

  int _jankDetectorTotalFrames = 0;

  int _jankDetectorJankyFrames = 0;

  double _jankDetectorWorstFrameMs = 0;

  // ===========================================================================
  // STATE MANAGEMENT INSPECTION
  // ===========================================================================

  /// Registered state providers for inspection
  final Map<String, _StateProviderConfig> _stateProviders = {};

  /// State watch subscriptions
  final Map<String, _StateWatchSubscription> _stateWatches = {};

  /// Counter for generating subscription IDs
  int _subscriptionIdCounter = 0;

  /// Riverpod container reference (set via registerRiverpodContainer)
  dynamic _riverpodContainer;

  // ===========================================================================
  // STATE DEPENDENCY GRAPH
  // ===========================================================================

  /// Provider dependencies: Map<providerId, Set<dependsOnProviderIds>>
  final Map<String, Set<String>> _providerDependencies = {};

  /// Provider dependents: Map<providerId, Set<providerIdsThatDependOnThis>>
  final Map<String, Set<String>> _providerDependents = {};

  /// Widget consumers: Map<providerId, Set<widgetKeys>>
  final Map<String, Set<String>> _widgetConsumers = {};

  // ===========================================================================
  // SENSOR & DEVICE MOCKING STATE
  // ===========================================================================

  /// Current mock location
  MockLocation? _mockLocation;

  /// Mock permission states: Map<permission, state>
  final Map<MockPermissionType, MockPermissionState> _mockPermissions = {};

  /// Current mock connectivity state
  MockConnectivity? _mockConnectivity;

  // ===========================================================================
  // WIDGET REBUILD PROFILING STATE
  // ===========================================================================

  /// Whether rebuild profiling is currently active
  bool _isProfilingRebuilds = false;

  /// Timestamp when profiling started
  DateTime? _rebuildProfilingStartTime;

  /// Rebuild data: Map of widget identifier to rebuild info
  final Map<String, _RebuildInfo> _rebuildProfile = {};

  /// The previous debug callback (to restore when stopping)
  void Function(Duration)? _rebuildProfilingFrameCallback;

  // ===========================================================================
  // APP LIFECYCLE TESTING STATE
  // ===========================================================================

  /// Current simulated lifecycle state
  AppLifecycleState _currentLifecycleState = AppLifecycleState.resumed;

  /// History of lifecycle events
  final List<AppLifecycleEvent> _lifecycleHistory = [];

  /// Current simulated locale
  Locale _currentLocale = const Locale('en', 'US');

  /// Current simulated text scale factor
  double _currentTextScale = 1.0;

  /// Current simulated brightness mode
  Brightness _currentBrightness = Brightness.light;

  /// List of caches cleared during memory pressure simulation
  final List<String> _clearedCaches = [];

  // ===========================================================================
  // TIME-TRAVEL STATE SNAPSHOTS STATE
  // ===========================================================================

  /// Whether time-travel recording is active
  bool _isRecordingTimeline = false;

  /// List of captured time-travel snapshots
  final List<_AppSnapshot> _timelineSnapshots = [];

  /// Timer for automatic snapshot capture at intervals
  Timer? _snapshotTimer;

  /// Whether to capture snapshots on user interaction
  bool _captureOnInteraction = false;

  // ===========================================================================
  // NAVIGATION STACK INSPECTOR STATE
  // ===========================================================================

  /// Navigation history events
  final List<NavigationEvent> _navigationHistory = [];

  /// Route stack tracked by observer
  final List<Route<dynamic>> _routeStack = [];

  /// Navigation observer for tracking
  late final NavigationInspectorObserver _navigationObserver;

  /// Whether navigation observer is attached
  bool _navigationObserverAttached = false;

  // ===========================================================================
  // BIOMETRIC AUTHENTICATION MOCKING STATE
  // ===========================================================================

  /// Available biometric types
  bool _biometricFaceIdAvailable = false;

  bool _biometricTouchIdAvailable = false;

  bool _biometricFingerprintAvailable = false;

  bool _biometricIrisAvailable = false;

  bool _biometricDeviceCredentialAvailable = true;

  /// Next biometric auth result configuration
  MockBiometricResult _nextBiometricResult = MockBiometricResult.success;

  String? _nextBiometricErrorMessage;

  int _nextBiometricDelay = 0;

  /// History of biometric authentication attempts
  final List<BiometricAttempt> _biometricHistory = [];

  /// Static callback for apps to use instead of real local_auth.
  /// When set, this callback is invoked during biometric authentication.
  ///
  /// Example:
  /// ```dart
  /// SelfTestBridge.onBiometricAuth = (reason) async {
  ///   // This is called when authenticate() is called
  ///   // The result is determined by the configured mock result
  ///   return true; // or false based on mock configuration
  /// };
  /// ```
  static Future<bool> Function(String reason)? onBiometricAuth;

  // ===========================================================================
  // PUSH NOTIFICATION MOCKING STATE
  // ===========================================================================

  /// History of simulated notifications
  final List<MockNotification> _notificationHistory = [];

  /// Counter for generating notification IDs
  int _notificationIdCounter = 0;

  /// Mock FCM token (generated once and reused)
  String? _mockFcmToken;

  /// Handler flags
  bool _notificationOnReceiveEnabled = false;

  bool _notificationOnTapEnabled = false;

  bool _notificationOnDismissEnabled = false;

  /// Static callback that apps can set to handle notifications.
  /// This is invoked when a notification is "received" with action 'received'.
  ///
  /// Example:
  /// ```dart
  /// SelfTestBridge.onNotificationReceived = (notification) {
  ///   // Handle the mock notification
  ///   showLocalNotification(notification);
  /// };
  /// ```
  static void Function(MockNotification notification)? onNotificationReceived;

  /// Static callback for when a notification is tapped.
  ///
  /// Example:
  /// ```dart
  /// SelfTestBridge.onNotificationTap = (notification) {
  ///   // Navigate based on notification data
  ///   myBridgeNavigator.goTo(notification.data['deep_link']);
  /// };
  /// ```
  static void Function(MockNotification notification)? onNotificationTap;

  /// Static callback for when a notification is dismissed.
  static void Function(MockNotification notification)? onNotificationDismiss;

  // ===========================================================================
  // MEMORY PROFILING STATE
  // ===========================================================================

  /// Whether memory profiling is currently active
  bool _isProfilingMemory = false;

  /// Timer for memory profiling intervals
  Timer? _memoryProfilingTimer;

  /// Memory samples collected during profiling
  final List<_MemorySample> _memorySamples = [];

  // ===========================================================================
  // WIDGET TEST GENERATION STATE
  // ===========================================================================

  /// Whether test recording is currently active
  bool _isRecordingTest = false;

  /// Current test recording ID
  String? _currentTestId;

  /// Current test name
  String? _currentTestName;

  /// Current test description
  String? _currentTestDescription;

  /// Recorded steps for test generation
  final List<_RecordedStep> _recordedSteps = [];

  // ===========================================================================
  // DEEP LINK TESTING STATE
  // ===========================================================================

  /// History of deep links received during the session
  final List<DeepLinkEvent> _deepLinkHistory = [];

  /// Registered URL schemes the app handles
  final Set<String> _registeredSchemes = {};

  // ===========================================================================
  // STATIC CALLBACKS FOR APP INTEGRATION
  // ===========================================================================

  /// Callback invoked when mock location is set.
  /// Register this to receive mock GPS coordinates in your app.
  ///
  /// Example:
  /// ```dart
  /// SelfTestBridge.onLocationChanged = (location) {
  ///   // Update your location provider with mock data
  ///   myLocationService.updateLocation(
  ///     latitude: location.latitude,
  ///     longitude: location.longitude,
  ///   );
  /// };
  /// ```
  static void Function(MockLocation location)? onLocationChanged;

  /// Callback invoked when permission state is requested.
  /// Return the mock state for the given permission, or null to use real permissions.
  ///
  /// Example:
  /// ```dart
  /// SelfTestBridge.onPermissionRequested = (permission) {
  ///   // Return mock permission state or null for real permissions
  ///   return _mockPermissionStates[permission];
  /// };
  /// ```
  static MockPermissionState? Function(MockPermissionType permission)?
  onPermissionRequested;

  /// Callback invoked when connectivity state changes.
  /// Register this to receive mock connectivity updates.
  ///
  /// Example:
  /// ```dart
  /// SelfTestBridge.onConnectivityChanged = (connectivity) {
  ///   // Update your connectivity provider
  ///   myConnectivityService.setConnectivity(
  ///     type: connectivity.state,
  ///     isConnected: connectivity.isConnected,
  ///   );
  /// };
  /// ```
  static void Function(MockConnectivity connectivity)? onConnectivityChanged;

  /// Get the current mock location, if set
  MockLocation? get mockLocation => _mockLocation;

  /// Get the mock state for a permission, if set
  MockPermissionState? getMockPermission(MockPermissionType permission) =>
      _mockPermissions[permission];

  /// Get the current mock connectivity, if set
  MockConnectivity? get mockConnectivity => _mockConnectivity;

  /// Create a new bridge instance
  ///
  /// [host] defaults to loopback, so only this machine can connect. Pass
  /// `InternetAddress.anyIPv4` to reach it from a real device, and understand
  /// that everyone else on that network can reach it too.
  ///
  /// [token] defaults to a fresh random secret, printed at startup.
  SelfTestBridge({
    this.navigator,
    this.port = 9999,
    String? projectRoot,
    InternetAddress? host,
    String? token,
    this.allowInReleaseBuilds = false,
  }) : _projectRoot = projectRoot,

       host = host ?? InternetAddress.loopbackIPv4,
       token = token ?? _generateToken();

  /// The port actually listening.
  ///
  /// Differs from [port] when the app passed 0 to let the operating system
  /// pick one, which is what a test does to avoid fighting over 9999.
  int get boundPort => _server?.port ?? port;

  /// The URL a client connects to, token included.
  String get url => 'ws://${host.address}:$boundPort?token=$token';

  /// Set the project root directory for golden file storage.
  /// This should be the root directory of your Flutter project.
  void setProjectRoot(String path) {
    _projectRoot = path;
  }

  /// Get the Dio HTTP interceptor for this bridge.
  ///
  /// Add this interceptor to your Dio instance to enable HTTP mocking,
  /// blocking, and network logging controlled by the bridge.
  ///
  /// Example:
  /// ```dart
  /// final bridge = SelfTestBridge();
  /// final dio = Dio();
  /// dio.interceptors.add(bridge.httpInterceptor);
  /// ```
  SelfTestHttpInterceptor get httpInterceptor {
    _httpInterceptor ??= SelfTestHttpInterceptor(
      httpMocks: _httpMocks,
      blockedPatterns: _blockedPatterns,
      networkLog: _networkLog,
      pendingNetworkWaits: _pendingNetworkWaits,
    );
    return _httpInterceptor!;
  }

  /// Start the WebSocket server
  Future<void> start() async {
    if (_server != null) {
      debugPrint('[SelfTestBridge] Already running');
      return;
    }

    if (!allowInReleaseBuilds && !SelfTestManager.isEnabled) {
      throw StateError(
        'The self_test bridge refuses to start: self_test is disabled in '
        'release builds, and a bridge in a shipped app is a remote control '
        'for it. Pass allowInReleaseBuilds: true if that is really what you '
        'want.',
      );
    }

    try {
      _server = await HttpServer.bind(host, port);
      debugPrint('[SelfTestBridge] Listening on ${host.address}:$port');
      if (!host.isLoopback) {
        SelfTestManager.printWarning(
          'The bridge is bound to ${host.address}, not loopback. Everyone who '
          'can reach this device on the network can drive this app if they '
          'have the token.',
        );
      }
      debugPrint('[SelfTestBridge] Connect with: $url');

      // Setup error capture
      FlutterError.onError = (details) {
        _captureError(details);
        FlutterError.presentError(details);
      };

      _server!.listen(
        _handleRequest,
        onError: (Object error) {
          debugPrint('[SelfTestBridge] Server error: $error');
        },
      );
    } catch (e) {
      debugPrint('[SelfTestBridge] Failed to start server: $e');
      rethrow;
    }
  }

  /// Stop the WebSocket server
  Future<void> stop() async {
    _recordingTimer?.cancel();
    for (final client in _clients) {
      await client.close();
    }
    _clients.clear();

    await _server?.close();
    _server = null;
    debugPrint('[SelfTestBridge] Server stopped');
  }

  /// Handle a command from the MCP server
  /// Runs [command] exactly as one arriving over the socket would, error
  /// handling included.
  ///
  /// The dispatcher is where the bridge's behaviour lives, and a test that
  /// drove it through a real WebSocket could not also pump a widget tree:
  /// `flutter_test`'s fake clock and real socket I/O do not mix.
  @visibleForTesting
  Future<BridgeResponse> dispatchForTest(BridgeCommand command) =>
      _handleCommand(command);

  /// Clear all mock states
  void clearMockStates() {
    _mockLocation = null;
    _mockPermissions.clear();
    _mockConnectivity = null;
    _logConsole('info', 'All mock states cleared');
  }

  /// Check if a permission has a mock state set
  bool hasPermissionMock(MockPermissionType permission) {
    return _mockPermissions.containsKey(permission);
  }

  /// Get all mock permission states
  Map<MockPermissionType, MockPermissionState> get allMockPermissions =>
      Map.unmodifiable(_mockPermissions);

  /// Get list of available biometric types
  List<String> getAvailableBiometrics() {
    final available = <String>[];
    if (_biometricFaceIdAvailable) available.add('faceId');
    if (_biometricTouchIdAvailable) available.add('touchId');
    if (_biometricFingerprintAvailable) available.add('fingerprint');
    if (_biometricIrisAvailable) available.add('iris');
    if (_biometricDeviceCredentialAvailable) available.add('deviceCredential');
    return available;
  }

  /// Check if any biometric type is available
  bool get hasBiometricsAvailable =>
      _biometricFaceIdAvailable ||
      _biometricTouchIdAvailable ||
      _biometricFingerprintAvailable ||
      _biometricIrisAvailable ||
      _biometricDeviceCredentialAvailable;

  /// Get the configured next biometric result
  MockBiometricResult get nextBiometricResult => _nextBiometricResult;

  /// Authenticate using mock biometrics (for app integration).
  Future<Map<String, dynamic>> authenticateBiometric({
    required String localizedReason,
    bool biometricOnly = false,
    String? preferredType,
  }) async {
    return _simulateBiometricPrompt(localizedReason, preferredType);
  }

  // ===========================================================================
  // STATE MANAGEMENT INSPECTION IMPLEMENTATIONS
  // ===========================================================================

  /// Register a Riverpod ProviderContainer for state inspection.
  ///
  /// Call this method during app initialization to enable Riverpod state inspection:
  /// ```dart
  /// final container = ProviderContainer();
  /// bridge.registerRiverpodContainer(container);
  /// ```
  void registerRiverpodContainer(dynamic container) {
    _riverpodContainer = container;
    _logConsole('info', 'Riverpod container registered for state inspection');
  }

  /// Register a state provider for inspection.
  ///
  /// This allows the bridge to read and manipulate state from various state management
  /// solutions. The callbacks provide the interface for state operations.
  ///
  /// Example for a custom state:
  /// ```dart
  /// bridge.registerStateProvider(
  ///   'counterState',
  ///   type: 'custom',
  ///   getState: () => {'count': counter.value},
  ///   dispatchAction: (action, payload) {
  ///     if (action == 'increment') counter.increment();
  ///     if (action == 'decrement') counter.decrement();
  ///   },
  /// );
  /// ```
  void registerStateProvider(
    String providerId, {
    required String type,
    required Map<String, dynamic> Function() getState,
    void Function(String action, dynamic payload)? dispatchAction,
    Stream<Map<String, dynamic>>? stateStream,
  }) {
    _stateProviders[providerId] = _StateProviderConfig(
      id: providerId,
      type: type,
      getState: getState,
      dispatchAction: dispatchAction,
      stateStream: stateStream,
    );
    _logConsole('info', 'State provider registered: $providerId ($type)');
  }

  /// Unregister a state provider.
  void unregisterStateProvider(String providerId) {
    _stateProviders.remove(providerId);
  }

  // ===========================================================================
  // STATE DEPENDENCY GRAPH IMPLEMENTATIONS
  // ===========================================================================

  /// Record a dependency between two providers.
  /// Call this when a provider reads from or depends on another provider.
  void recordStateDependency(String consumer, String dependency) {
    _providerDependencies
        .putIfAbsent(consumer, () => <String>{})
        .add(dependency);
    _providerDependents.putIfAbsent(dependency, () => <String>{}).add(consumer);
  }

  /// Record that a widget consumes a provider.
  /// Call this when a widget reads or watches a provider.
  void recordWidgetConsumer(String providerId, String widgetKey) {
    _widgetConsumers.putIfAbsent(providerId, () => <String>{}).add(widgetKey);
  }

  /// Clear a specific dependency.
  void clearStateDependency(String consumer, String dependency) {
    _providerDependencies[consumer]?.remove(dependency);
    _providerDependents[dependency]?.remove(consumer);
  }

  /// Clear all dependencies for a provider.
  void clearProviderDependencies(String providerId) {
    // Remove from dependencies
    final deps = _providerDependencies.remove(providerId);
    if (deps != null) {
      for (final dep in deps) {
        _providerDependents[dep]?.remove(providerId);
      }
    }

    // Remove from dependents
    final dependents = _providerDependents.remove(providerId);
    if (dependents != null) {
      for (final dependent in dependents) {
        _providerDependencies[dependent]?.remove(providerId);
      }
    }

    // Remove widget consumers
    _widgetConsumers.remove(providerId);
  }

  /// Get the current simulated locale.
  Locale get currentLocale => _currentLocale;

  /// Get the current simulated text scale factor.
  double get currentTextScale => _currentTextScale;

  /// Get the current simulated brightness.
  Brightness get currentBrightness => _currentBrightness;

  /// Clear lifecycle history.
  void clearLifecycleHistory() {
    _lifecycleHistory.clear();
  }

  /// Get the navigation observer to attach to a Navigator
  NavigationInspectorObserver get navigationObserver {
    _ensureNavigationObserver();
    return _navigationObserver;
  }

  // ===========================================================================
  // SEMANTIC LABEL AUTO-GENERATION IMPLEMENTATIONS
  // ===========================================================================

  /// Cached semantic suggestions for applySuggestedSemantics
  final Map<String, _SemanticSuggestion> _cachedSuggestions = {};
}
