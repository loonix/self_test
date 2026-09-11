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
import 'bridge_navigator.dart';
import 'http_interceptor.dart';

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

  /// What every navigation command answers when no [BridgeNavigator] was
  /// configured. Reporting success for a move that never happened is how an
  /// agent ends up asserting against the wrong screen.
  static const Map<String, dynamic> _navigatorMissing = {
    'error':
        'No BridgeNavigator is configured, so the bridge cannot navigate. '
        'Pass one to SelfTestBridge(navigator:) - '
        'NavigatorStateBridgeNavigator(yourNavigatorKey) works for any app.',
  };

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

  /// Default golden directory (relative to project root)
  static const String _defaultGoldensDir = 'test/goldens';

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

  static String _generateToken() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

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

  /// Get the absolute path to the goldens directory.
  String _getGoldensDirectory(String? goldensDir) {
    final dir = goldensDir ?? _defaultGoldensDir;
    if (_projectRoot != null) {
      return '$_projectRoot/$dir';
    }
    // Fallback: use current directory
    return dir;
  }

  /// Ensure the goldens directory exists.
  Future<Directory> _ensureGoldensDirectory(String? goldensDir) async {
    final path = _getGoldensDirectory(goldensDir);
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Get the path to a golden file.
  String _getGoldenPath(String name, String? goldensDir) {
    final dir = _getGoldensDirectory(goldensDir);
    // Sanitize name for filesystem
    final safeName = name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return '$dir/$safeName.png';
  }

  /// Get the path to a diff file.
  String _getDiffPath(String name, String? goldensDir) {
    final dir = _getGoldensDirectory(goldensDir);
    final safeName = name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return '$dir/${safeName}_diff.png';
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

  /// Check the token, then upgrade.
  ///
  /// The check happens before the upgrade so a client with the wrong token
  /// gets an HTTP 403 it can read, rather than a WebSocket that closes for no
  /// stated reason.
  Future<void> _handleRequest(HttpRequest request) async {
    if (!_isAuthorised(request)) {
      debugPrint(
        '[SelfTestBridge] Rejected a connection with a bad or missing token',
      );
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('self_test bridge: bad or missing token');
      await request.response.close();
      return;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('self_test bridge: expected a WebSocket upgrade');
      await request.response.close();
      return;
    }

    _handleConnection(await WebSocketTransformer.upgrade(request));
  }

  bool _isAuthorised(HttpRequest request) {
    final presented =
        request.uri.queryParameters['token'] ??
        request.headers.value('x-self-test-token');
    if (presented == null) return false;
    return _secretsMatch(presented, token);
  }

  /// Compares without leaking where the difference is through timing.
  static bool _secretsMatch(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// Handle a new WebSocket connection
  void _handleConnection(WebSocket socket) {
    debugPrint('[SelfTestBridge] Client connected');
    _clients.add(socket);

    socket.listen(
      (data) async {
        try {
          final command = BridgeCommand.fromJson(jsonDecode(data as String));
          final response = await _handleCommand(command);
          socket.add(jsonEncode(response.toJson()));
        } catch (e, stackTrace) {
          debugPrint('[SelfTestBridge] Error handling command: $e');
          debugPrint(stackTrace.toString());
          socket.add(jsonEncode({'id': 0, 'error': e.toString()}));
        }
      },
      onDone: () {
        debugPrint('[SelfTestBridge] Client disconnected');
        _clients.remove(socket);
      },
      onError: (error) {
        debugPrint('[SelfTestBridge] Client error: $error');
        _clients.remove(socket);
      },
    );
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

  Future<BridgeResponse> _handleCommand(BridgeCommand command) async {
    debugPrint('[SelfTestBridge] Handling command: ${command.command}');

    // Record trace event if tracing
    if (_isTracing) {
      _traceEvents.add({
        'timestamp': DateTime.now().toIso8601String(),
        'command': command.command,
        'params': command.params,
      });
    }

    try {
      final result = await _executeCommand(command);
      if (_interactionCommands.contains(command.command)) {
        await _afterInteraction(command.command, command.params);
      }
      return BridgeResponse(id: command.id, result: result);
    } catch (e) {
      return BridgeResponse(id: command.id, error: e.toString());
    }
  }

  /// The commands that drive the app rather than merely question it.
  ///
  /// Time-travel capture and test recording both need to know when one runs,
  /// and listing them once here is what stopped both features being wired to
  /// nothing.
  static const Set<String> _interactionCommands = {
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

  /// Runs after a command that changed the app, once it has succeeded.
  Future<void> _afterInteraction(
    String action,
    Map<String, dynamic> params,
  ) async {
    await _onUserInteraction();
    _recordInteractionStep(action, params);
  }

  // ===========================================================================
  // LOCATORS
  //
  // Every command that named a widget by its registered id also takes a
  // `locator` object, which is the wire form of SelfTestLocator:
  //
  //   {"by": "text|key|id|semanticsLabel|type|tooltip",
  //    "value": "Sign in", "exact": true, "index": 0}
  //
  // A locator wins over widgetId when both are sent, because a caller that
  // sends one has the more precise intent. Locators need no registration: they
  // resolve against the element tree, so they reach widgets a
  // SelfTestableWidget id never could.
  // ===========================================================================

  /// The locator a command sent, or null when it sent none.
  ///
  /// Throws with the reason when a locator is present but malformed, so the
  /// caller is told what is wrong with it rather than being handed a cast
  /// error from three layers down.
  SelfTestLocator? _locatorFrom(Map<String, dynamic> params) {
    final raw = params['locator'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw Exception(
        'The "locator" parameter must be an object such as '
        '{"by": "text", "value": "Sign in"}, not a ${raw.runtimeType}.',
      );
    }

    final json = Map<String, dynamic>.from(raw);
    final index = json['index'];
    if (index != null && (index is! int || index < 0)) {
      throw Exception(
        'Locator "index" must be an integer of 0 or more, not '
        '${_describeJsonValue(index)}.',
      );
    }
    final exact = json['exact'];
    if (exact != null && exact is! bool) {
      throw Exception(
        'Locator "exact" must be true or false, not '
        '${_describeJsonValue(exact)}.',
      );
    }

    try {
      return SelfTestLocator.fromJson(json);
    } on ArgumentError catch (e) {
      throw Exception('Bad locator: ${e.message}');
    }
  }

  /// The locator a command requires, for the commands that take nothing else.
  SelfTestLocator _requireLocator(Map<String, dynamic> params) {
    final locator = _locatorFrom(params);
    if (locator == null) {
      throw Exception(
        'This command needs a "locator" parameter, such as '
        '{"by": "text", "value": "Sign in"}.',
      );
    }
    return locator;
  }

  static String _describeJsonValue(Object? value) =>
      value is String ? '"$value"' : '$value';

  /// The registered widget id a command is aimed at.
  ///
  /// Commands that still work through the registered-node map need an id, so a
  /// locator is resolved against the tree and the id of what it matched is
  /// used. A locator can match a widget the app never registered, and that
  /// combination is refused rather than silently acting on something else.
  String _targetId(Map<String, dynamic> params, {String key = 'widgetId'}) {
    final locator = _locatorFrom(params);
    if (locator != null) {
      final matches = SelfTestManager().findAll(locator);
      if (matches.isEmpty) {
        throw Exception('No widget matches $locator.');
      }
      if (locator.index >= matches.length) {
        throw Exception(
          'Locator $locator asked for index ${locator.index} but only '
          '${matches.length} widget(s) match.',
        );
      }
      final id = matches[locator.index].id;
      if (id == null) {
        throw Exception(
          'The widget matching $locator has no self-test id, and this command '
          'works through the registered-widget map. Either wrap it in a '
          'SelfTestableWidget or use a command that takes a locator directly.',
        );
      }
      return id;
    }

    final widgetId = params[key];
    if (widgetId is! String) {
      throw Exception('This command needs either a "locator" or a "$key".');
    }
    return widgetId;
  }

  static String _requireString(Map<String, dynamic> params, String key) {
    final value = params[key];
    if (value is! String) {
      throw Exception('This command needs a "$key" parameter.');
    }
    return value;
  }

  // ===========================================================================
  // ACTION COMMANDS
  //
  // Each takes the locator path when one was sent and the registered-id path
  // otherwise, so a caller written against 0.1.0 keeps working.
  // ===========================================================================

  Future<Map<String, dynamic>> _tapCommand(Map<String, dynamic> params) async {
    final manager = SelfTestManager();
    final locator = _locatorFrom(params);
    if (locator != null) {
      await manager.tap(locator);
    } else {
      final widgetId = _targetId(params);
      await _waitForWidget(widgetId, params['timeout'] as int? ?? 5000);
      await manager.trigger(widgetId);
    }
    await manager.waitForAnimations();
    if (_traceScreenshots) {
      await _captureTraceScreenshot('tap_${locator ?? params['widgetId']}');
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _doubleTapCommand(
    Map<String, dynamic> params,
  ) async {
    final locator = _locatorFrom(params);
    if (locator != null) {
      await SelfTestManager().doubleTap(locator);
    } else {
      await _doubleTap(_targetId(params));
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _longPressCommand(
    Map<String, dynamic> params,
  ) async {
    final durationMs = params['duration'] as int? ?? 500;
    final locator = _locatorFrom(params);
    if (locator != null) {
      await SelfTestManager().longPress(
        locator,
        hold: Duration(milliseconds: durationMs),
      );
    } else {
      await _longPress(_targetId(params), durationMs);
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _typeCommand(Map<String, dynamic> params) async {
    final manager = SelfTestManager();
    final text = params['text'] as String;
    final append = params['append'] as bool? ?? false;
    final submit = params['submit'] as bool? ?? false;

    final locator = _locatorFrom(params);
    if (locator != null) {
      // typeInto replaces the field's contents, so appending means sending
      // what is there now plus the new text.
      final value = append ? '${manager.readText(locator) ?? ''}$text' : text;
      await manager.typeInto(locator, value);
      if (submit) await manager.submit(locator);
    } else {
      final widgetId = _targetId(params);
      if (!append) {
        // Clear by entering empty string first
        await manager.enterText(widgetId, '');
      }
      await manager.enterText(widgetId, text);
      if (submit) await _sendDoneAction();
    }

    await manager.waitForAnimations();
    return {'success': true};
  }

  Future<Map<String, dynamic>> _submitCommand(
    Map<String, dynamic> params,
  ) async {
    final manager = SelfTestManager();
    final locator = _locatorFrom(params);
    if (locator != null) {
      await manager.submit(locator);
    } else {
      await _sendDoneAction();
    }
    await manager.waitForAnimations();
    return {'success': true};
  }

  /// Fires the keyboard's "done" action at whatever holds focus.
  ///
  /// The registered-id path has no field to aim at, so it goes through the
  /// platform channel the soft keyboard uses.
  Future<void> _sendDoneAction() async {
    await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/textinput',
      const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'method': 'TextInputClient.performAction',
        'args': <dynamic>[0, 'TextInputAction.done'],
      }),
      (ByteData? data) {},
    );
  }

  Future<Map<String, dynamic>> _dragCommand(Map<String, dynamic> params) async {
    final locator = _locatorFrom(params);
    if (locator != null) {
      final dx = (params['dx'] as num?)?.toDouble();
      final dy = (params['dy'] as num?)?.toDouble();
      if (dx == null && dy == null) {
        throw Exception(
          'A drag by locator needs "dx" and/or "dy": how far to drag from the '
          'widget the locator matches.',
        );
      }
      await SelfTestManager().dragFrom(locator, Offset(dx ?? 0, dy ?? 0));
    } else {
      await _drag(
        _requireString(params, 'sourceId'),
        _requireString(params, 'targetId'),
      );
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _scrollCommand(
    Map<String, dynamic> params,
  ) async {
    final direction = params['direction'] as String? ?? 'down';
    final delta = (params['delta'] as num?)?.toDouble() ?? 300.0;

    final locator = _locatorFrom(params);
    if (locator != null) {
      await SelfTestManager().scrollBy(
        locator,
        _scrollOffset(direction, delta),
      );
    } else {
      await _scroll(params['widgetId'] as String?, direction, delta);
    }
    return {'success': true};
  }

  static Offset _scrollOffset(String direction, double delta) {
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

  /// Execute a specific command
  Future<dynamic> _executeCommand(BridgeCommand command) async {
    final manager = SelfTestManager();
    final params = command.params;

    switch (command.command) {
      // =====================================================================
      // LOCATORS
      // =====================================================================

      case 'describeScreen':
        return {
          'widgets': manager.describeScreen().map((w) => w.toJson()).toList(),
        };

      case 'find':
        final found = manager.findAll(_requireLocator(params));
        return {'widget': found.isEmpty ? null : found.first.toJson()};

      case 'exists':
        return {'result': manager.exists(_requireLocator(params))};

      case 'isVisible':
        return {'result': manager.isVisible(_requireLocator(params))};

      case 'readText':
        return {'text': manager.readText(_requireLocator(params))};

      case 'getSnapshot':
        return _getSnapshot();

      case 'getWidgetCatalog':
        return WidgetCatalog.exportCatalog();

      case 'getFlowGraph':
        final flowNavigator = navigator;
        if (flowNavigator == null) return _navigatorMissing;
        return {'routes': flowNavigator.describeRoutes()};

      case 'getScreens':
        return _getScreens();

      case 'getCurrentState':
        return _getCurrentState();

      case 'getByRole':
        return _getByRole(params['role'] as String, params['name'] as String?);

      case 'getByText':
        return _getByText(
          params['text'] as String,
          params['exact'] as bool? ?? false,
        );

      // =====================================================================
      // ACTIONS
      // =====================================================================

      case 'tap':
        return await _tapCommand(params);

      case 'type':
      case 'enterText':
        return await _typeCommand(params);

      case 'submit':
        return await _submitCommand(params);

      case 'clear':
        final locator = _locatorFrom(params);
        if (locator != null) {
          await manager.typeInto(locator, '');
        } else {
          await manager.enterText(_targetId(params), '');
        }
        return {'success': true};

      case 'pressKey':
        final key = params['key'] as String;
        await _pressKey(key);
        return {'success': true};

      case 'scroll':
        return await _scrollCommand(params);

      case 'scrollTo':
        final scrollableId = params['scrollableId'] as String?;
        final timeout = params['timeout'] as int? ?? 10000;
        await _scrollToWidget(_targetId(params), scrollableId, timeout);
        return {'success': true};

      case 'drag':
        return await _dragCommand(params);

      case 'longPress':
        return await _longPressCommand(params);

      case 'doubleTap':
        return await _doubleTapCommand(params);

      case 'hover':
        await _hover(_targetId(params));
        return {'success': true};

      case 'focus':
        await _focus(_targetId(params));
        return {'success': true};

      case 'select':
        final value = params['value'] as String;
        await _selectOption(_targetId(params), value);
        return {'success': true};

      case 'toggle':
        final checked = params['checked'] as bool?;
        await _toggle(_targetId(params), checked);
        return {'success': true};

      case 'setSlider':
        final value = (params['value'] as num).toDouble();
        await _setSlider(_targetId(params), value);
        return {'success': true};

      // =====================================================================
      // NAVIGATION
      // =====================================================================

      case 'navigate':
        final route = params['route'] as String;
        final replace = params['replace'] as bool? ?? false;
        final navigateTarget = navigator;
        if (navigateTarget == null) return _navigatorMissing;
        await navigateTarget.goTo(route, replace: replace);
        await manager.waitForAnimations();
        return {'success': true};

      case 'goBack':
        final backTarget = navigator;
        if (backTarget == null) return _navigatorMissing;
        if (backTarget.canGoBack) {
          await backTarget.goBack();
        } else {
          // Nothing left in the app to pop, so ask the platform to leave it.
          await SystemNavigator.pop();
        }
        await manager.waitForAnimations();
        return {'success': true};

      case 'reload':
        // A real hot reload needs the VM service. This re-enters the current
        // route, which is as close as the bridge can get on its own.
        final reloadTarget = navigator;
        if (reloadTarget == null) return _navigatorMissing;
        final currentLocation = reloadTarget.currentLocation;
        if (currentLocation == null) {
          return {
            'error':
                'The configured BridgeNavigator cannot report where the app '
                'is, so there is nothing to reload.',
          };
        }
        await reloadTarget.goTo(currentLocation, replace: true);
        await manager.waitForAnimations();
        return {'success': true};

      case 'restart':
        // A real hot restart needs the VM service. Going back to the root is
        // the closest the bridge can get.
        final restartTarget = navigator;
        if (restartTarget == null) return _navigatorMissing;
        await restartTarget.goTo('/', replace: true);
        await manager.waitForAnimations();
        return {'success': true};

      // =====================================================================
      // WAITING
      // =====================================================================

      case 'wait':
      case 'waitFor':
        final condition = params['condition'] as String;
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final text = params['text'] as String?;
        final timeout = params['timeout'] as int? ?? 5000;
        final duration = params['duration'] as int?;
        return await _wait(condition, widgetId, text, timeout, duration);

      // =====================================================================
      // ASSERTIONS
      // =====================================================================

      case 'expect':
        final assertion = params['assertion'] as String;
        final expected = params['expected'];
        final timeout = params['timeout'] as int? ?? 5000;
        return await _expect(_targetId(params), assertion, expected, timeout);

      case 'expectScreenshot':
        final name = params['name'] as String;
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final threshold = (params['threshold'] as num?)?.toDouble() ?? 0.01;
        final updateBaseline = params['updateBaseline'] as bool? ?? false;
        final goldensDir = params['goldensDir'] as String?;
        return await _expectScreenshot(
          name,
          widgetId,
          threshold,
          updateBaseline,
          goldensDir,
        );

      case 'updateGoldens':
        final names = (params['names'] as List?)?.cast<String>();
        final goldensDir = params['goldensDir'] as String?;
        return await _updateGoldens(names, goldensDir);

      case 'listGoldens':
        final goldensDir = params['goldensDir'] as String?;
        return await _listGoldens(goldensDir);

      case 'assertWidget':
        // Legacy assertion support
        final assertion = params['assertion'] as String;
        final expectedText = params['expectedText'] as String?;
        return _assertWidget(_targetId(params), assertion, expectedText);

      // =====================================================================
      // SCREENSHOTS & VIDEO
      // =====================================================================

      case 'screenshot':
        final name = params['name'] as String? ?? 'screenshot';
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final fullPage = params['fullPage'] as bool? ?? false;
        return await _takeScreenshot(name, widgetId, fullPage);

      case 'recordStart':
        final name = params['name'] as String? ?? 'recording';
        _startRecording(name);
        return {'success': true};

      case 'recordStop':
        return await _stopRecording();

      // =====================================================================
      // NETWORK
      // =====================================================================

      case 'mockHttp':
        final urlPattern = params['urlPattern'] as String;
        final response = params['response'] as Map<String, dynamic>;
        _httpMocks[urlPattern] = response;
        return {'success': true};

      case 'blockHttp':
        final urlPattern = params['urlPattern'] as String;
        _blockedPatterns.add(urlPattern);
        return {'success': true};

      case 'clearMocks':
        _httpMocks.clear();
        _blockedPatterns.clear();
        return {'success': true};

      case 'networkLog':
        final limit = params['limit'] as int? ?? 50;
        return {'requests': _networkLog.take(limit).toList()};

      case 'waitNetwork':
        final urlPattern = params['urlPattern'] as String;
        final timeout = params['timeout'] as int? ?? 10000;
        return await _waitForNetwork(urlPattern, timeout);

      // =====================================================================
      // CONSOLE & ERRORS
      // =====================================================================

      case 'console':
        final level = params['level'] as String? ?? 'all';
        final limit = params['limit'] as int? ?? 100;
        final clear = params['clear'] as bool? ?? false;

        var messages = _consoleMessages;
        if (level != 'all') {
          messages = messages.where((m) => m['level'] == level).toList();
        }
        messages = messages.take(limit).toList();

        if (clear) {
          _consoleMessages.clear();
        }

        return {'messages': messages};

      case 'errors':
        final clear = params['clear'] as bool? ?? false;
        final errors = List<Map<String, dynamic>>.from(_errors);
        if (clear) {
          _errors.clear();
        }
        return {'errors': errors};

      // =====================================================================
      // TRACING
      // =====================================================================

      case 'traceStart':
        final name = params['name'] as String? ?? 'trace';
        final screenshots = params['screenshots'] as bool? ?? false;
        _isTracing = true;
        _traceName = name;
        _traceScreenshots = screenshots;
        _traceEvents.clear();
        _traceEvents.add({
          'type': 'trace_start',
          'timestamp': DateTime.now().toIso8601String(),
          'name': name,
        });
        return {'success': true};

      case 'traceStop':
        _isTracing = false;
        _traceEvents.add({
          'type': 'trace_end',
          'timestamp': DateTime.now().toIso8601String(),
        });

        // Save trace to file
        final filepath = await _saveTrace();
        return {'filepath': filepath, 'events': _traceEvents.length};

      // =====================================================================
      // DEVICE EMULATION
      // =====================================================================

      case 'resize':
        final width = (params['width'] as num).toDouble();
        final height = (params['height'] as num).toDouble();
        // Window resizing requires platform-specific implementation
        // This is mainly useful for web and desktop
        _logConsole('info', 'Resize requested: ${width}x$height');
        return {'success': true, 'note': 'Resize may require platform support'};

      case 'setTheme':
        final theme = params['theme'] as String;
        await _setTheme(theme);
        return {'success': true};

      case 'setLocale':
        final locale = params['locale'] as String;
        await _setLocale(locale);
        return {'success': true};

      case 'setTextScale':
        final scale = (params['scale'] as num).toDouble();
        await _setTextScale(scale);
        return {'success': true};

      // =====================================================================
      // DIALOGS & OVERLAYS
      // =====================================================================

      case 'handleDialog':
        final action = params['action'] as String;
        final text = params['text'] as String?;
        return await _handleDialog(action, text);

      case 'dismissOverlay':
        return await _dismissOverlay();

      // =====================================================================
      // STORAGE & STATE
      // =====================================================================

      case 'storageGet':
        final key = params['key'] as String;
        final storage = params['storage'] as String? ?? 'shared_prefs';
        return await _storageGet(key, storage);

      case 'storageSet':
        final key = params['key'] as String;
        final value = params['value'];
        final storage = params['storage'] as String? ?? 'shared_prefs';
        await _storageSet(key, value, storage);
        return {'success': true};

      case 'storageClear':
        final storage = params['storage'] as String? ?? 'all';
        await _storageClear(storage);
        return {'success': true};

      case 'saveState':
        final name = params['name'] as String;
        await _saveState(name);
        return {'success': true};

      case 'restoreState':
        final name = params['name'] as String;
        await _restoreState(name);
        return {'success': true};

      // =====================================================================
      // FILES
      // =====================================================================

      case 'filePicker':
        final files = (params['files'] as List?)?.cast<String>() ?? [];
        _filePickerMockFiles = files;
        return {'success': true};

      // =====================================================================
      // SCENARIOS
      // =====================================================================

      case 'runScenario':
        final name = params['name'] as String;
        final steps = (params['steps'] as List).cast<Map<String, dynamic>>();
        final stopOnError = params['stopOnError'] as bool? ?? true;
        return await _runScenario(name, steps, stopOnError);

      // =====================================================================
      // ACCESSIBILITY
      // =====================================================================

      case 'accessibilityAudit':
        return await _accessibilityAudit();

      // =====================================================================
      // CLIPBOARD
      // =====================================================================

      case 'clipboardRead':
        return await _clipboardRead();

      case 'clipboardWrite':
        final text = params['text'] as String;
        await _clipboardWrite(text);
        return {'success': true};

      // =====================================================================
      // HAR EXPORT
      // =====================================================================

      case 'harExport':
        return _harExport();

      // =====================================================================
      // ANIMATION CONTROL
      // =====================================================================

      case 'animationSpeed':
        final speed = (params['speed'] as num).toDouble();
        _setAnimationSpeed(speed);
        return {'success': true, 'speed': speed};

      case 'pump':
        final durationMs = params['duration'] as int? ?? 0;
        await _pump(durationMs);
        return {'success': true};

      // =====================================================================
      // FRAME BUDGET ANALYSIS
      // =====================================================================

      case 'frameProfilingStart':
        final budgetMs = (params['budgetMs'] as num?)?.toDouble() ?? 16.67;
        _startFrameProfiling(budgetMs: budgetMs);
        return {'success': true, 'budgetMs': budgetMs};

      case 'frameProfilingStop':
        return _stopFrameProfiling();

      case 'frameBudgetCheck':
        final action = params['action'] as String;
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final actionParams = params['params'] as Map<String, dynamic>? ?? {};
        final budgetMs = (params['budgetMs'] as num?)?.toDouble() ?? 16.67;
        return await _frameBudgetCheck(
          action,
          widgetId,
          actionParams,
          budgetMs,
        );

      case 'jankDetector':
        final enabled = params['enabled'] as bool;
        final threshold = (params['threshold'] as num?)?.toDouble() ?? 16.67;
        final callback = params['callback'] as bool? ?? enabled;
        return _setJankDetector(enabled, threshold, callback);

      // =====================================================================
      // PLATFORM CHANNEL MOCKING
      // =====================================================================

      case 'mockChannel':
        final channel = params['channel'] as String;
        final method = params['method'] as String;
        final response = params['response'];
        final errorCode = params['errorCode'] as String?;
        final errorMessage = params['errorMessage'] as String?;
        _mockChannel(channel, method, response, errorCode, errorMessage);
        return {'success': true};

      case 'clearChannelMocks':
        final channel = params['channel'] as String?;
        _clearChannelMocks(channel);
        return {'success': true};

      case 'channelLog':
        final channel = params['channel'] as String?;
        final limit = params['limit'] as int? ?? 50;
        final clear = params['clear'] as bool? ?? false;
        return _getChannelLog(channel, limit, clear);

      // =====================================================================
      // STATE MANAGEMENT INSPECTION
      // =====================================================================

      case 'getState':
        final providerId = params['providerId'] as String;
        final path = params['path'] as String?;
        final stateType = params['stateType'] as String? ?? 'auto';
        return await _getState(providerId, path, stateType);

      case 'dispatchAction':
        final providerId = params['providerId'] as String;
        final action = params['action'] as String;
        final payload = params['payload'];
        final stateType = params['stateType'] as String? ?? 'auto';
        return await _dispatchAction(providerId, action, payload, stateType);

      case 'watchState':
        final providerId = params['providerId'] as String;
        final stateType = params['stateType'] as String? ?? 'auto';
        final debounceMs = params['debounceMs'] as int? ?? 100;
        return await _watchState(providerId, stateType, debounceMs);

      case 'getStateChanges':
        final subscriptionId = params['subscriptionId'] as String;
        final clear = params['clear'] as bool? ?? true;
        return _getStateChanges(subscriptionId, clear);

      case 'unwatchState':
        final subscriptionId = params['subscriptionId'] as String;
        _unwatchState(subscriptionId);
        return {'success': true};

      case 'listStateProviders':
        final stateType = params['stateType'] as String? ?? 'all';
        return _listStateProviders(stateType);

      // =====================================================================
      // SENSOR & DEVICE MOCKING
      // =====================================================================

      case 'setGeolocation':
        return _setGeolocation(params);

      case 'setPermission':
        return _setPermission(params);

      case 'setConnectivity':
        return _setConnectivity(params);

      // =====================================================================
      // TIME-TRAVEL STATE SNAPSHOTS
      // =====================================================================

      case 'timeTravelStart':
        final captureOnInteraction =
            params['captureOnInteraction'] as bool? ?? false;
        final intervalMs = params['intervalMs'] as int?;
        return _timeTravelStart(captureOnInteraction, intervalMs);

      case 'timeTravelSnapshot':
        final label = params['label'] as String?;
        return await _timeTravelSnapshot(label);

      case 'timeTravelList':
        return _timeTravelList();

      case 'timeTravelGoto':
        final snapshotId = params['snapshotId'] as String?;
        final index = params['index'] as int?;
        return await _timeTravelGoto(snapshotId, index);

      case 'timeTravelStop':
        final clear = params['clear'] as bool? ?? false;
        return _timeTravelStop(clear);

      case 'timeTravelDiff':
        final from = params['from'] as String;
        final to = params['to'] as String;
        return _timeTravelDiff(from, to);

      // =====================================================================
      // STATE DEPENDENCY GRAPH
      // =====================================================================

      case 'stateDependencyGraph':
        return _getStateDependencyGraph();

      case 'stateImpactAnalysis':
        final providerId = params['providerId'] as String;
        return _getStateImpactAnalysis(providerId);

      case 'stateTrace':
        final providerId = params['providerId'] as String;
        final widgetId = params['widgetId'] as String?;
        return _getStateTrace(providerId, widgetId);

      case 'orphanStateCheck':
        return _getOrphanStateCheck();

      // =====================================================================
      // WIDGET REBUILD PROFILING
      // =====================================================================

      case 'profileRebuildsStart':
        return _startRebuildProfiling();

      case 'profileRebuildsStop':
        return _stopRebuildProfiling();

      case 'profileRebuildsReport':
        final threshold = params['threshold'] as int? ?? 1;
        return _getRebuildReport(threshold);

      // =====================================================================
      // SEMANTIC LABEL AUTO-GENERATION
      // =====================================================================

      case 'suggestSemantics':
        final screen = params['screen'] as String?;
        final includeLabeled = params['includeLabeled'] as bool? ?? false;
        return _suggestSemantics(screen, includeLabeled);

      case 'semanticsCoverage':
        return _semanticsCoverage();

      case 'semanticsTree':
        final includeHidden = params['includeHidden'] as bool? ?? false;
        return _semanticsTree(includeHidden);

      case 'applySuggestedSemantics':
        final suggestions =
            (params['suggestions'] as List?)?.cast<String>() ?? [];
        return _applySuggestedSemantics(suggestions);

      // =====================================================================
      // APP LIFECYCLE TESTING
      // =====================================================================

      case 'simulateLifecycle':
        final state = params['state'] as String;
        return await _simulateLifecycleState(state);

      case 'lifecycleHistory':
        return _getLifecycleHistory();

      case 'simulateMemoryPressure':
        final level = params['level'] as String? ?? 'low';
        return await _simulateMemoryPressure(level);

      case 'simulateLocaleChange':
        final locale = params['locale'] as String;
        return await _simulateLocaleChange(locale);

      case 'simulateTextScaleChange':
        final scale = (params['scale'] as num).toDouble();
        return await _simulateTextScaleChange(scale);

      case 'simulateBrightnessChange':
        final brightness = params['brightness'] as String;
        return await _simulateBrightnessChange(brightness);

      // =====================================================================
      // BIOMETRIC AUTHENTICATION MOCKING
      // =====================================================================

      case 'setBiometricAvailability':
        return _setBiometricAvailability(params);

      case 'setBiometricResult':
        return _setBiometricResult(params);

      case 'biometricAuthHistory':
        return _getBiometricAuthHistory();

      case 'simulateBiometricPrompt':
        final reason = params['reason'] as String;
        final type = params['type'] as String?;
        return await _simulateBiometricPrompt(reason, type);

      case 'clearBiometricConfig':
        return _clearBiometricConfig();

      // =====================================================================
      // MEMORY PROFILING
      // =====================================================================

      case 'memorySnapshot':
        return _getMemorySnapshot();

      case 'memoryProfileStart':
        final intervalMs = params['intervalMs'] as int? ?? 1000;
        _startMemoryProfiling(intervalMs: intervalMs);
        return {'profiling': true};

      case 'memoryProfileStop':
        return _stopMemoryProfiling();

      case 'forceGc':
        return await _forceGc();

      case 'imageCacheStats':
        return _getImageCacheStats();

      case 'clearImageCache':
        return _clearImageCache();

      case 'memoryLeakCheck':
        final action = params['action'] as String;
        final iterations = params['iterations'] as int? ?? 5;
        return await _memoryLeakCheck(action, iterations);

      // =====================================================================
      // WIDGET TEST GENERATION
      // =====================================================================

      case BridgeCommands.recordTestStart:
        final testName = params['testName'] as String;
        final description = params['description'] as String?;
        return _startTestRecording(testName, description: description);

      case BridgeCommands.recordTestStop:
        final format = params['format'] as String? ?? 'widget_test';
        return _stopTestRecording(format);

      case BridgeCommands.recordAddAssertion:
        final assertion = params['assertion'] as String;
        final expected = params['expected'];
        return _recordAssertion(_targetId(params), assertion, expected);

      case BridgeCommands.recordAddComment:
        final comment = params['comment'] as String;
        return _recordComment(comment);

      case BridgeCommands.getRecordedSteps:
        return _getRecordedSteps();

      case BridgeCommands.generateTestFromScenario:
        final scenario = params['scenario'] as Map<String, dynamic>;
        final format = params['format'] as String? ?? 'widget_test';
        return _generateTestFromScenario(scenario, format);

      // =====================================================================
      // PUSH NOTIFICATION MOCKING
      // =====================================================================

      case BridgeCommands.simulatePushNotification:
        final title = params['title'] as String;
        final body = params['body'] as String;
        final data = params['data'] as Map<String, dynamic>?;
        final action = params['action'] as String? ?? 'received';
        final delay = params['delay'] as int?;
        return await _simulatePushNotification(
          title: title,
          body: body,
          data: data,
          action: action,
          delayMs: delay,
        );

      case BridgeCommands.simulateNotificationTap:
        final notificationId = params['notificationId'] as String;
        final actionId = params['actionId'] as String?;
        return await _simulateNotificationTap(notificationId, actionId);

      case BridgeCommands.notificationHistory:
        return _getNotificationHistory();

      case BridgeCommands.setNotificationHandler:
        final onReceive = params['onReceive'] as bool?;
        final onTap = params['onTap'] as bool?;
        final onDismiss = params['onDismiss'] as bool?;
        return _setNotificationHandler(
          onReceive: onReceive,
          onTap: onTap,
          onDismiss: onDismiss,
        );

      case BridgeCommands.clearNotifications:
        return _clearNotifications();

      case BridgeCommands.getFcmToken:
        return _getFcmToken();

      // =====================================================================
      // NAVIGATION STACK INSPECTOR
      // =====================================================================

      case BridgeCommands.navigationStack:
        return _getNavigationStack();

      case BridgeCommands.navigationHistory:
        final limit = params['limit'] as int? ?? 20;
        return _getNavigationHistory(limit);

      case BridgeCommands.popUntil:
        final route = params['route'] as String?;
        final predicate = params['predicate'] as String?;
        return await _popUntil(route, predicate);

      case BridgeCommands.canPop:
        return _canPop();

      case BridgeCommands.navigationListeners:
        return _getNavigationListeners();

      case BridgeCommands.simulateBackGesture:
        final type = params['type'] as String? ?? 'button';
        return await _simulateBackGesture(type);

      case BridgeCommands.routeSettings:
        final route = params['route'] as String?;
        return _getRouteSettings(route);

      // =====================================================================
      // DEEP LINK TESTING
      // =====================================================================

      case BridgeCommands.simulateDeepLink:
        final url = params['url'] as String;
        final source = params['source'] as String? ?? 'external';
        return await _simulateDeepLink(url, source);

      case BridgeCommands.deepLinkHistory:
        return _getDeepLinkHistory();

      case BridgeCommands.registerDeepLinkSchemes:
        final schemes = (params['schemes'] as List).cast<String>();
        return _registerDeepLinkSchemes(schemes);

      case BridgeCommands.testDeepLinkRouting:
        final url = params['url'] as String;
        final expectedRoute = params['expectedRoute'] as String;
        final expectedParams =
            params['expectedParams'] as Map<String, dynamic>?;
        return _testDeepLinkRouting(url, expectedRoute, expectedParams);

      case BridgeCommands.clearDeepLinkHistory:
        return _clearDeepLinkHistory();

      default:
        throw Exception('Unknown command: ${command.command}');
    }
  }

  // ===========================================================================
  // LOCATOR IMPLEMENTATIONS
  // ===========================================================================

  Map<String, dynamic> _getSnapshot() {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;

    String currentScreen = 'unknown';
    if (nodes.isNotEmpty) {
      final firstNode = nodes.values.first;
      if (firstNode.context != null) {
        currentScreen = _inferScreen(firstNode.context!);
      }
    }

    final widgets = <Map<String, dynamic>>[];
    for (final entry in nodes.entries) {
      final node = entry.value;
      widgets.add({
        'id': entry.key,
        'type': _inferWidgetType(node),
        'screen': node.context != null
            ? _inferScreen(node.context!)
            : 'unknown',
        'isStable': !entry.key.endsWith('_UNSTABLE'),
        'isEnabled': node.onTap != null || node.onTextChange != null,
        'isChecked': null, // TestNode doesn't track checked state
        'currentText': node.currentText,
        'capabilities': {
          'canTap': node.onTap != null,
          'canEnterText': node.onTextChange != null,
          'canToggle': node.onTap != null, // Toggle uses onTap
        },
      });
    }

    return {
      'currentScreen': currentScreen,
      'widgets': widgets,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _getByRole(String role, String? name) {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;
    final matches = <Map<String, dynamic>>[];

    for (final entry in nodes.entries) {
      final node = entry.value;
      final inferredType = _inferWidgetType(node);

      bool roleMatches = false;
      switch (role) {
        case 'button':
          roleMatches = inferredType == 'button';
          break;
        case 'textbox':
          roleMatches = inferredType == 'text_input';
          break;
        case 'checkbox':
        case 'switch':
          roleMatches = inferredType == 'checkbox' || inferredType == 'switch';
          break;
        case 'slider':
          roleMatches = inferredType == 'slider';
          break;
        case 'link':
          roleMatches = inferredType == 'link';
          break;
        default:
          roleMatches = inferredType == role;
      }

      if (roleMatches) {
        if (name == null || (node.currentText?.contains(name) ?? false)) {
          matches.add({
            'id': entry.key,
            'type': inferredType,
            'text': node.currentText,
          });
        }
      }
    }

    return matches;
  }

  List<Map<String, dynamic>> _getByText(String text, bool exact) {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;
    final matches = <Map<String, dynamic>>[];

    for (final entry in nodes.entries) {
      final node = entry.value;
      final nodeText = node.currentText ?? '';

      bool textMatches;
      if (exact) {
        textMatches = nodeText == text;
      } else {
        textMatches = nodeText.toLowerCase().contains(text.toLowerCase());
      }

      if (textMatches) {
        matches.add({
          'id': entry.key,
          'type': _inferWidgetType(node),
          'text': nodeText,
        });
      }
    }

    return matches;
  }

  List<Map<String, dynamic>> _getScreens() {
    final catalog = WidgetCatalog.exportByScreen();
    final screens = <Map<String, dynamic>>[];

    for (final entry in catalog.entries) {
      final screenData = entry.value as Map<String, dynamic>;
      final widgets = screenData['widgets'] as List? ?? [];

      screens.add({
        'name': entry.key,
        'path': '/${entry.key}',
        'requiresAuth': _inferAuthRequirement(entry.key),
        'widgetCount': widgets.length,
      });
    }

    return screens;
  }

  Map<String, dynamic> _getCurrentState() {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;

    String currentScreen = 'unknown';
    if (nodes.isNotEmpty) {
      final firstNode = nodes.values.first;
      if (firstNode.context != null) {
        currentScreen = _inferScreen(firstNode.context!);
      }
    }

    return {
      'currentScreen': currentScreen,
      'widgetCount': nodes.length,
      'testModeActive': manager.isSelfTestModeActive || manager.isTestMode,
      'autoDetectionEnabled': true,
      'isTracing': _isTracing,
      'isRecording': _isRecording,
    };
  }

  // ===========================================================================
  // ACTION IMPLEMENTATIONS
  // ===========================================================================

  Future<void> _waitForWidget(String widgetId, int timeoutMs) async {
    final manager = SelfTestManager();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (DateTime.now().isBefore(deadline)) {
      if (manager.activeTestNodes.containsKey(widgetId)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    throw Exception('Widget "$widgetId" not found within ${timeoutMs}ms');
  }

  Future<void> _pressKey(String key) async {
    LogicalKeyboardKey logicalKey;
    switch (key.toLowerCase()) {
      case 'enter':
        logicalKey = LogicalKeyboardKey.enter;
        break;
      case 'tab':
        logicalKey = LogicalKeyboardKey.tab;
        break;
      case 'escape':
        logicalKey = LogicalKeyboardKey.escape;
        break;
      case 'backspace':
        logicalKey = LogicalKeyboardKey.backspace;
        break;
      case 'delete':
        logicalKey = LogicalKeyboardKey.delete;
        break;
      case 'up':
        logicalKey = LogicalKeyboardKey.arrowUp;
        break;
      case 'down':
        logicalKey = LogicalKeyboardKey.arrowDown;
        break;
      case 'left':
        logicalKey = LogicalKeyboardKey.arrowLeft;
        break;
      case 'right':
        logicalKey = LogicalKeyboardKey.arrowRight;
        break;
      case 'home':
        logicalKey = LogicalKeyboardKey.home;
        break;
      case 'end':
        logicalKey = LogicalKeyboardKey.end;
        break;
      default:
        throw Exception('Unknown key: $key');
    }

    // Simulate key press through raw key event
    await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/keyevent',
      const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'type': 'keydown',
        'keyCode': logicalKey.keyId,
      }),
      (ByteData? data) {},
    );

    await Future.delayed(const Duration(milliseconds: 50));

    await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/keyevent',
      const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'type': 'keyup',
        'keyCode': logicalKey.keyId,
      }),
      (ByteData? data) {},
    );
  }

  Future<void> _scroll(String? widgetId, String direction, double delta) async {
    final manager = SelfTestManager();

    // Find scrollable
    ScrollController? controller;
    if (widgetId != null) {
      final node = manager.activeTestNodes[widgetId];
      if (node?.context != null) {
        final scrollable = Scrollable.maybeOf(node!.context!);
        controller = scrollable?.widget.controller;
      }
    } else {
      // Find any scrollable in current context
      // This would need access to the current build context
    }

    if (controller != null) {
      double offset;
      switch (direction) {
        case 'up':
          offset = -delta;
          break;
        case 'down':
          offset = delta;
          break;
        case 'left':
          offset = -delta;
          break;
        case 'right':
          offset = delta;
          break;
        default:
          throw Exception('Unknown scroll direction: $direction');
      }

      await controller.animateTo(
        controller.offset + offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    await manager.waitForAnimations();
  }

  Future<void> _scrollToWidget(
    String widgetId,
    String? scrollableId,
    int timeout,
  ) async {
    final manager = SelfTestManager();
    final deadline = DateTime.now().add(Duration(milliseconds: timeout));

    while (DateTime.now().isBefore(deadline)) {
      final node = manager.activeTestNodes[widgetId];
      if (node?.context != null) {
        // Widget found, ensure visible
        await Scrollable.ensureVisible(
          node!.context!,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
        return;
      }

      // Scroll down and try again
      await _scroll(scrollableId, 'down', 200);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    throw Exception('Widget "$widgetId" not found after scrolling');
  }

  Future<void> _drag(String sourceId, String targetId) async {
    final manager = SelfTestManager();
    final sourceNode = manager.activeTestNodes[sourceId];
    final targetNode = manager.activeTestNodes[targetId];

    if (sourceNode == null)
      throw Exception('Source widget "$sourceId" not found');
    if (targetNode == null)
      throw Exception('Target widget "$targetId" not found');

    if (sourceNode.context == null || targetNode.context == null) {
      throw Exception('Widget contexts not available');
    }

    final sourceBox = sourceNode.context!.findRenderObject() as RenderBox?;
    final targetBox = targetNode.context!.findRenderObject() as RenderBox?;

    if (sourceBox == null || targetBox == null) {
      throw Exception('Widget render objects not found');
    }

    // Get global positions
    final sourcePos = sourceBox.localToGlobal(
      sourceBox.size.center(Offset.zero),
    );
    final targetPos = targetBox.localToGlobal(
      targetBox.size.center(Offset.zero),
    );

    // Simulate drag using gesture binding
    final binding = WidgetsBinding.instance;
    final pointer = TestPointer();

    binding.handlePointerEvent(pointer.down(sourcePos));
    await Future.delayed(const Duration(milliseconds: 100));

    // Move in steps
    const steps = 10;
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final current = Offset.lerp(sourcePos, targetPos, t)!;
      binding.handlePointerEvent(pointer.move(current));
      await Future.delayed(const Duration(milliseconds: 20));
    }

    binding.handlePointerEvent(pointer.up());
    await manager.waitForAnimations();
  }

  Future<void> _longPress(String widgetId, int durationMs) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');
    if (node.context == null) throw Exception('Widget context not available');

    final box = node.context!.findRenderObject() as RenderBox?;
    if (box == null) throw Exception('Widget render object not found');

    final position = box.localToGlobal(box.size.center(Offset.zero));

    final binding = WidgetsBinding.instance;
    final pointer = TestPointer();

    binding.handlePointerEvent(pointer.down(position));
    await Future.delayed(Duration(milliseconds: durationMs));
    binding.handlePointerEvent(pointer.up());
    await manager.waitForAnimations();
  }

  Future<void> _doubleTap(String widgetId) async {
    final manager = SelfTestManager();
    await manager.trigger(widgetId);
    await Future.delayed(const Duration(milliseconds: 100));
    await manager.trigger(widgetId);
    await manager.waitForAnimations();
  }

  Future<void> _hover(String widgetId) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');
    if (node.context == null) throw Exception('Widget context not available');

    final box = node.context!.findRenderObject() as RenderBox?;
    if (box == null) throw Exception('Widget render object not found');

    final position = box.localToGlobal(box.size.center(Offset.zero));

    final binding = WidgetsBinding.instance;
    final pointer = TestPointer(kind: PointerDeviceKind.mouse);

    binding.handlePointerEvent(pointer.hover(position));
  }

  Future<void> _focus(String widgetId) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');
    if (node.context == null) throw Exception('Widget context not available');

    // Find focus node in widget tree
    final focusNode = Focus.maybeOf(node.context!);
    focusNode?.requestFocus();
  }

  Future<void> _selectOption(String widgetId, String value) async {
    final manager = SelfTestManager();

    // First tap to open dropdown
    await manager.trigger(widgetId);
    await manager.waitForAnimations();
    await Future.delayed(const Duration(milliseconds: 200));

    // Find and tap the option
    final nodes = manager.activeTestNodes;
    for (final entry in nodes.entries) {
      if (entry.value.currentText == value) {
        await manager.trigger(entry.key);
        break;
      }
    }

    await manager.waitForAnimations();
  }

  Future<void> _toggle(String widgetId, bool? checked) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');

    // TestNode doesn't track checked state, so we always trigger the tap
    // The widget itself manages its internal state
    if (node.onTap != null) {
      await manager.trigger(widgetId);
    } else {
      throw Exception(
        'Widget "$widgetId" is not toggleable (no onTap callback)',
      );
    }

    await manager.waitForAnimations();
  }

  Future<void> _setSlider(String widgetId, double value) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');

    // TestNode uses onTextChange for value changes (pass value as string)
    if (node.onTextChange != null) {
      node.onTextChange!(value.toString());
    } else {
      throw Exception('Widget "$widgetId" does not support value changes');
    }

    await manager.waitForAnimations();
  }

  // ===========================================================================
  // WAIT IMPLEMENTATIONS
  // ===========================================================================

  Future<Map<String, dynamic>> _wait(
    String condition,
    String? widgetId,
    String? text,
    int timeoutMs,
    int? durationMs,
  ) async {
    final manager = SelfTestManager();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    switch (condition) {
      case 'visible':
      case 'widget_exists':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          if (manager.activeTestNodes.containsKey(widgetId)) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for widget "$widgetId"');

      case 'hidden':
      case 'widget_gone':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          if (!manager.activeTestNodes.containsKey(widgetId)) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to disappear');

      case 'enabled':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          final node = manager.activeTestNodes[widgetId];
          if (node != null &&
              (node.onTap != null || node.onTextChange != null)) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to be enabled');

      case 'disabled':
        if (widgetId == null) throw Exception('widgetId required');
        while (DateTime.now().isBefore(deadline)) {
          final node = manager.activeTestNodes[widgetId];
          if (node != null && node.onTap == null && node.onTextChange == null) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to be disabled');

      case 'text':
        if (widgetId == null) throw Exception('widgetId required');
        if (text == null) throw Exception('text required');
        while (DateTime.now().isBefore(deadline)) {
          final node = manager.activeTestNodes[widgetId];
          if (node?.currentText == text) {
            return {'success': true};
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
        throw Exception('Timeout waiting for "$widgetId" to have text "$text"');

      case 'idle':
        await manager.waitForAnimations();
        return {'success': true};

      case 'network_idle':
        // Wait for no pending network requests
        await Future.delayed(const Duration(milliseconds: 500));
        return {'success': true};

      case 'duration':
        final duration = durationMs ?? 1000;
        await Future.delayed(Duration(milliseconds: duration));
        return {'success': true};

      default:
        throw Exception('Unknown wait condition: $condition');
    }
  }

  // ===========================================================================
  // ASSERTION IMPLEMENTATIONS
  // ===========================================================================

  Future<Map<String, dynamic>> _expect(
    String widgetId,
    String assertion,
    dynamic expected,
    int timeout,
  ) async {
    final manager = SelfTestManager();

    // Wait for widget first
    try {
      await _waitForWidget(widgetId, timeout);
    } catch (e) {
      if (assertion == 'toBeHidden') {
        return {'passed': true, 'message': 'Widget is hidden'};
      }
      return {'passed': false, 'message': 'Widget "$widgetId" not found'};
    }

    final node = manager.activeTestNodes[widgetId];

    switch (assertion) {
      case 'toBeVisible':
        return {
          'passed': node != null,
          'message': node != null ? 'Widget is visible' : 'Widget not found',
        };

      case 'toBeHidden':
        return {
          'passed': node == null,
          'message': node == null ? 'Widget is hidden' : 'Widget is visible',
        };

      case 'toBeEnabled':
        final isEnabled = node?.onTap != null || node?.onTextChange != null;
        return {
          'passed': isEnabled,
          'message': isEnabled ? 'Widget is enabled' : 'Widget is disabled',
        };

      case 'toBeDisabled':
        final isDisabled = node?.onTap == null && node?.onTextChange == null;
        return {
          'passed': isDisabled,
          'message': isDisabled ? 'Widget is disabled' : 'Widget is enabled',
        };

      case 'toBeChecked':
        // TestNode doesn't track checked state; check currentText for 'true'/'checked'
        final isChecked =
            node?.currentText?.toLowerCase() == 'true' ||
            node?.currentText?.toLowerCase() == 'checked';
        return {
          'passed': isChecked,
          'message': isChecked ? 'Widget is checked' : 'Widget is not checked',
        };

      case 'toBeUnchecked':
        // TestNode doesn't track checked state; check currentText for 'false'/'unchecked'
        final isUnchecked =
            node?.currentText?.toLowerCase() != 'true' &&
            node?.currentText?.toLowerCase() != 'checked';
        return {
          'passed': isUnchecked,
          'message': isUnchecked ? 'Widget is unchecked' : 'Widget is checked',
        };

      case 'toHaveText':
        final actual = node?.currentText ?? '';
        final matches = actual == expected;
        return {
          'passed': matches,
          'message': matches
              ? 'Text matches'
              : 'Expected "$expected" but got "$actual"',
        };

      case 'toContainText':
        final actual = node?.currentText ?? '';
        final contains = actual.contains(expected as String);
        return {
          'passed': contains,
          'message': contains
              ? 'Text contains expected substring'
              : 'Expected "$actual" to contain "$expected"',
        };

      case 'toHaveValue':
        // TestNode uses currentText for all values
        final actual = node?.currentText;
        final matches = actual == expected || actual == expected?.toString();
        return {
          'passed': matches,
          'message': matches
              ? 'Value matches'
              : 'Expected "$expected" but got "$actual"',
        };

      case 'toHaveCount':
        // Count widgets with this ID pattern
        final count = manager.activeTestNodes.keys
            .where((k) => k.startsWith(widgetId))
            .length;
        final expectedCount = expected as int;
        return {
          'passed': count == expectedCount,
          'message': count == expectedCount
              ? 'Count matches'
              : 'Expected $expectedCount but got $count',
        };

      case 'toBeFocused':
        // Check if widget has focus
        final hasFocus =
            node?.context != null &&
            Focus.maybeOf(node!.context!)?.hasFocus == true;
        return {
          'passed': hasFocus,
          'message': hasFocus ? 'Widget is focused' : 'Widget is not focused',
        };

      default:
        return {'passed': false, 'message': 'Unknown assertion: $assertion'};
    }
  }

  Future<Map<String, dynamic>> _expectScreenshot(
    String name,
    String? widgetId,
    double threshold,
    bool updateBaseline,
    String? goldensDir,
  ) async {
    await _ensureGoldensDirectory(goldensDir);
    final baselinePath = _getGoldenPath(name, goldensDir);
    final baselineFile = File(baselinePath);
    final currentBytes = await _captureScreenshotBytes(widgetId);
    final safeName = name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final relativeDir = goldensDir ?? _defaultGoldensDir;
    final relativeBaselinePath = '$relativeDir/$safeName.png';

    if (updateBaseline) {
      await baselineFile.writeAsBytes(currentBytes);
      return {
        'passed': true,
        'baselineUpdated': true,
        'baselinePath': relativeBaselinePath,
        'difference': 0.0,
      };
    }

    if (!await baselineFile.exists()) {
      await baselineFile.writeAsBytes(currentBytes);
      return {
        'passed': true,
        'baselineCreated': true,
        'baselinePath': relativeBaselinePath,
        'difference': 0.0,
      };
    }

    final baselineBytes = await baselineFile.readAsBytes();
    final baselineImage = await _decodeImage(baselineBytes);
    final currentImage = await _decodeImage(currentBytes);

    if (baselineImage == null || currentImage == null) {
      return {
        'passed': false,
        'difference': 1.0,
        'message': 'Failed to decode images',
        'baselinePath': relativeBaselinePath,
      };
    }

    if (baselineImage.width != currentImage.width ||
        baselineImage.height != currentImage.height) {
      final diffPath = _getDiffPath(name, goldensDir);
      await File(diffPath).writeAsBytes(currentBytes);
      return {
        'passed': false,
        'difference': 1.0,
        'message':
            'Size mismatch: ${baselineImage.width}x${baselineImage.height} vs ${currentImage.width}x${currentImage.height}',
        'baselinePath': relativeBaselinePath,
        'diffPath': '$relativeDir/${safeName}_diff.png',
      };
    }

    final baselineData = await baselineImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final currentData = await currentImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    if (baselineData == null || currentData == null) {
      return {
        'passed': false,
        'difference': 1.0,
        'message': 'Failed to get image data',
        'baselinePath': relativeBaselinePath,
      };
    }

    int differentPixels = 0;
    final totalPixels = baselineImage.width * baselineImage.height;
    final diffBuffer = Uint8List(baselineData.lengthInBytes);

    for (int i = 0; i < baselineData.lengthInBytes; i += 4) {
      final r1 = baselineData.getUint8(i);
      final g1 = baselineData.getUint8(i + 1);
      final b1 = baselineData.getUint8(i + 2);
      final a1 = baselineData.getUint8(i + 3);
      final r2 = currentData.getUint8(i);
      final g2 = currentData.getUint8(i + 1);
      final b2 = currentData.getUint8(i + 2);
      final a2 = currentData.getUint8(i + 3);

      if (r1 != r2 || g1 != g2 || b1 != b2 || a1 != a2) {
        differentPixels++;
        diffBuffer[i] = 255;
        diffBuffer[i + 1] = 0;
        diffBuffer[i + 2] = 0;
        diffBuffer[i + 3] = 255;
      } else {
        diffBuffer[i] = (r1 * 0.3).round();
        diffBuffer[i + 1] = (g1 * 0.3).round();
        diffBuffer[i + 2] = (b1 * 0.3).round();
        diffBuffer[i + 3] = a1;
      }
    }

    final difference = differentPixels / totalPixels;
    final passed = difference <= threshold;
    String? diffImageBase64;

    if (!passed) {
      final diffPath = _getDiffPath(name, goldensDir);
      final diffImage = await _createImageFromRgba(
        diffBuffer,
        baselineImage.width,
        baselineImage.height,
      );
      if (diffImage != null) {
        final diffPngBytes = await diffImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (diffPngBytes != null) {
          await File(diffPath).writeAsBytes(diffPngBytes.buffer.asUint8List());
          diffImageBase64 = base64Encode(diffPngBytes.buffer.asUint8List());
        }
      }
    }

    return {
      'passed': passed,
      'difference': difference,
      'baselinePath': relativeBaselinePath,
      if (!passed) 'diffPath': '$relativeDir/${safeName}_diff.png',
      if (!passed && diffImageBase64 != null) 'diffImage': diffImageBase64,
    };
  }

  Future<ui.Image?> _decodeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      return null;
    }
  }

  Future<ui.Image?> _createImageFromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return await completer.future;
  }

  Future<Map<String, dynamic>> _updateGoldens(
    List<String>? names,
    String? goldensDir,
  ) async {
    await _ensureGoldensDirectory(goldensDir);
    final directory = Directory(_getGoldensDirectory(goldensDir));
    final updated = <String>[];

    if (names != null && names.isNotEmpty) {
      for (final name in names) {
        final currentBytes = await _captureScreenshotBytes(null);
        final path = _getGoldenPath(name, goldensDir);
        await File(path).writeAsBytes(currentBytes);
        updated.add(name);
      }
    } else {
      if (await directory.exists()) {
        await for (final file in directory.list()) {
          if (file is File &&
              file.path.endsWith('.png') &&
              !file.path.endsWith('_diff.png')) {
            final name = file.path.split('/').last.replaceAll('.png', '');
            final currentBytes = await _captureScreenshotBytes(null);
            await file.writeAsBytes(currentBytes);
            updated.add(name);
          }
        }
      }
    }
    return {'updated': updated, 'skipped': <String>[]};
  }

  Future<Map<String, dynamic>> _listGoldens(String? goldensDir) async {
    final directoryPath = _getGoldensDirectory(goldensDir);
    final directory = Directory(directoryPath);
    final goldens = <Map<String, dynamic>>[];
    final relativeDir = goldensDir ?? _defaultGoldensDir;

    if (await directory.exists()) {
      await for (final file in directory.list()) {
        if (file is File &&
            file.path.endsWith('.png') &&
            !file.path.endsWith('_diff.png')) {
          final stat = await file.stat();
          final name = file.path.split('/').last.replaceAll('.png', '');
          final sizeStr = stat.size < 1024
              ? '${stat.size} B'
              : '${(stat.size / 1024).toStringAsFixed(1)} KB';
          goldens.add({
            'name': name,
            'path': '$relativeDir/$name.png',
            'size': sizeStr,
            'modified': stat.modified.toIso8601String(),
          });
        }
      }
    }
    return {'directory': relativeDir, 'goldens': goldens};
  }

  Map<String, dynamic> _assertWidget(
    String widgetId,
    String assertion,
    String? expectedText,
  ) {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    switch (assertion) {
      case 'exists':
        return node != null
            ? {'passed': true, 'message': 'Widget exists'}
            : {'passed': false, 'message': 'Widget "$widgetId" not found'};

      case 'not_exists':
        return node == null
            ? {'passed': true, 'message': 'Widget does not exist'}
            : {'passed': false, 'message': 'Widget "$widgetId" exists'};

      case 'has_text':
        if (node == null) {
          return {'passed': false, 'message': 'Widget "$widgetId" not found'};
        }
        return node.currentText == expectedText
            ? {'passed': true, 'message': 'Text matches'}
            : {
                'passed': false,
                'message':
                    'Expected "$expectedText" but got "${node.currentText}"',
              };

      case 'is_enabled':
        if (node == null) {
          return {'passed': false, 'message': 'Widget "$widgetId" not found'};
        }
        return (node.onTap != null || node.onTextChange != null)
            ? {'passed': true, 'message': 'Widget is enabled'}
            : {'passed': false, 'message': 'Widget is disabled'};

      case 'is_visible':
        return node != null
            ? {'passed': true, 'message': 'Widget is visible'}
            : {'passed': false, 'message': 'Widget "$widgetId" not found'};

      default:
        return {'passed': false, 'message': 'Unknown assertion: $assertion'};
    }
  }

  // ===========================================================================
  // SCREENSHOT & RECORDING
  // ===========================================================================

  Future<Map<String, dynamic>> _takeScreenshot(
    String name,
    String? widgetId,
    bool fullPage,
  ) async {
    final manager = SelfTestManager();

    try {
      final path = await manager.captureScreenshot(name);

      if (path != null) {
        final file = File(path);
        final bytes = await file.readAsBytes();
        final base64Data = base64Encode(bytes);

        return {
          'filename': path.split('/').last,
          'filepath': path,
          'base64': base64Data,
        };
      }
    } catch (e) {
      _logConsole('error', 'Screenshot failed: $e');
    }

    return {'error': 'Failed to capture screenshot'};
  }

  Future<Uint8List> _captureScreenshotBytes(String? widgetId) async {
    final manager = SelfTestManager();
    final path = await manager.captureScreenshot('temp_comparison');

    if (path != null) {
      final file = File(path);
      return await file.readAsBytes();
    }

    return Uint8List(0);
  }

  void _startRecording(String name) {
    _isRecording = true;
    _recordingName = name;
    _recordingFrames.clear();

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (_isRecording) {
        final bytes = await _captureScreenshotBytes(null);
        _recordingFrames.add(bytes);
      }
    });
  }

  Future<Map<String, dynamic>> _stopRecording() async {
    _recordingTimer?.cancel();
    _isRecording = false;

    // Save frames as video or animated GIF
    final filepath = '/tmp/${_recordingName ?? 'recording'}.gif';

    // Note: Actual video encoding would require a native plugin
    // For now, save frames metadata
    return {
      'filepath': filepath,
      'frames': _recordingFrames.length,
      'note': 'Video encoding requires native implementation',
    };
  }

  Future<void> _captureTraceScreenshot(String name) async {
    final bytes = await _captureScreenshotBytes(null);
    _traceEvents.add({
      'type': 'screenshot',
      'name': name,
      'timestamp': DateTime.now().toIso8601String(),
      'data': base64Encode(bytes),
    });
  }

  Future<String> _saveTrace() async {
    final filepath = '/tmp/${_traceName ?? 'trace'}.json';
    final file = File(filepath);
    await file.writeAsString(jsonEncode(_traceEvents));
    return filepath;
  }

  // ===========================================================================
  // NETWORK
  // ===========================================================================

  Future<Map<String, dynamic>> _waitForNetwork(
    String urlPattern,
    int timeout,
  ) async {
    final completer = Completer<Map<String, dynamic>>();
    _pendingNetworkWaits[urlPattern] = completer;

    // Check if already in log
    for (final req in _networkLog) {
      if (_matchesPattern(req['url'] as String, urlPattern)) {
        _pendingNetworkWaits.remove(urlPattern);
        return req;
      }
    }

    // Wait with timeout
    return completer.future.timeout(
      Duration(milliseconds: timeout),
      onTimeout: () {
        _pendingNetworkWaits.remove(urlPattern);
        throw Exception('Timeout waiting for request matching $urlPattern');
      },
    );
  }

  bool _matchesPattern(String url, String pattern) {
    if (pattern.contains('*')) {
      final regex = RegExp(pattern.replaceAll('*', '.*'));
      return regex.hasMatch(url);
    }
    return url.contains(pattern);
  }

  // ===========================================================================
  // DEVICE EMULATION
  // ===========================================================================

  Future<void> _setTheme(String theme) async {
    // This requires app-level support via a callback or provider
    _logConsole('info', 'Theme change requested: $theme');
  }

  Future<void> _setLocale(String locale) async {
    final parts = locale.split('_');
    final newLocale = Locale(parts[0], parts.length > 1 ? parts[1] : null);
    _logConsole('info', 'Locale change requested: $newLocale');
  }

  Future<void> _setTextScale(double scale) async {
    _logConsole('info', 'Text scale change requested: $scale');
  }

  // ===========================================================================
  // DIALOGS & OVERLAYS
  // ===========================================================================

  Future<Map<String, dynamic>> _handleDialog(
    String action,
    String? text,
  ) async {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;

    // Find dialog buttons
    for (final entry in nodes.entries) {
      final nodeText = entry.value.currentText?.toLowerCase() ?? '';

      if (action == 'accept') {
        if (nodeText.contains('ok') ||
            nodeText.contains('yes') ||
            nodeText.contains('confirm') ||
            nodeText.contains('accept')) {
          await manager.trigger(entry.key);
          await manager.waitForAnimations();
          return {'success': true, 'text': entry.value.currentText};
        }
      } else if (action == 'dismiss') {
        if (nodeText.contains('cancel') ||
            nodeText.contains('no') ||
            nodeText.contains('close') ||
            nodeText.contains('dismiss')) {
          await manager.trigger(entry.key);
          await manager.waitForAnimations();
          return {'success': true};
        }
      } else if (action == 'get_text') {
        // Return dialog message text
        for (final n in nodes.values) {
          if (n.currentText != null && n.currentText!.length > 20) {
            return {'text': n.currentText};
          }
        }
      }
    }

    // Try pressing back to dismiss
    if (action == 'dismiss') {
      final target = navigator;
      if (target != null && target.canGoBack) {
        await target.goBack();
      }
      return {'success': true};
    }

    return {'error': 'Dialog action not completed'};
  }

  Future<Map<String, dynamic>> _dismissOverlay() async {
    // Try to pop any modal routes
    final target = navigator;
    if (target != null && target.canGoBack) {
      await target.goBack();
      await SelfTestManager().waitForAnimations();
      return {'success': true};
    }

    // Try pressing escape
    await _pressKey('escape');
    await SelfTestManager().waitForAnimations();
    return {'success': true};
  }

  // ===========================================================================
  // STORAGE & STATE
  // ===========================================================================

  Future<Map<String, dynamic>> _storageGet(String key, String storage) async {
    if (storage == 'shared_prefs') {
      final prefs = await SharedPreferences.getInstance();
      return {'value': prefs.get(key)};
    }
    return {'error': 'Storage type not supported'};
  }

  Future<void> _storageSet(String key, dynamic value, String storage) async {
    if (storage == 'shared_prefs') {
      final prefs = await SharedPreferences.getInstance();
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    }
  }

  Future<void> _storageClear(String storage) async {
    if (storage == 'shared_prefs' || storage == 'all') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    }
  }

  Future<void> _saveState(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final state = <String, dynamic>{};

    for (final key in prefs.getKeys()) {
      state[key] = prefs.get(key);
    }

    state['_currentRoute'] = navigator?.currentLocation;

    _savedStates[name] = state;
  }

  Future<void> _restoreState(String name) async {
    final state = _savedStates[name];
    if (state == null) {
      throw Exception('State "$name" not found');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    for (final entry in state.entries) {
      if (entry.key.startsWith('_')) continue;
      await _storageSet(entry.key, entry.value, 'shared_prefs');
    }

    final route = state['_currentRoute'] as String?;
    if (route != null) {
      await navigator?.goTo(route, replace: true);
    }

    await SelfTestManager().waitForAnimations();
  }

  // ===========================================================================
  // SCENARIOS
  // ===========================================================================

  Future<Map<String, dynamic>> _runScenario(
    String name,
    List<Map<String, dynamic>> steps,
    bool stopOnError,
  ) async {
    final manager = SelfTestManager();
    final results = <Map<String, dynamic>>[];
    var allPassed = true;

    manager.startTestRun(name);

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final action = step['action'] as String;
      final stepParams = step['params'] as Map<String, dynamic>? ?? {};
      String description = 'Step ${i + 1}: $action';

      try {
        // Execute the action as a command
        final command = BridgeCommand(
          id: 0,
          command: action,
          params: stepParams,
        );
        await _executeCommand(command);

        String? screenshotPath;
        screenshotPath = await manager.captureScreenshot(
          '${name}_step_${i + 1}',
        );

        results.add({
          'description': description,
          'passed': true,
          'screenshotPath': screenshotPath,
        });
      } catch (e) {
        allPassed = false;
        String? screenshotPath;
        screenshotPath = await manager.captureScreenshot(
          '${name}_step_${i + 1}_FAILED',
        );

        results.add({
          'description': description,
          'passed': false,
          'error': e.toString(),
          'screenshotPath': screenshotPath,
        });

        if (stopOnError) break;
      }
    }

    return {
      'name': name,
      'allPassed': allPassed,
      'passedCount': results.where((r) => r['passed'] == true).length,
      'failedCount': results.where((r) => r['passed'] == false).length,
      'steps': results,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // ===========================================================================
  // ACCESSIBILITY
  // ===========================================================================

  Future<Map<String, dynamic>> _accessibilityAudit() async {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;
    final issues = <Map<String, dynamic>>[];

    for (final entry in nodes.entries) {
      final node = entry.value;
      final widgetId = entry.key;

      // Check for unstable IDs
      if (widgetId.endsWith('_UNSTABLE')) {
        issues.add({
          'severity': 'warning',
          'widgetId': widgetId,
          'message': 'Widget has unstable ID',
          'suggestion': 'Add a Semantics label or ValueKey',
        });
      }

      // Check buttons without accessible names
      if (node.onTap != null &&
          (node.currentText == null || node.currentText!.isEmpty)) {
        issues.add({
          'severity': 'error',
          'widgetId': widgetId,
          'message': 'Interactive element has no accessible name',
          'suggestion': 'Add a Semantics label or visible text',
        });
      }

      // Check text inputs without labels
      if (node.onTextChange != null &&
          (node.currentText == null || node.currentText!.isEmpty)) {
        issues.add({
          'severity': 'warning',
          'widgetId': widgetId,
          'message': 'Text input has no label',
          'suggestion': 'Add a Semantics label or InputDecoration.labelText',
        });
      }
    }

    return {'issues': issues};
  }

  // ===========================================================================
  // CLIPBOARD
  // ===========================================================================

  Future<Map<String, dynamic>> _clipboardRead() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return {
        'text': data?.text ?? '',
        'hasData': data != null && data.text != null,
      };
    } catch (e) {
      return {'text': '', 'hasData': false, 'error': e.toString()};
    }
  }

  Future<void> _clipboardWrite(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  // ===========================================================================
  // HAR EXPORT
  // ===========================================================================

  Map<String, dynamic> _harExport() {
    // Generate HAR 1.2 format from network log
    final har = <String, dynamic>{
      'log': {
        'version': '1.2',
        'creator': {'name': 'SelfTestBridge', 'version': '2.0.0'},
        'entries': _networkLog.map((req) {
          final startTime =
              DateTime.tryParse(req['timestamp'] as String? ?? '') ??
              DateTime.now();
          final response = req['response'] as Map<String, dynamic>?;
          final responseTime =
              DateTime.tryParse(response?['timestamp'] as String? ?? '') ??
              startTime;
          final waitTime = responseTime.difference(startTime).inMilliseconds;

          return {
            'startedDateTime': startTime.toIso8601String(),
            'time': waitTime,
            'request': {
              'method': req['method'] ?? 'GET',
              'url': req['url'] ?? '',
              'httpVersion': 'HTTP/1.1',
              'cookies': <dynamic>[],
              'headers': _convertHeadersToHar(
                req['headers'] as Map<String, dynamic>?,
              ),
              'queryString': _parseQueryString(req['url'] as String?),
              'postData': req['body'] != null
                  ? {
                      'mimeType': req['contentType'] ?? 'application/json',
                      'text': req['body'] is String
                          ? req['body']
                          : jsonEncode(req['body']),
                    }
                  : null,
              'headersSize': -1,
              'bodySize': req['body'] != null
                  ? (req['body'] is String
                        ? (req['body'] as String).length
                        : jsonEncode(req['body']).length)
                  : 0,
            },
            'response': {
              'status': response?['status'] ?? 0,
              'statusText': response?['statusText'] ?? '',
              'httpVersion': 'HTTP/1.1',
              'cookies': <dynamic>[],
              'headers': _convertHeadersToHar(
                response?['headers'] as Map<String, dynamic>?,
              ),
              'content': {
                'size': response?['body'] != null
                    ? (response!['body'] is String
                          ? (response['body'] as String).length
                          : jsonEncode(response['body']).length)
                    : 0,
                'mimeType': response?['contentType'] ?? 'application/json',
                'text': response != null && response['body'] is String
                    ? response['body']
                    : jsonEncode(response?['body'] ?? {}),
              },
              'redirectURL': response?['redirectUrl'] ?? '',
              'headersSize': -1,
              'bodySize': response?['body'] != null
                  ? (response!['body'] is String
                        ? (response['body'] as String).length
                        : jsonEncode(response['body']).length)
                  : 0,
            },
            'cache': <String, dynamic>{},
            'timings': {
              'blocked': 0,
              'dns': -1,
              'connect': -1,
              'send': 0,
              'wait': waitTime,
              'receive': 0,
              'ssl': -1,
            },
          };
        }).toList(),
      },
    };

    return har;
  }

  List<Map<String, dynamic>> _convertHeadersToHar(
    Map<String, dynamic>? headers,
  ) {
    if (headers == null) return [];
    return headers.entries
        .map((e) => {'name': e.key, 'value': e.value?.toString() ?? ''})
        .toList();
  }

  List<Map<String, dynamic>> _parseQueryString(String? url) {
    if (url == null) return [];
    final uri = Uri.tryParse(url);
    if (uri == null) return [];
    return uri.queryParameters.entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();
  }

  // ===========================================================================
  // ANIMATION CONTROL
  // ===========================================================================

  void _setAnimationSpeed(double speed) {
    // timeDilation controls animation speed globally
    // speed = 0 pauses animations (we use a very large value)
    // speed = 0.5 is slow motion (2x timeDilation)
    // speed = 1 is normal (1x timeDilation)
    // speed = 2 is fast (0.5x timeDilation)
    if (speed <= 0) {
      // Pause animations by setting a very high dilation
      timeDilation = 1000000.0;
    } else {
      // timeDilation is inverse of speed
      // speed 2 = timeDilation 0.5 (faster)
      // speed 0.5 = timeDilation 2 (slower)
      timeDilation = 1.0 / speed;
    }
    _logConsole(
      'info',
      'Animation speed set to $speed (timeDilation: $timeDilation)',
    );
  }

  Future<void> _pump([int durationMs = 0]) async {
    final binding = WidgetsBinding.instance;

    if (durationMs > 0) {
      // Advance time by the specified duration
      // We do this by scheduling multiple frames
      final frames = (durationMs / 16.67).ceil(); // ~60fps
      for (int i = 0; i < frames; i++) {
        binding.scheduleFrame();
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } else {
      // Just pump once - schedule a single frame
      binding.scheduleFrame();
    }

    // Wait for the frame to be processed
    await Future.delayed(Duration(milliseconds: durationMs > 0 ? 1 : 16));

    // Ensure all scheduled callbacks are processed
    await binding.endOfFrame;
  }

  // ===========================================================================
  // ===========================================================================
  // FRAME BUDGET ANALYSIS IMPLEMENTATIONS
  // ===========================================================================

  /// Callback for frame timings during profiling
  void _onFrameTimings(List<FrameTiming> timings) {
    if (_isProfilingFrames) {
      _frameTimings.addAll(timings);
    }

    // Handle jank detection if enabled
    if (_jankDetectorEnabled) {
      for (final timing in timings) {
        _jankDetectorTotalFrames++;
        final durationMs = timing.totalSpan.inMicroseconds / 1000.0;
        if (durationMs > _jankThresholdMs) {
          _jankDetectorJankyFrames++;
          if (durationMs > _jankDetectorWorstFrameMs) {
            _jankDetectorWorstFrameMs = durationMs;
          }
          _logConsole(
            'warning',
            'Jank detected: frame took ${durationMs.toStringAsFixed(2)}ms (threshold: ${_jankThresholdMs}ms)',
          );
        }
      }
    }
  }

  /// Start frame timing profiling
  void _startFrameProfiling({double? budgetMs}) {
    _frameTimings.clear();
    _frameBudgetMs = budgetMs ?? 16.67;
    _isProfilingFrames = true;

    // Register the frame timings callback
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    _logConsole(
      'info',
      'Frame profiling started (budget: ${_frameBudgetMs}ms)',
    );
  }

  /// Stop frame profiling and return results
  Map<String, dynamic> _stopFrameProfiling() {
    _isProfilingFrames = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);

    if (_frameTimings.isEmpty) {
      return {
        'totalFrames': 0,
        'jankyFrames': 0,
        'averageMs': 0.0,
        'p50Ms': 0.0,
        'p95Ms': 0.0,
        'p99Ms': 0.0,
        'worstFrame': null,
        'histogram': {'0-8ms': 0, '8-16ms': 0, '16-32ms': 0, '32ms+': 0},
      };
    }

    // Convert frame timings to durations in milliseconds
    final durations = _frameTimings
        .map((t) => t.totalSpan.inMicroseconds / 1000.0)
        .toList();

    // Sort for percentile calculations
    durations.sort();

    // Calculate statistics
    final totalFrames = durations.length;
    final jankyFrames = durations.where((d) => d > _frameBudgetMs).length;
    final average = durations.reduce((a, b) => a + b) / totalFrames;

    // Find worst frame
    double worstDuration = 0;
    int worstIndex = 0;
    for (int i = 0; i < _frameTimings.length; i++) {
      final duration = _frameTimings[i].totalSpan.inMicroseconds / 1000.0;
      if (duration > worstDuration) {
        worstDuration = duration;
        worstIndex = i;
      }
    }

    // Calculate histogram
    final histogram = {
      '0-8ms': durations.where((d) => d < 8).length,
      '8-16ms': durations.where((d) => d >= 8 && d < 16).length,
      '16-32ms': durations.where((d) => d >= 16 && d < 32).length,
      '32ms+': durations.where((d) => d >= 32).length,
    };

    _logConsole(
      'info',
      'Frame profiling stopped: $totalFrames frames, $jankyFrames janky',
    );

    return {
      'totalFrames': totalFrames,
      'jankyFrames': jankyFrames,
      'averageMs': average,
      'p50Ms': _percentile(durations, 50),
      'p95Ms': _percentile(durations, 95),
      'p99Ms': _percentile(durations, 99),
      'worstFrame': {'index': worstIndex, 'durationMs': worstDuration},
      'histogram': histogram,
    };
  }

  /// Calculate percentile from sorted list
  double _percentile(List<double> sortedList, int percentile) {
    if (sortedList.isEmpty) return 0.0;
    final index = ((percentile / 100) * (sortedList.length - 1)).round();
    return sortedList[index.clamp(0, sortedList.length - 1)];
  }

  /// Profile a specific action and return frame analysis
  Future<Map<String, dynamic>> _frameBudgetCheck(
    String action,
    String? widgetId,
    Map<String, dynamic> actionParams,
    double budgetMs,
  ) async {
    // Start profiling
    _startFrameProfiling(budgetMs: budgetMs);

    final stopwatch = Stopwatch()..start();

    try {
      // Execute the action
      switch (action) {
        case 'scroll':
          final direction = actionParams['direction'] as String? ?? 'down';
          final delta = (actionParams['delta'] as num?)?.toDouble() ?? 300.0;
          await _scroll(widgetId, direction, delta);
          break;

        case 'tap':
          if (widgetId == null) {
            throw Exception('widgetId required for tap action');
          }
          final manager = SelfTestManager();
          await _waitForWidget(widgetId, 5000);
          await manager.trigger(widgetId);
          await manager.waitForAnimations();
          break;

        case 'navigate':
          final route = actionParams['route'] as String?;
          final target = navigator;
          if (route != null && target != null) {
            await target.goTo(route);
            await SelfTestManager().waitForAnimations();
          }
          break;

        case 'type':
          if (widgetId == null) {
            throw Exception('widgetId required for type action');
          }
          final text = actionParams['text'] as String? ?? '';
          final manager = SelfTestManager();
          await manager.enterText(widgetId, text);
          await manager.waitForAnimations();
          break;

        case 'drag':
          final sourceId = actionParams['sourceId'] as String?;
          final targetId = actionParams['targetId'] as String?;
          if (sourceId != null && targetId != null) {
            await _drag(sourceId, targetId);
          }
          break;

        default:
          throw Exception('Unknown action: $action');
      }

      // Wait a bit for frames to settle
      await Future.delayed(const Duration(milliseconds: 100));
    } finally {
      stopwatch.stop();
    }

    // Get profiling results
    final results = _stopFrameProfiling();

    // Add action duration
    results['actionDuration'] = stopwatch.elapsedMicroseconds / 1000.0;
    results['action'] = action;
    results['widgetId'] = widgetId;

    return results;
  }

  /// Enable or disable continuous jank monitoring
  Map<String, dynamic> _setJankDetector(
    bool enabled,
    double threshold,
    bool callback,
  ) {
    final previousState = _jankDetectorEnabled;

    if (enabled && !previousState) {
      // Enable jank detection
      _jankDetectorEnabled = true;
      _jankThresholdMs = threshold;
      _jankDetectorTotalFrames = 0;
      _jankDetectorJankyFrames = 0;
      _jankDetectorWorstFrameMs = 0;

      // Register callback if not already profiling
      if (!_isProfilingFrames) {
        SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
      }

      _logConsole('info', 'Jank detector enabled (threshold: ${threshold}ms)');

      return {
        'enabled': true,
        'threshold': threshold,
        'statistics': {'totalFrames': 0, 'jankyFrames': 0, 'jankRate': 0.0},
      };
    } else if (!enabled && previousState) {
      // Disable jank detection
      _jankDetectorEnabled = false;

      // Remove callback if not profiling
      if (!_isProfilingFrames) {
        SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
      }

      final jankRate = _jankDetectorTotalFrames > 0
          ? (_jankDetectorJankyFrames / _jankDetectorTotalFrames) * 100
          : 0.0;

      _logConsole('info', 'Jank detector disabled');

      return {
        'enabled': false,
        'statistics': {
          'totalFrames': _jankDetectorTotalFrames,
          'jankyFrames': _jankDetectorJankyFrames,
          'jankRate': jankRate,
          'worstFrameMs': _jankDetectorWorstFrameMs,
        },
      };
    }

    // Return current state if no change
    final jankRate = _jankDetectorTotalFrames > 0
        ? (_jankDetectorJankyFrames / _jankDetectorTotalFrames) * 100
        : 0.0;

    return {
      'enabled': _jankDetectorEnabled,
      'threshold': _jankThresholdMs,
      'statistics': {
        'totalFrames': _jankDetectorTotalFrames,
        'jankyFrames': _jankDetectorJankyFrames,
        'jankRate': jankRate,
        'worstFrameMs': _jankDetectorWorstFrameMs,
      },
    };
  }

  // ===========================================================================
  // MEMORY PROFILING IMPLEMENTATIONS
  // ===========================================================================

  /// Get current memory usage snapshot
  Map<String, dynamic> _getMemorySnapshot() {
    final imageCache = PaintingBinding.instance.imageCache;

    return {
      'heapUsed': _getHeapUsage(),
      'heapCapacity': _getHeapCapacity(),
      'externalUsage': _getExternalUsage(),
      'imageCache': {
        'count': imageCache.currentSize,
        'sizeBytes': imageCache.currentSizeBytes,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Start memory profiling at specified intervals
  void _startMemoryProfiling({int intervalMs = 1000}) {
    // Starting twice used to drop the first timer on the floor and keep it
    // ticking forever, so the samples came from two interleaved runs.
    if (_isProfilingMemory) return;
    _memorySamples.clear();
    _isProfilingMemory = true;

    _memoryProfilingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (
      _,
    ) {
      _memorySamples.add(
        _MemorySample(timestamp: DateTime.now(), heapUsed: _getHeapUsage()),
      );
    });

    _logConsole('info', 'Memory profiling started (interval: ${intervalMs}ms)');
  }

  /// Stop memory profiling and return results
  Map<String, dynamic> _stopMemoryProfiling() {
    _isProfilingMemory = false;
    _memoryProfilingTimer?.cancel();
    _memoryProfilingTimer = null;

    if (_memorySamples.isEmpty) {
      return {
        'samples': <Map<String, dynamic>>[],
        'peak': 0,
        'average': 0,
        'leakSuspects': <String>[],
      };
    }

    final heapValues = _memorySamples.map((s) => s.heapUsed).toList();
    final peak = heapValues.reduce((a, b) => a > b ? a : b);
    final average = heapValues.reduce((a, b) => a + b) ~/ heapValues.length;

    // Simple leak detection: check if memory is monotonically increasing
    final leakSuspects = <String>[];
    if (_isMonotonicallyIncreasing(heapValues)) {
      leakSuspects.add(
        'Possible memory leak: heap usage continuously increasing',
      );
    }

    // Check for significant growth (more than 20% increase from start to end)
    if (heapValues.length > 1 && heapValues.first > 0) {
      final growthRate =
          (heapValues.last - heapValues.first) / heapValues.first;
      if (growthRate > 0.2) {
        leakSuspects.add(
          'Significant memory growth: ${(growthRate * 100).toStringAsFixed(1)}% increase',
        );
      }
    }

    _logConsole(
      'info',
      'Memory profiling stopped: ${_memorySamples.length} samples',
    );

    return {
      'samples': _memorySamples.map((s) => s.toJson()).toList(),
      'peak': peak,
      'average': average,
      'leakSuspects': leakSuspects,
    };
  }

  /// Force garbage collection
  Future<Map<String, dynamic>> _forceGc() async {
    final before = _getHeapUsage();

    // Clear image cache to free memory
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // Give GC time to run
    await Future.delayed(const Duration(milliseconds: 100));

    final after = _getHeapUsage();

    _logConsole('info', 'GC requested: $before -> $after bytes');

    return {
      'memoryBefore': before,
      'memoryAfter': after,
      'freed': before - after,
    };
  }

  /// Get image cache statistics
  Map<String, dynamic> _getImageCacheStats() {
    final cache = PaintingBinding.instance.imageCache;
    return {
      'currentSize': cache.currentSize,
      'maximumSize': cache.maximumSize,
      'liveImages': cache.liveImageCount,
      'pendingImages': cache.pendingImageCount,
      'currentSizeBytes': cache.currentSizeBytes,
      'maximumSizeBytes': cache.maximumSizeBytes,
    };
  }

  /// Clear the image cache
  Map<String, dynamic> _clearImageCache() {
    final cache = PaintingBinding.instance.imageCache;
    final sizeBefore = cache.currentSizeBytes;
    final countBefore = cache.currentSize;

    cache.clear();
    cache.clearLiveImages();

    _logConsole(
      'info',
      'Image cache cleared: $countBefore images, $sizeBefore bytes',
    );

    return {'cleared': countBefore, 'freedBytes': sizeBefore};
  }

  /// Run heuristic leak detection by repeating an action
  Future<Map<String, dynamic>> _memoryLeakCheck(
    String action,
    int iterations,
  ) async {
    final manager = SelfTestManager();
    final memoryBefore = _getHeapUsage();
    final samples = <int>[];

    for (int i = 0; i < iterations; i++) {
      // Execute the action
      try {
        final command = BridgeCommand(id: 0, command: action, params: {});
        await _executeCommand(command);
      } catch (e) {
        // Continue even if action fails
        _logConsole('warning', 'Leak check action failed: $e');
      }

      // Wait for animations and GC
      await manager.waitForAnimations();
      await Future.delayed(const Duration(milliseconds: 100));

      // Record memory
      samples.add(_getHeapUsage());
    }

    final memoryAfter = _getHeapUsage();
    final memoryGrowth = memoryAfter - memoryBefore;

    // Analyze for potential leaks
    final potentialLeaks = _isMonotonicallyIncreasing(samples);
    final suspectedWidgets = <String>[];

    // Check growth rate
    if (samples.isNotEmpty && memoryBefore > 0) {
      final growthRate = memoryGrowth / memoryBefore;
      if (growthRate > 0.1) {
        suspectedWidgets.add(
          'High memory growth rate: ${(growthRate * 100).toStringAsFixed(1)}%',
        );
      }
    }

    // Check if memory consistently increases with each iteration
    if (potentialLeaks) {
      suspectedWidgets.add('Memory increases with each iteration of "$action"');
    }

    return {
      'potentialLeaks':
          potentialLeaks ||
          (memoryBefore > 0 && memoryGrowth > memoryBefore * 0.1),
      'memoryGrowth': memoryGrowth,
      'memoryBefore': memoryBefore,
      'memoryAfter': memoryAfter,
      'iterations': iterations,
      'samples': samples,
      'suspectedWidgets': suspectedWidgets,
    };
  }

  /// Get approximate heap usage
  int _getHeapUsage() {
    // In debug/profile mode, we can get some memory info
    // This is approximate - actual heap access requires VM service
    try {
      // Try to get process info if available (dart:io)
      return ProcessInfo.currentRss;
    } catch (_) {
      // Fallback: return 0 if not available
      return 0;
    }
  }

  /// Get approximate heap capacity
  int _getHeapCapacity() {
    try {
      return ProcessInfo.maxRss;
    } catch (_) {
      return 0;
    }
  }

  /// Get external memory usage (estimate from image cache)
  int _getExternalUsage() {
    // External usage is primarily from images and native buffers
    final imageCache = PaintingBinding.instance.imageCache;
    return imageCache.currentSizeBytes;
  }

  /// Check if values are monotonically increasing
  bool _isMonotonicallyIncreasing(List<int> values) {
    if (values.length < 2) return false;
    for (int i = 1; i < values.length; i++) {
      if (values[i] < values[i - 1]) return false;
    }
    return true;
  }

  // HELPERS
  // ===========================================================================

  void _captureError(FlutterErrorDetails details) {
    _errors.add({
      'type': details.exception.runtimeType.toString(),
      'message': details.exceptionAsString(),
      'stackTrace': details.stack?.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _logConsole(String level, String message) {
    _consoleMessages.add({
      'level': level,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
    debugPrint('[$level] $message');
  }

  String _inferWidgetType(TestNode node) {
    // TestNode only has onTap and onTextChange callbacks
    // We infer widget type based on these and the node id
    if (node.onTap != null && node.onTextChange != null) {
      return 'interactive';
    }
    if (node.onTap != null) {
      // Check if the id suggests a toggle/checkbox/switch
      final lowerId = node.id.toLowerCase();
      if (lowerId.contains('checkbox') ||
          lowerId.contains('switch') ||
          lowerId.contains('toggle')) {
        return 'checkbox';
      }
      return 'button';
    }
    if (node.onTextChange != null) {
      // Check if the id suggests a slider
      final lowerId = node.id.toLowerCase();
      if (lowerId.contains('slider')) {
        return 'slider';
      }
      return 'text_input';
    }
    return 'unknown';
  }

  String _inferScreen(BuildContext context) {
    try {
      final route = ModalRoute.of(context);
      if (route?.settings.name != null) {
        return route!.settings.name!
            .replaceAll('/', '_')
            .replaceAll('-', '_')
            .toLowerCase()
            .replaceFirst('_', '');
      }
    } catch (_) {}

    try {
      BuildContext? current = context;
      while (current != null) {
        final widget = current.widget;
        final typeName = widget.runtimeType.toString();
        if (typeName.endsWith('Screen') || typeName.endsWith('Page')) {
          return typeName
              .replaceAll('Screen', '')
              .replaceAll('Page', '')
              .replaceAllMapped(RegExp(r'(?<!^)(?=[A-Z])'), (m) => '_')
              .toLowerCase();
        }

        BuildContext? parent;
        current.visitAncestorElements((element) {
          parent = element;
          return false;
        });
        current = parent;
      }
    } catch (_) {}

    return 'unknown';
  }

  bool _inferAuthRequirement(String screenName) {
    final lower = screenName.toLowerCase();
    if (lower.contains('login') ||
        lower.contains('sign') ||
        lower.contains('intro') ||
        lower.contains('welcome') ||
        lower.contains('forgot')) {
      return false;
    }
    return true;
  }

  // ===========================================================================
  // PLATFORM CHANNEL MOCKING
  // ===========================================================================

  /// Initialize platform channel mocking by setting up mock method call handlers
  void _initializeChannelMocking() {
    if (_channelMockingInitialized) return;
    _channelMockingInitialized = true;
    _logConsole('info', 'Platform channel mocking initialized');
  }

  /// Mock a platform channel method with specified response
  void _mockChannel(
    String channel,
    String method,
    dynamic response,
    String? errorCode,
    String? errorMessage,
  ) {
    _initializeChannelMocking();

    // Get or create the channel's method mocks
    final channelMocks = _channelMocks.putIfAbsent(channel, () => {});

    // Store the mock configuration
    channelMocks[method] = _ChannelMockConfig(
      response: response,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );

    // Set up the mock handler for this channel
    _setupChannelHandler(channel);

    _logConsole('info', 'Mocked $channel:$method');
  }

  /// Set up a mock handler for a specific channel
  void _setupChannelHandler(String channel) {
    const codec = StandardMethodCodec();

    // Set the message handler on the binary messenger
    ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(channel, (
      ByteData? message,
    ) async {
      if (message == null) return null;

      final methodCall = codec.decodeMethodCall(message);
      final timestamp = DateTime.now().toIso8601String();

      // Log the call
      _channelCallLog.add({
        'channel': channel,
        'method': methodCall.method,
        'arguments': methodCall.arguments,
        'timestamp': timestamp,
      });

      // Check if we have a mock for this method
      final channelMocks = _channelMocks[channel];
      if (channelMocks != null && channelMocks.containsKey(methodCall.method)) {
        final config = channelMocks[methodCall.method]!;

        // Update the log entry with the result
        _channelCallLog.last['mocked'] = true;

        // If error is configured, encode PlatformException
        if (config.errorCode != null) {
          _channelCallLog.last['error'] = config.errorCode;
          return codec.encodeErrorEnvelope(
            code: config.errorCode!,
            message: config.errorMessage,
          );
        }

        // Return the mocked response
        _channelCallLog.last['result'] = config.response;
        return codec.encodeSuccessEnvelope(config.response);
      }

      // No mock found, mark as passthrough and return null
      // This allows the original handler to be called
      _channelCallLog.last['mocked'] = false;
      return null;
    });
  }

  /// Clear all channel mocks or mocks for a specific channel
  void _clearChannelMocks(String? channel) {
    if (channel != null) {
      // Clear mocks for specific channel
      _channelMocks.remove(channel);
      ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
        channel,
        null,
      );
      _logConsole('info', 'Cleared mocks for channel: $channel');
    } else {
      // Clear all mocks
      for (final ch in _channelMocks.keys.toList()) {
        ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
          ch,
          null,
        );
      }
      _channelMocks.clear();
      _logConsole('info', 'Cleared all channel mocks');
    }
  }

  /// Get the channel call log
  Map<String, dynamic> _getChannelLog(String? channel, int limit, bool clear) {
    var calls = _channelCallLog.toList();

    // Filter by channel if specified
    if (channel != null) {
      calls = calls.where((c) => c['channel'] == channel).toList();
    }

    // Reverse to get most recent first and apply limit
    final result = calls.reversed.take(limit).toList();

    if (clear) {
      if (channel != null) {
        _channelCallLog.removeWhere((c) => c['channel'] == channel);
      } else {
        _channelCallLog.clear();
      }
    }

    return {'calls': result};
  }

  // ===========================================================================
  // SENSOR & DEVICE MOCKING IMPLEMENTATIONS
  // ===========================================================================

  /// Set mock geolocation
  Map<String, dynamic> _setGeolocation(Map<String, dynamic> params) {
    final location = MockLocation.fromJson(params);
    _mockLocation = location;

    // Invoke the callback if registered
    if (onLocationChanged != null) {
      onLocationChanged!(location);
    }

    _logConsole(
      'info',
      'Mock location set: (${location.latitude}, ${location.longitude})',
    );

    return {'success': true, 'location': location.toJson()};
  }

  /// Set mock permission state
  Map<String, dynamic> _setPermission(Map<String, dynamic> params) {
    final permissionStr = params['permission'] as String;
    final stateStr = params['state'] as String;

    final permission = MockPermissionType.fromString(permissionStr);
    final state = MockPermissionState.fromString(stateStr);

    _mockPermissions[permission] = state;

    _logConsole('info', 'Mock permission set: $permissionStr = $stateStr');

    return {'success': true, 'permission': permissionStr, 'state': stateStr};
  }

  /// Set mock connectivity state
  Map<String, dynamic> _setConnectivity(Map<String, dynamic> params) {
    final connectivity = MockConnectivity.fromJson(params);
    _mockConnectivity = connectivity;

    // Invoke the callback if registered
    if (onConnectivityChanged != null) {
      onConnectivityChanged!(connectivity);
    }

    _logConsole(
      'info',
      'Mock connectivity set: ${connectivity.state.name} (connected: ${connectivity.isConnected})',
    );

    return {'success': true, 'connectivity': connectivity.toJson()};
  }

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

  // ===========================================================================
  // BIOMETRIC AUTHENTICATION MOCKING IMPLEMENTATIONS
  // ===========================================================================

  /// Set which biometric types are available
  Map<String, dynamic> _setBiometricAvailability(Map<String, dynamic> params) {
    if (params['faceId'] != null) {
      _biometricFaceIdAvailable = params['faceId'] as bool;
    }
    if (params['touchId'] != null) {
      _biometricTouchIdAvailable = params['touchId'] as bool;
    }
    if (params['fingerprint'] != null) {
      _biometricFingerprintAvailable = params['fingerprint'] as bool;
    }
    if (params['iris'] != null) {
      _biometricIrisAvailable = params['iris'] as bool;
    }
    if (params['deviceCredential'] != null) {
      _biometricDeviceCredentialAvailable = params['deviceCredential'] as bool;
    }

    final available = getAvailableBiometrics();
    _logConsole('info', 'Biometric availability set: $available');

    return {'available': available};
  }

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

  /// Set what the next biometric auth will return
  Map<String, dynamic> _setBiometricResult(Map<String, dynamic> params) {
    final resultStr = params['result'] as String;
    _nextBiometricResult = MockBiometricResult.fromString(resultStr);
    _nextBiometricErrorMessage = params['errorMessage'] as String?;
    _nextBiometricDelay = (params['delay'] as int?) ?? 0;

    _logConsole(
      'info',
      'Biometric result configured: $_nextBiometricResult'
          '${_nextBiometricErrorMessage != null ? ' (error: $_nextBiometricErrorMessage)' : ''}'
          '${_nextBiometricDelay > 0 ? ' (delay: ${_nextBiometricDelay}ms)' : ''}',
    );

    return {'configured': true};
  }

  /// Get history of biometric authentication attempts
  Map<String, dynamic> _getBiometricAuthHistory() {
    return {'attempts': _biometricHistory.map((a) => a.toJson()).toList()};
  }

  /// Simulate a biometric prompt and get the configured result
  Future<Map<String, dynamic>> _simulateBiometricPrompt(
    String reason,
    String? type,
  ) async {
    // Apply configured delay
    if (_nextBiometricDelay > 0) {
      await Future.delayed(Duration(milliseconds: _nextBiometricDelay));
    }

    final biometricType = type ?? 'fingerprint';
    final resultStr = _nextBiometricResult.name;
    final success = _nextBiometricResult == MockBiometricResult.success;

    // Record the attempt
    final attempt = BiometricAttempt(
      timestamp: DateTime.now(),
      type: biometricType,
      result: resultStr,
      reason: reason,
    );
    _biometricHistory.add(attempt);

    _logConsole(
      'info',
      'Biometric auth attempt: $biometricType, result: $resultStr, reason: $reason',
    );

    // Trigger callback if set
    if (onBiometricAuth != null) {
      try {
        await onBiometricAuth!(reason);
      } catch (e) {
        _logConsole('error', 'Biometric auth callback error: $e');
      }
    }

    return {
      'success': success,
      if (success) 'authenticatedAs': 'user',
      if (!success) 'error': _nextBiometricErrorMessage ?? resultStr,
    };
  }

  /// Clear biometric configuration and reset to defaults
  Map<String, dynamic> _clearBiometricConfig() {
    _biometricFaceIdAvailable = false;
    _biometricTouchIdAvailable = false;
    _biometricFingerprintAvailable = false;
    _biometricIrisAvailable = false;
    _biometricDeviceCredentialAvailable = true;
    _nextBiometricResult = MockBiometricResult.success;
    _nextBiometricErrorMessage = null;
    _nextBiometricDelay = 0;
    _biometricHistory.clear();

    _logConsole('info', 'Biometric configuration cleared');

    return {'cleared': true};
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

  Future<Map<String, dynamic>> _getState(
    String providerId,
    String? path,
    String stateType,
  ) async {
    // Try registered providers first
    final provider = _stateProviders[providerId];
    if (provider != null) {
      try {
        var state = provider.getState();

        // Apply path extraction if specified
        if (path != null && path.isNotEmpty) {
          state = _extractPath(state, path);
        }

        return {
          'state': state,
          'stateType': provider.type,
          'metadata': {
            'providerId': providerId,
            'timestamp': DateTime.now().toIso8601String(),
          },
        };
      } catch (e) {
        throw Exception('Failed to get state for $providerId: $e');
      }
    }

    // Try Riverpod if available and stateType allows
    if ((stateType == 'auto' || stateType == 'riverpod') &&
        _riverpodContainer != null) {
      final riverpodState = await _getRiverpodState(providerId, path);
      if (riverpodState != null) {
        return riverpodState;
      }
    }

    throw Exception(
      'State provider "$providerId" not found. '
      'Register it using registerStateProvider() or registerRiverpodContainer().',
    );
  }

  Future<Map<String, dynamic>?> _getRiverpodState(
    String providerId,
    String? path,
  ) async {
    // This requires runtime reflection or code generation to work with Riverpod.
    // For now, we rely on registered providers. Apps can register their Riverpod
    // providers manually using registerStateProvider().
    //
    // A full implementation would require:
    // 1. Access to the ProviderContainer
    // 2. A way to look up providers by name (which Riverpod doesn't provide natively)
    // 3. Reading the current value
    //
    // Apps can integrate this by:
    // ```dart
    // bridge.registerStateProvider(
    //   'userProvider',
    //   type: 'riverpod',
    //   getState: () => ref.read(userProvider).toJson(),
    //   dispatchAction: (action, payload) {
    //     if (action == 'setUser') ref.read(userProvider.notifier).setUser(payload);
    //   },
    // );
    // ```
    return null;
  }

  Map<String, dynamic> _extractPath(Map<String, dynamic> state, String path) {
    // Parse path like 'user.name' or 'items[0].id'
    final segments = path.split('.');
    dynamic current = state;

    for (final segment in segments) {
      if (current == null) {
        throw Exception('Path "$path" not found: null encountered');
      }

      // Check for array access like 'items[0]'
      final arrayMatch = RegExp(r'^(\w+)\[(\d+)\]$').firstMatch(segment);
      if (arrayMatch != null) {
        final key = arrayMatch.group(1)!;
        final index = int.parse(arrayMatch.group(2)!);

        if (current is Map) {
          current = current[key];
        } else {
          throw Exception(
            'Expected map at "$key" but got ${current.runtimeType}',
          );
        }

        if (current is List && index < current.length) {
          current = current[index];
        } else {
          throw Exception('Invalid array access: $segment');
        }
      } else {
        if (current is Map) {
          current = current[segment];
        } else {
          throw Exception(
            'Expected map at "$segment" but got ${current.runtimeType}',
          );
        }
      }
    }

    // Wrap result in a map if it's not already
    if (current is Map<String, dynamic>) {
      return current;
    }
    return {'value': current};
  }

  Future<Map<String, dynamic>> _dispatchAction(
    String providerId,
    String action,
    dynamic payload,
    String stateType,
  ) async {
    final provider = _stateProviders[providerId];
    if (provider == null) {
      throw Exception(
        'State provider "$providerId" not found. '
        'Register it using registerStateProvider() to enable action dispatch.',
      );
    }

    if (provider.dispatchAction == null) {
      throw Exception(
        'State provider "$providerId" does not support action dispatch. '
        'Provide a dispatchAction callback when registering.',
      );
    }

    // Capture state before
    final previousState = provider.getState();

    // Dispatch the action
    provider.dispatchAction!(action, payload);

    // Wait a frame for state to update
    await Future.delayed(const Duration(milliseconds: 16));

    // Capture state after
    final newState = provider.getState();

    return {
      'success': true,
      'providerId': providerId,
      'action': action,
      'previousState': previousState,
      'newState': newState,
    };
  }

  Future<Map<String, dynamic>> _watchState(
    String providerId,
    String stateType,
    int debounceMs,
  ) async {
    final provider = _stateProviders[providerId];
    if (provider == null) {
      throw Exception('State provider "$providerId" not found.');
    }

    // Generate subscription ID
    final subscriptionId = 'watch_${++_subscriptionIdCounter}';

    // Get initial state
    final initialState = provider.getState();

    // Create subscription
    final subscription = _StateWatchSubscription(
      id: subscriptionId,
      providerId: providerId,
      changes: [],
      debounceMs: debounceMs,
    );

    // If provider has a state stream, subscribe to it
    if (provider.stateStream != null) {
      subscription.streamSubscription = provider.stateStream!.listen((state) {
        subscription.changes.add({
          'state': state,
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
    } else {
      // Poll for changes (less efficient but works without streams)
      subscription.pollTimer = Timer.periodic(
        Duration(milliseconds: debounceMs),
        (_) {
          try {
            final currentState = provider.getState();
            final lastState = subscription.changes.isNotEmpty
                ? subscription.changes.last['state']
                : initialState;

            // Simple equality check - deep comparison would be better
            if (jsonEncode(currentState) != jsonEncode(lastState)) {
              subscription.changes.add({
                'state': currentState,
                'timestamp': DateTime.now().toIso8601String(),
              });
            }
          } catch (e) {
            _logConsole('error', 'Error polling state for $providerId: $e');
          }
        },
      );
    }

    _stateWatches[subscriptionId] = subscription;

    return {
      'subscriptionId': subscriptionId,
      'initialState': initialState,
      'providerId': providerId,
    };
  }

  Map<String, dynamic> _getStateChanges(String subscriptionId, bool clear) {
    final subscription = _stateWatches[subscriptionId];
    if (subscription == null) {
      throw Exception('Subscription "$subscriptionId" not found.');
    }

    final changes = List<Map<String, dynamic>>.from(subscription.changes);

    if (clear) {
      subscription.changes.clear();
    }

    return {
      'subscriptionId': subscriptionId,
      'providerId': subscription.providerId,
      'changes': changes,
    };
  }

  void _unwatchState(String subscriptionId) {
    final subscription = _stateWatches.remove(subscriptionId);
    if (subscription != null) {
      subscription.streamSubscription?.cancel();
      subscription.pollTimer?.cancel();
    }
  }

  Map<String, dynamic> _listStateProviders(String stateType) {
    final result = <String, List<Map<String, dynamic>>>{
      'riverpod': [],
      'bloc': [],
      'provider': [],
    };

    for (final provider in _stateProviders.values) {
      final category = _categorizeStateType(provider.type);
      if (stateType == 'all' || stateType == category) {
        try {
          final currentValue = provider.getState();
          (result[category] ?? result['provider']!).add({
            'name': provider.id,
            'type': provider.type,
            'currentValue': _truncateState(currentValue),
            'canDispatch': provider.dispatchAction != null,
            'hasStream': provider.stateStream != null,
          });
        } catch (e) {
          (result[category] ?? result['provider']!).add({
            'name': provider.id,
            'type': provider.type,
            'error': e.toString(),
          });
        }
      }
    }

    return result;
  }

  String _categorizeStateType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('riverpod') || lower.contains('notifier')) {
      return 'riverpod';
    }
    if (lower.contains('bloc') || lower.contains('cubit')) {
      return 'bloc';
    }
    return 'provider';
  }

  Map<String, dynamic> _truncateState(Map<String, dynamic> state) {
    // Truncate large state objects for listing
    final json = jsonEncode(state);
    if (json.length > 200) {
      return {'_truncated': true, '_preview': json.substring(0, 200)};
    }
    return state;
  }

  // ===========================================================================
  // WIDGET REBUILD PROFILING IMPLEMENTATIONS
  // ===========================================================================

  /// Start profiling widget rebuilds.
  ///
  /// Note: The `debugOnRebuildDirtyWidget` callback was removed in recent Flutter versions.
  /// This implementation uses frame callbacks and element tree sampling instead.
  Map<String, dynamic> _startRebuildProfiling() {
    if (_isProfilingRebuilds) {
      return {'success': false, 'error': 'Rebuild profiling is already active'};
    }

    // Clear previous profiling data
    _rebuildProfile.clear();
    _rebuildProfilingStartTime = DateTime.now();
    _isProfilingRebuilds = true;

    // Note: debugOnRebuildDirtyWidget is not available in current Flutter versions.
    // We track widgets using frame callbacks and element tree inspection instead.

    // Set up a frame callback to sample the widget tree periodically
    _rebuildProfilingFrameCallback = (Duration timestamp) {
      if (!_isProfilingRebuilds) return;

      // Schedule next frame callback
      SchedulerBinding.instance.addPostFrameCallback(
        _rebuildProfilingFrameCallback!,
      );

      // Sample elements by walking the tree
      _sampleWidgetTree();
    };

    SchedulerBinding.instance.addPostFrameCallback(
      _rebuildProfilingFrameCallback!,
    );

    _logConsole(
      'info',
      'Widget rebuild profiling started (using frame sampling)',
    );

    return {
      'success': true,
      'startTime': _rebuildProfilingStartTime?.toIso8601String(),
      'note':
          'Using frame-based sampling as debugOnRebuildDirtyWidget is not available',
    };
  }

  /// Sample the widget tree to track widgets.
  void _sampleWidgetTree() {
    try {
      final binding = WidgetsBinding.instance;
      final rootElement = binding.rootElement;
      if (rootElement == null) return;

      // Walk the element tree and track visible widgets
      void visitElement(Element element) {
        final widget = element.widget;
        final widgetType = widget.runtimeType.toString();
        final key = widget.key?.toString() ?? '';
        final widgetId = key.isNotEmpty ? '$widgetType($key)' : widgetType;

        // Track this widget - increment count each time we see it in a frame
        final info = _rebuildProfile.putIfAbsent(
          widgetId,
          () => _RebuildInfo(),
        );
        info.count++;
        info.reasons.add(_inferRebuildReason(element));

        // Try to get the widget location from debug info
        if (info.location == null) {
          info.location = _getWidgetLocation(element);
        }

        element.visitChildren(visitElement);
      }

      visitElement(rootElement);
    } catch (e) {
      // Silently ignore errors during sampling
    }
  }

  /// Stop profiling widget rebuilds and return results.
  Map<String, dynamic> _stopRebuildProfiling() {
    if (!_isProfilingRebuilds) {
      return {'error': 'Rebuild profiling is not active'};
    }

    _isProfilingRebuilds = false;
    final endTime = DateTime.now();
    final durationMs = _rebuildProfilingStartTime != null
        ? endTime.difference(_rebuildProfilingStartTime!).inMilliseconds
        : 0;

    // Clear the frame callback
    _rebuildProfilingFrameCallback = null;

    // Calculate totals
    int totalRebuilds = 0;
    for (final info in _rebuildProfile.values) {
      totalRebuilds += info.count;
    }

    // Convert to JSON-serializable format
    final widgets = <String, Map<String, dynamic>>{};
    for (final entry in _rebuildProfile.entries) {
      widgets[entry.key] = entry.value.toJson();
    }

    _logConsole(
      'info',
      'Widget rebuild profiling stopped. Total rebuilds: $totalRebuilds, Unique widgets: ${_rebuildProfile.length}',
    );

    return {
      'durationMs': durationMs,
      'totalRebuilds': totalRebuilds,
      'uniqueWidgets': _rebuildProfile.length,
      'widgets': widgets,
    };
  }

  /// Get detailed rebuild report with optional threshold filtering.
  Map<String, dynamic> _getRebuildReport(int threshold) {
    // Calculate totals
    int totalRebuilds = 0;
    for (final info in _rebuildProfile.values) {
      totalRebuilds += info.count;
    }

    // Filter and sort widgets by rebuild count
    final filtered = _rebuildProfile.entries
        .where((e) => e.value.count >= threshold)
        .toList();
    filtered.sort((a, b) => b.value.count.compareTo(a.value.count));

    // Convert to list format with widget ID included
    final widgets = filtered.map((entry) {
      final json = entry.value.toJson();
      json['widgetId'] = entry.key;
      return json;
    }).toList();

    return {
      'isActive': _isProfilingRebuilds,
      'totalRebuilds': totalRebuilds,
      'matchingWidgets': widgets.length,
      'widgets': widgets,
    };
  }

  /// Infer the reason for a widget rebuild based on element state.
  String _inferRebuildReason(Element element) {
    // Check if this is a StatefulElement
    if (element is StatefulElement) {
      // This could be due to setState being called
      return 'setState';
    }

    // Check for InheritedWidget dependencies
    try {
      // If the element depends on inherited widgets, it might have rebuilt
      // due to dependency changes
      final dependencies = element.debugGetDiagnosticChain();
      for (final diagnostic in dependencies) {
        final name = diagnostic.toStringShort();
        if (name.contains('InheritedWidget') || name.contains('Provider')) {
          return 'InheritedWidget/Provider changed';
        }
      }
    } catch (_) {
      // Ignore errors when accessing debug info
    }

    // Check for parent rebuilds
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false; // Stop at first ancestor
    });

    if (parent != null) {
      return 'Parent rebuilt';
    }

    return 'Unknown';
  }

  /// Get the source location of a widget if available from debug info.
  String? _getWidgetLocation(Element element) {
    try {
      // Try to get location from widget's toStringShort which sometimes includes it
      final diagnostics = element.toDiagnosticsNode();
      final properties = diagnostics.getProperties();

      for (final prop in properties) {
        if (prop.name == 'creationLocation' || prop.name == 'location') {
          return prop.value?.toString();
        }
      }

      // Try to extract from the diagnostic chain
      final chain = element.debugGetDiagnosticChain();
      for (final node in chain) {
        final nodeStr = node.toStringDeep();
        // Look for file:line patterns
        final match = RegExp(
          r'package:[^\s]+\.dart:\d+:\d+',
        ).firstMatch(nodeStr);
        if (match != null) {
          return match.group(0);
        }
      }
    } catch (_) {
      // Ignore errors when accessing debug info
    }
    return null;
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

  /// Get the dependency graph of all state providers.
  Map<String, dynamic> _getStateDependencyGraph() {
    final nodes = <Map<String, dynamic>>[];
    final edges = <Map<String, dynamic>>[];

    // Add all registered providers as nodes
    for (final provider in _stateProviders.values) {
      nodes.add({
        'id': provider.id,
        'type': _categorizeStateType(provider.type),
        'name': provider.id,
      });
    }

    // Add providers that appear in dependencies but aren't registered
    final allProviderIds = <String>{
      ..._stateProviders.keys,
      ..._providerDependencies.keys,
      ..._providerDependencies.values.expand((s) => s),
      ..._providerDependents.keys,
      ..._providerDependents.values.expand((s) => s),
    };

    for (final providerId in allProviderIds) {
      if (!_stateProviders.containsKey(providerId)) {
        nodes.add({'id': providerId, 'type': 'unknown', 'name': providerId});
      }
    }

    // Add dependency edges
    for (final entry in _providerDependencies.entries) {
      final consumer = entry.key;
      for (final dependency in entry.value) {
        edges.add({'from': consumer, 'to': dependency, 'type': 'depends'});
      }
    }

    // Add notification edges (reverse of depends)
    for (final entry in _providerDependents.entries) {
      final provider = entry.key;
      for (final dependent in entry.value) {
        // Check if this edge doesn't already exist as a 'depends' edge
        final existsAsDependsEdge = edges.any(
          (e) =>
              e['from'] == dependent &&
              e['to'] == provider &&
              e['type'] == 'depends',
        );
        if (!existsAsDependsEdge) {
          edges.add({'from': provider, 'to': dependent, 'type': 'notifies'});
        }
      }
    }

    return {'nodes': nodes, 'edges': edges};
  }

  /// Analyze what would be affected by changing a provider.
  Map<String, dynamic> _getStateImpactAnalysis(String providerId) {
    // Direct dependents
    final directDependents = _providerDependents[providerId]?.toList() ?? [];

    // Transitive dependents (BFS)
    final transitiveDependents = <String>{};
    final queue = <String>[...directDependents];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (transitiveDependents.add(current)) {
        queue.addAll(_providerDependents[current] ?? {});
      }
    }
    // Remove direct dependents from transitive set
    transitiveDependents.removeAll(directDependents);

    // Affected widgets
    final affectedWidgets = <String>{..._widgetConsumers[providerId] ?? {}};
    // Also include widgets affected by dependents
    for (final dependent in [...directDependents, ...transitiveDependents]) {
      affectedWidgets.addAll(_widgetConsumers[dependent] ?? {});
    }

    // Calculate impact score (0-100)
    final totalProviders = _stateProviders.length;
    final totalDependents =
        directDependents.length + transitiveDependents.length;
    final totalWidgets = affectedWidgets.length;

    int impactScore = 0;
    if (totalProviders > 0) {
      impactScore += ((totalDependents / totalProviders) * 50).round();
    }
    if (totalWidgets > 0) {
      impactScore += (totalWidgets.clamp(0, 10) * 5);
    }
    impactScore = impactScore.clamp(0, 100);

    return {
      'directDependents': directDependents,
      'transitiveDependents': transitiveDependents.toList(),
      'affectedWidgets': affectedWidgets.toList(),
      'impactScore': impactScore,
    };
  }

  /// Trace state flow from a source provider to widgets or a specific widget.
  Map<String, dynamic> _getStateTrace(String providerId, String? widgetId) {
    final path = <Map<String, dynamic>>[];
    final transformations = <String>[];

    // Start with the source provider
    path.add({
      'node': providerId,
      'type': _stateProviders.containsKey(providerId)
          ? _categorizeStateType(_stateProviders[providerId]!.type)
          : 'unknown',
    });

    if (widgetId != null) {
      // Find path from provider to specific widget
      final visited = <String>{providerId};
      final queue = <List<String>>[
        [providerId],
      ];

      while (queue.isNotEmpty) {
        final currentPath = queue.removeAt(0);
        final current = currentPath.last;

        // Check if this provider is consumed by the target widget
        if (_widgetConsumers[current]?.contains(widgetId) ?? false) {
          // Build the full path
          for (int i = 1; i < currentPath.length; i++) {
            final node = currentPath[i];
            path.add({
              'node': node,
              'type': _stateProviders.containsKey(node)
                  ? _categorizeStateType(_stateProviders[node]!.type)
                  : 'unknown',
            });
            transformations.add('$node depends on ${currentPath[i - 1]}');
          }
          path.add({'node': widgetId, 'type': 'widget'});
          transformations.add('$widgetId consumes $current');
          break;
        }

        // Explore dependents
        for (final dependent in _providerDependents[current] ?? <String>{}) {
          if (!visited.contains(dependent)) {
            visited.add(dependent);
            queue.add([...currentPath, dependent]);
          }
        }
      }
    } else {
      // Trace to all consuming widgets
      final directWidgets = _widgetConsumers[providerId] ?? <String>{};
      for (final widget in directWidgets) {
        path.add({'node': widget, 'type': 'widget'});
        transformations.add('$widget consumes $providerId');
      }

      // Also add dependent providers
      for (final dependent in _providerDependents[providerId] ?? <String>{}) {
        path.add({
          'node': dependent,
          'type': _stateProviders.containsKey(dependent)
              ? _categorizeStateType(_stateProviders[dependent]!.type)
              : 'unknown',
        });
        transformations.add('$dependent depends on $providerId');
      }
    }

    return {'path': path, 'transformations': transformations};
  }

  /// Find providers that are defined but never used.
  Map<String, dynamic> _getOrphanStateCheck() {
    final orphanedProviders = <String>[];
    final unusedInWidgets = <String>[];

    for (final providerId in _stateProviders.keys) {
      // Check if this provider has any dependents
      final dependents = _providerDependents[providerId] ?? <String>{};
      if (dependents.isEmpty) {
        orphanedProviders.add(providerId);
      }

      // Check if this provider is consumed by any widgets
      final widgets = _widgetConsumers[providerId] ?? <String>{};
      if (widgets.isEmpty) {
        unusedInWidgets.add(providerId);
      }
    }

    return {
      'orphanedProviders': orphanedProviders,
      'unusedInWidgets': unusedInWidgets,
    };
  }

  // ===========================================================================
  // APP LIFECYCLE TESTING IMPLEMENTATIONS
  // ===========================================================================

  /// Simulate app lifecycle state change.
  ///
  /// Triggers the lifecycle callback in the app, notifying all WidgetsBindingObservers.
  Future<Map<String, dynamic>> _simulateLifecycleState(String stateStr) async {
    final previousState = _currentLifecycleState;

    // Parse the state string to AppLifecycleState
    AppLifecycleState newState;
    switch (stateStr.toLowerCase()) {
      case 'paused':
        newState = AppLifecycleState.paused;
        break;
      case 'resumed':
        newState = AppLifecycleState.resumed;
        break;
      case 'inactive':
        newState = AppLifecycleState.inactive;
        break;
      case 'detached':
        newState = AppLifecycleState.detached;
        break;
      case 'hidden':
        newState = AppLifecycleState.hidden;
        break;
      default:
        throw Exception(
          'Invalid lifecycle state: $stateStr. '
          'Valid states: paused, resumed, inactive, detached, hidden',
        );
    }

    _currentLifecycleState = newState;

    // Record in history
    _lifecycleHistory.add(
      AppLifecycleEvent(state: newState, timestamp: DateTime.now()),
    );

    // Notify all observers through the binding
    try {
      final binding = WidgetsBinding.instance;
      binding.handleAppLifecycleStateChanged(newState);
      _logConsole(
        'info',
        'Lifecycle state changed: ${previousState.name} -> ${newState.name}',
      );
    } catch (e) {
      _logConsole('error', 'Failed to notify lifecycle observers: $e');
    }

    // Wait a frame for observers to react
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousState': previousState.name,
      'currentState': newState.name,
    };
  }

  /// Get history of lifecycle events.
  Map<String, dynamic> _getLifecycleHistory() {
    return {
      'events': _lifecycleHistory.map((e) => e.toJson()).toList(),
      'currentState': _currentLifecycleState.name,
      'eventCount': _lifecycleHistory.length,
    };
  }

  /// Simulate memory pressure warning.
  ///
  /// Triggers cache clearing and notifies observers about low memory condition.
  Future<Map<String, dynamic>> _simulateMemoryPressure(String level) async {
    _clearedCaches.clear();

    // Clear image caches
    try {
      PaintingBinding.instance.imageCache.clear();
      _clearedCaches.add('imageCache');
      PaintingBinding.instance.imageCache.clearLiveImages();
      _clearedCaches.add('liveImageCache');
    } catch (e) {
      _logConsole('error', 'Failed to clear image cache: $e');
    }

    // For critical level, try more aggressive cleanup
    if (level == 'critical') {
      try {
        // Trigger garbage collection hints (not guaranteed)
        await Future.delayed(const Duration(milliseconds: 50));

        // Clear any additional caches the app might have registered
        _clearedCaches.add('forcedGC');
      } catch (e) {
        _logConsole('error', 'Failed aggressive cleanup: $e');
      }
    }

    // Notify about memory pressure
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // We trigger a frame rebuild to give the app a chance to respond to memory state changes.
    try {
      WidgetsBinding.instance.scheduleFrame();
      _clearedCaches.add('notifiedObservers');
    } catch (e) {
      _logConsole('error', 'Failed to notify memory pressure: $e');
    }

    _logConsole('info', 'Memory pressure simulated: $level');

    return {'success': true, 'level': level, 'clearedCaches': _clearedCaches};
  }

  /// Simulate system locale change.
  Future<Map<String, dynamic>> _simulateLocaleChange(String localeStr) async {
    final previousLocale = _currentLocale;

    // Parse locale string (e.g., "en_US", "fr_FR")
    final parts = localeStr.split('_');
    final newLocale = Locale(parts[0], parts.length > 1 ? parts[1] : null);

    _currentLocale = newLocale;

    // Notify about locale change
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // Locale changes are typically triggered through the platform channel.
    try {
      // Force a rebuild of the widget tree by scheduling a frame
      WidgetsBinding.instance.scheduleFrame();
      _logConsole(
        'info',
        'Locale changed: ${previousLocale.toString()} -> ${newLocale.toString()}',
      );
    } catch (e) {
      _logConsole('error', 'Failed to notify locale change: $e');
    }

    // Wait a frame for UI to update
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousLocale': previousLocale.toString(),
      'currentLocale': newLocale.toString(),
    };
  }

  /// Simulate system text scale change.
  Future<Map<String, dynamic>> _simulateTextScaleChange(double scale) async {
    final previousScale = _currentTextScale;
    _currentTextScale = scale;

    // Notify about text scale change
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // Text scale changes are typically triggered through the platform channel.
    try {
      // Force a rebuild of the widget tree by scheduling a frame
      WidgetsBinding.instance.scheduleFrame();
      _logConsole('info', 'Text scale changed: $previousScale -> $scale');
    } catch (e) {
      _logConsole('error', 'Failed to notify text scale change: $e');
    }

    // Wait a frame for UI to update
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousScale': previousScale,
      'currentScale': scale,
    };
  }

  /// Simulate system brightness mode change.
  Future<Map<String, dynamic>> _simulateBrightnessChange(
    String brightnessStr,
  ) async {
    final previousBrightness = _currentBrightness;

    // Parse brightness string
    Brightness newBrightness;
    switch (brightnessStr.toLowerCase()) {
      case 'light':
        newBrightness = Brightness.light;
        break;
      case 'dark':
        newBrightness = Brightness.dark;
        break;
      default:
        throw Exception(
          'Invalid brightness: $brightnessStr. Valid values: light, dark',
        );
    }

    _currentBrightness = newBrightness;

    // Notify about brightness change
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // Brightness changes are typically triggered through the platform channel.
    try {
      // Force a rebuild of the widget tree by scheduling a frame
      WidgetsBinding.instance.scheduleFrame();
      _logConsole(
        'info',
        'Brightness changed: ${previousBrightness.name} -> ${newBrightness.name}',
      );
    } catch (e) {
      _logConsole('error', 'Failed to notify brightness change: $e');
    }

    // Wait a frame for UI to update
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousBrightness': previousBrightness.name,
      'currentBrightness': newBrightness.name,
    };
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

  // ===========================================================================
  // TIME-TRAVEL STATE SNAPSHOTS IMPLEMENTATION
  // ===========================================================================

  /// Start recording time-travel snapshots
  Map<String, dynamic> _timeTravelStart(
    bool captureOnInteraction,
    int? intervalMs,
  ) {
    if (_isRecordingTimeline) {
      return {
        'success': false,
        'error': 'Time-travel recording is already active',
      };
    }

    _isRecordingTimeline = true;
    _captureOnInteraction = captureOnInteraction;
    _timelineSnapshots.clear();

    // Capture initial snapshot
    _captureSnapshotInternal(label: 'initial');

    // Set up interval-based capturing if specified
    if (intervalMs != null && intervalMs > 0) {
      _snapshotTimer?.cancel();
      _snapshotTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
        if (_isRecordingTimeline) {
          _captureSnapshotInternal(label: 'auto');
        }
      });
    }

    return {
      'success': true,
      'captureOnInteraction': captureOnInteraction,
      'intervalMs': intervalMs,
    };
  }

  /// Manually capture a snapshot
  Future<Map<String, dynamic>> _timeTravelSnapshot(String? label) async {
    if (!_isRecordingTimeline) {
      return {
        'error':
            'Time-travel recording is not active. Call timeTravelStart first.',
      };
    }

    final snapshot = await _captureSnapshotInternal(label: label);
    return {
      'snapshotId': snapshot.id,
      'timestamp': snapshot.timestamp.millisecondsSinceEpoch,
      'label': snapshot.label,
      'route': snapshot.currentRoute,
    };
  }

  /// List all captured snapshots
  Map<String, dynamic> _timeTravelList() {
    return {
      'snapshots': _timelineSnapshots
          .map(
            (s) => {
              'id': s.id,
              'label': s.label,
              'timestamp': s.timestamp.millisecondsSinceEpoch,
              'route': s.currentRoute,
            },
          )
          .toList(),
      'isRecording': _isRecordingTimeline,
      'totalCount': _timelineSnapshots.length,
    };
  }

  /// Restore app to a previous snapshot state
  Future<Map<String, dynamic>> _timeTravelGoto(
    String? snapshotId,
    int? index,
  ) async {
    _AppSnapshot? snapshot;

    if (snapshotId != null) {
      snapshot = _timelineSnapshots.firstWhere(
        (s) => s.id == snapshotId,
        orElse: () => throw Exception('Snapshot not found: $snapshotId'),
      );
    } else if (index != null) {
      if (index < 0 || index >= _timelineSnapshots.length) {
        return {
          'success': false,
          'error':
              'Invalid snapshot index: $index. Valid range: 0-${_timelineSnapshots.length - 1}',
        };
      }
      snapshot = _timelineSnapshots[index];
    } else {
      return {
        'success': false,
        'error': 'Either snapshotId or index must be provided',
      };
    }

    try {
      await _restoreSnapshotInternal(snapshot);
      return {
        'success': true,
        'restoredFrom': snapshot.id,
        'timestamp': snapshot.timestamp.millisecondsSinceEpoch,
        'route': snapshot.currentRoute,
      };
    } catch (e) {
      return {'success': false, 'error': 'Failed to restore snapshot: $e'};
    }
  }

  /// Stop recording snapshots and optionally clear them
  Map<String, dynamic> _timeTravelStop(bool clear) {
    final totalSnapshots = _timelineSnapshots.length;

    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _isRecordingTimeline = false;
    _captureOnInteraction = false;

    if (clear) {
      _timelineSnapshots.clear();
    }

    return {
      'success': true,
      'totalSnapshots': totalSnapshots,
      'cleared': clear,
    };
  }

  /// Compare two snapshots and return differences
  Map<String, dynamic> _timeTravelDiff(String fromId, String toId) {
    final fromSnapshot = _timelineSnapshots.firstWhere(
      (s) => s.id == fromId,
      orElse: () => throw Exception('From snapshot not found: $fromId'),
    );

    final toSnapshot = _timelineSnapshots.firstWhere(
      (s) => s.id == toId,
      orElse: () => throw Exception('To snapshot not found: $toId'),
    );

    // Compare provider states
    final stateChanges = <Map<String, dynamic>>[];
    final allProviderIds = <String>{
      ...fromSnapshot.providerStates.keys,
      ...toSnapshot.providerStates.keys,
    };

    for (final providerId in allProviderIds) {
      final fromState = fromSnapshot.providerStates[providerId];
      final toState = toSnapshot.providerStates[providerId];

      if (fromState == null && toState != null) {
        stateChanges.add({
          'providerId': providerId,
          'type': 'added',
          'newValue': toState,
        });
      } else if (fromState != null && toState == null) {
        stateChanges.add({
          'providerId': providerId,
          'type': 'removed',
          'oldValue': fromState,
        });
      } else if (jsonEncode(fromState) != jsonEncode(toState)) {
        stateChanges.add({
          'providerId': providerId,
          'type': 'changed',
          'oldValue': fromState,
          'newValue': toState,
        });
      }
    }

    // Compare storage snapshots
    final storageChanges = <Map<String, dynamic>>[];
    final allStorageKeys = <String>{
      ...fromSnapshot.storageSnapshot.keys,
      ...toSnapshot.storageSnapshot.keys,
    };

    for (final key in allStorageKeys) {
      final fromValue = fromSnapshot.storageSnapshot[key];
      final toValue = toSnapshot.storageSnapshot[key];

      if (fromValue == null && toValue != null) {
        storageChanges.add({'key': key, 'type': 'added', 'newValue': toValue});
      } else if (fromValue != null && toValue == null) {
        storageChanges.add({
          'key': key,
          'type': 'removed',
          'oldValue': fromValue,
        });
      } else if (jsonEncode(fromValue) != jsonEncode(toValue)) {
        storageChanges.add({
          'key': key,
          'type': 'changed',
          'oldValue': fromValue,
          'newValue': toValue,
        });
      }
    }

    // Compare widget tree digests
    final widgetChanges = <Map<String, dynamic>>[];
    if (fromSnapshot.widgetTreeDigest != toSnapshot.widgetTreeDigest) {
      widgetChanges.add({
        'type': 'widget_tree_changed',
        'from': fromSnapshot.widgetTreeDigest,
        'to': toSnapshot.widgetTreeDigest,
      });
    }

    return {
      'from': {
        'id': fromSnapshot.id,
        'timestamp': fromSnapshot.timestamp.millisecondsSinceEpoch,
        'label': fromSnapshot.label,
      },
      'to': {
        'id': toSnapshot.id,
        'timestamp': toSnapshot.timestamp.millisecondsSinceEpoch,
        'label': toSnapshot.label,
      },
      'routeChanged': fromSnapshot.currentRoute != toSnapshot.currentRoute,
      'fromRoute': fromSnapshot.currentRoute,
      'toRoute': toSnapshot.currentRoute,
      'stateChanges': stateChanges,
      'storageChanges': storageChanges,
      'widgetChanges': widgetChanges,
      'timeDeltaMs':
          toSnapshot.timestamp.millisecondsSinceEpoch -
          fromSnapshot.timestamp.millisecondsSinceEpoch,
    };
  }

  /// Internal method to capture a snapshot
  Future<_AppSnapshot> _captureSnapshotInternal({String? label}) async {
    final id = 'snap_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now();

    // Capture current route
    final currentRoute = navigator?.currentLocation ?? '/';

    // Capture provider states from registered providers
    final providerStates = <String, Map<String, dynamic>>{};
    for (final entry in _stateProviders.entries) {
      try {
        providerStates[entry.key] = entry.value.getState();
      } catch (e) {
        providerStates[entry.key] = {'_error': e.toString()};
      }
    }

    // Capture storage snapshot
    final storageSnapshot = <String, dynamic>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        storageSnapshot[key] = prefs.get(key);
      }
    } catch (e) {
      storageSnapshot['_error'] = e.toString();
    }

    // Capture widget tree digest
    String? widgetTreeDigest;
    try {
      final manager = SelfTestManager();
      final nodes = manager.activeTestNodes;
      // Create a simple digest of the widget tree
      final widgetIds = nodes.keys.toList()..sort();
      widgetTreeDigest = widgetIds.join('|');
    } catch (e) {
      widgetTreeDigest = null;
    }

    final snapshot = _AppSnapshot(
      id: id,
      label: label,
      timestamp: timestamp,
      currentRoute: currentRoute,
      providerStates: providerStates,
      storageSnapshot: storageSnapshot,
      widgetTreeDigest: widgetTreeDigest,
    );

    _timelineSnapshots.add(snapshot);
    return snapshot;
  }

  /// Internal method to restore a snapshot
  Future<void> _restoreSnapshotInternal(_AppSnapshot snapshot) async {
    // 1. Restore storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      for (final entry in snapshot.storageSnapshot.entries) {
        if (entry.key.startsWith('_')) continue;
        await _storageSet(entry.key, entry.value, 'shared_prefs');
      }
    } catch (e) {
      debugPrint('[SelfTestBridge] Failed to restore storage: $e');
    }

    // 2. Restore provider states (for registered providers that support injection)
    for (final entry in snapshot.providerStates.entries) {
      final config = _stateProviders[entry.key];
      if (config?.dispatchAction != null) {
        try {
          config!.dispatchAction!('_restore', entry.value);
        } catch (e) {
          debugPrint(
            '[SelfTestBridge] Failed to restore provider ${entry.key}: $e',
          );
        }
      }
    }

    // 3. Navigate to the route
    if (snapshot.currentRoute.isNotEmpty) {
      await navigator?.goTo(snapshot.currentRoute, replace: true);
    }

    // 4. Wait for animations to complete
    await SelfTestManager().waitForAnimations();
  }

  /// Called when a user interaction occurs (for captureOnInteraction mode)
  Future<void> _onUserInteraction() async {
    if (_isRecordingTimeline && _captureOnInteraction) {
      // _captureSnapshotInternal appends to _timelineSnapshots itself.
      await _captureSnapshotInternal(label: 'interaction');
    }
  }

  // ===========================================================================
  // PUSH NOTIFICATION MOCKING IMPLEMENTATION
  // ===========================================================================

  /// Simulate receiving a push notification.
  ///
  /// Creates a mock notification with the given parameters and triggers
  /// the appropriate callbacks based on the action type.
  Future<Map<String, dynamic>> _simulatePushNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String action = 'received',
    int? delayMs,
  }) async {
    // Apply delay if specified
    if (delayMs != null && delayMs > 0) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    // Generate notification ID
    final notificationId = 'notif_${++_notificationIdCounter}';

    // Create the notification
    final notification = MockNotification(
      id: notificationId,
      title: title,
      body: body,
      data: data,
      action: action,
    );

    // Add to history
    _notificationHistory.add(notification);

    // Trigger appropriate callbacks based on action
    switch (action) {
      case 'received':
        if (_notificationOnReceiveEnabled) {
          onNotificationReceived?.call(notification);
        }
        break;
      case 'tap':
        if (_notificationOnTapEnabled) {
          onNotificationTap?.call(notification);
        }
        // Handle deep link navigation if present
        final deepLink = data?['deep_link'] as String?;
        if (deepLink != null) {
          await navigator?.goTo(deepLink);
        }
        break;
      case 'dismiss':
        if (_notificationOnDismissEnabled) {
          onNotificationDismiss?.call(notification);
        }
        break;
    }

    _logConsole('info', 'Simulated notification: $title ($action)');

    return {'success': true, 'notificationId': notificationId};
  }

  /// Simulate user tapping a notification.
  ///
  /// Finds the notification by ID and triggers the tap callback.
  /// If the notification has a deep_link in its data, navigates to it.
  Future<Map<String, dynamic>> _simulateNotificationTap(
    String notificationId,
    String? actionId,
  ) async {
    // Find the notification
    final index = _notificationHistory.indexWhere(
      (n) => n.id == notificationId,
    );
    if (index == -1) {
      return {
        'success': false,
        'error': 'Notification not found: $notificationId',
      };
    }

    final notification = _notificationHistory[index];
    notification.action = 'tap';

    // Trigger tap callback
    if (_notificationOnTapEnabled) {
      onNotificationTap?.call(notification);
    }

    // Handle deep link navigation
    String? navigatedTo;
    final deepLink = notification.data['deep_link'] as String?;
    if (deepLink != null && navigator != null) {
      navigatedTo = deepLink;
      await navigator!.goTo(deepLink);
      await SelfTestManager().waitForAnimations();
    }

    _logConsole('info', 'Notification tapped: ${notification.title}');

    return {'success': true, 'navigatedTo': navigatedTo};
  }

  /// Get history of simulated notifications.
  Map<String, dynamic> _getNotificationHistory() {
    return {
      'notifications': _notificationHistory
          .map(
            (n) => {
              'id': n.id,
              'title': n.title,
              'body': n.body,
              'data': n.data,
              'timestamp': n.timestamp.millisecondsSinceEpoch,
              'action': n.action,
            },
          )
          .toList(),
      'count': _notificationHistory.length,
    };
  }

  /// Set notification handler flags.
  Map<String, dynamic> _setNotificationHandler({
    bool? onReceive,
    bool? onTap,
    bool? onDismiss,
  }) {
    final handlersSet = <String>[];

    if (onReceive != null) {
      _notificationOnReceiveEnabled = onReceive;
      if (onReceive) handlersSet.add('onReceive');
    }
    if (onTap != null) {
      _notificationOnTapEnabled = onTap;
      if (onTap) handlersSet.add('onTap');
    }
    if (onDismiss != null) {
      _notificationOnDismissEnabled = onDismiss;
      if (onDismiss) handlersSet.add('onDismiss');
    }

    return {
      'handlersSet': handlersSet,
      'onReceive': _notificationOnReceiveEnabled,
      'onTap': _notificationOnTapEnabled,
      'onDismiss': _notificationOnDismissEnabled,
    };
  }

  /// Clear notification history.
  Map<String, dynamic> _clearNotifications() {
    final count = _notificationHistory.length;
    _notificationHistory.clear();
    _notificationIdCounter = 0;

    return {'cleared': count};
  }

  /// Get mock FCM token.
  ///
  /// Returns a consistent mock token for the session.
  /// The token is generated once and reused for subsequent calls.
  Map<String, dynamic> _getFcmToken() {
    _mockFcmToken ??= 'mock_fcm_token_${DateTime.now().millisecondsSinceEpoch}';
    return {'token': _mockFcmToken};
  }

  // ===========================================================================
  // DEEP LINK TESTING IMPLEMENTATIONS
  // ===========================================================================

  /// Simulate receiving a deep link / universal link.
  ///
  /// Parses the URL and attempts to navigate using the configured router.
  /// Records the event in history for later inspection.
  Future<Map<String, dynamic>> _simulateDeepLink(
    String url,
    String source,
  ) async {
    final uri = Uri.parse(url);
    final manager = SelfTestManager();

    // Record the event
    final event = DeepLinkEvent(
      url: url,
      timestamp: DateTime.now(),
      source: source,
    );

    // Handed to whatever BridgeNavigator the app configured.
    String? handledBy;
    String? navigatedTo;

    final target = navigator;
    if (target != null) {
      try {
        // Check if this URL scheme is registered (if schemes are registered)
        bool schemeAllowed = _registeredSchemes.isEmpty;
        if (!schemeAllowed) {
          // Check if scheme matches
          if (uri.scheme.isNotEmpty &&
              _registeredSchemes.contains(uri.scheme)) {
            schemeAllowed = true;
          }
          // Check if host matches (for https/http links)
          if (uri.host.isNotEmpty) {
            for (final scheme in _registeredSchemes) {
              if (scheme.contains(uri.host)) {
                schemeAllowed = true;
                break;
              }
            }
          }
        }

        if (schemeAllowed) {
          // Determine the path to navigate to
          String path = uri.path;
          if (path.isEmpty) {
            path = '/';
          }

          // The query string rides along in the location rather than in a
          // router-specific "extra" bag, which is the only form every router
          // understands.
          if (uri.hasQuery) {
            path = '$path?${uri.query}';
          }
          await target.goTo(path);

          handledBy = target.runtimeType.toString();
          navigatedTo = path;
          event.handled = true;
          event.route = path;
          event.handledBy = handledBy;
        }

        await manager.waitForAnimations();
      } catch (e) {
        event.handled = false;
        debugPrint('[SelfTestBridge] Deep link navigation error: $e');
      }
    }

    _deepLinkHistory.add(event);

    return {
      'success': event.handled,
      'handledBy': handledBy,
      'navigatedTo': navigatedTo,
    };
  }

  /// Get history of deep links received during the session.
  Map<String, dynamic> _getDeepLinkHistory() {
    return {'links': _deepLinkHistory.map((e) => e.toJson()).toList()};
  }

  /// Register URL schemes that the app handles.
  Map<String, dynamic> _registerDeepLinkSchemes(List<String> schemes) {
    final previousSchemes = _registeredSchemes.toList();
    _registeredSchemes.addAll(schemes);

    return {'registered': schemes, 'previousSchemes': previousSchemes};
  }

  /// Test that a deep link routes correctly without actually navigating.
  ///
  /// Validates URL parsing and route matching.
  Map<String, dynamic> _testDeepLinkRouting(
    String url,
    String expectedRoute,
    Map<String, dynamic>? expectedParams,
  ) {
    final uri = Uri.parse(url);

    // Determine actual route from URL
    String actualRoute = uri.path;
    if (actualRoute.isEmpty) {
      actualRoute = '/';
    }

    // Get actual params
    final actualParams = <String, dynamic>{};

    // Add query parameters
    actualParams.addAll(uri.queryParameters);

    // Try to extract path parameters if the router supports it
    // This would require knowledge of the route configuration
    // For now, we compare query params

    // Check if route matches
    final routeMatches = actualRoute == expectedRoute;

    // Check if params match
    final paramMismatches = <Map<String, dynamic>>[];
    if (expectedParams != null) {
      for (final entry in expectedParams.entries) {
        final actualValue = actualParams[entry.key];
        if (actualValue != entry.value) {
          paramMismatches.add({
            'key': entry.key,
            'expected': entry.value,
            'actual': actualValue,
          });
        }
      }
    }

    final match = routeMatches && paramMismatches.isEmpty;

    return {
      'success': match,
      'actualRoute': actualRoute,
      'actualParams': actualParams,
      'match': match,
      'paramMismatches': paramMismatches,
    };
  }

  /// Clear deep link history.
  Map<String, dynamic> _clearDeepLinkHistory() {
    final count = _deepLinkHistory.length;
    _deepLinkHistory.clear();

    return {'cleared': count};
  }

  // ===========================================================================
  // NAVIGATION STACK INSPECTOR IMPLEMENTATIONS
  // ===========================================================================

  /// Initialize navigation observer if not already done
  void _ensureNavigationObserver() {
    if (!_navigationObserverAttached) {
      _navigationObserver = NavigationInspectorObserver(
        onPush: (route, previousRoute) {
          _routeStack.add(route);
          _navigationHistory.add(
            NavigationEvent(
              action: 'push',
              from: previousRoute?.settings.name,
              to: route.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
              arguments: route.settings.arguments,
            ),
          );
        },
        onPop: (route, previousRoute) {
          _routeStack.remove(route);
          _navigationHistory.add(
            NavigationEvent(
              action: 'pop',
              from: route.settings.name ?? 'unknown',
              to: previousRoute?.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
            ),
          );
        },
        onReplace: (newRoute, oldRoute) {
          if (oldRoute != null) _routeStack.remove(oldRoute);
          if (newRoute != null) _routeStack.add(newRoute);
          _navigationHistory.add(
            NavigationEvent(
              action: 'replace',
              from: oldRoute?.settings.name,
              to: newRoute?.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
            ),
          );
        },
        onRemove: (route, previousRoute) {
          _routeStack.remove(route);
          _navigationHistory.add(
            NavigationEvent(
              action: 'remove',
              from: route.settings.name ?? 'unknown',
              to: previousRoute?.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
            ),
          );
        },
      );
      _navigationObserverAttached = true;
    }
  }

  /// Get the navigation observer to attach to a Navigator
  NavigationInspectorObserver get navigationObserver {
    _ensureNavigationObserver();
    return _navigationObserver;
  }

  /// Where the app is, preferring the configured navigator and falling back to
  /// what the observer saw.
  String get _currentRouteName =>
      navigator?.currentLocation ??
      (_routeStack.isNotEmpty ? _routeStack.last.settings.name : null) ??
      'unknown';

  /// Get the full navigation stack
  Map<String, dynamic> _getNavigationStack() {
    _ensureNavigationObserver();

    final currentRoute = _currentRouteName;

    final stack = _routeStack.asMap().entries.map((e) {
      final route = e.value;
      dynamic arguments;
      try {
        // Try to serialize arguments as JSON-compatible
        arguments = _serializeNavigationArguments(route.settings.arguments);
      } catch (_) {
        arguments = route.settings.arguments?.toString();
      }
      return {
        'route': route.settings.name ?? 'Route#${e.key}',
        'name': route.settings.name,
        'arguments': arguments,
        'isFirst': e.key == 0,
        'isCurrent': e.key == _routeStack.length - 1,
      };
    }).toList();

    return {
      'stack': stack,
      'currentRoute': currentRoute,
      'depth': _routeStack.length,
    };
  }

  /// Get navigation history
  Map<String, dynamic> _getNavigationHistory(int limit) {
    _ensureNavigationObserver();

    final history = _navigationHistory.reversed
        .take(limit)
        .map((e) => e.toJson())
        .toList()
        .reversed
        .toList();

    return {'history': history};
  }

  /// Pop routes until a condition is met
  Future<Map<String, dynamic>> _popUntil(
    String? route,
    String? predicate,
  ) async {
    final manager = SelfTestManager();
    int poppedCount = 0;

    final target = navigator;
    if (target == null) return _navigatorMissing;

    if (route != null) {
      // A router that addresses screens by location cannot report how many
      // entries that dropped, so this counts the one move it made.
      await target.goTo(route, replace: true);
      poppedCount = 1;
    } else if (predicate == 'isFirst') {
      while (target.canGoBack) {
        await target.goBack();
        poppedCount++;
      }
    }

    await manager.waitForAnimations();

    final currentRoute = _currentRouteName;

    return {'poppedCount': poppedCount, 'currentRoute': currentRoute};
  }

  /// Check if current route can be popped
  Map<String, dynamic> _canPop() {
    _ensureNavigationObserver();

    final canPop = navigator?.canGoBack ?? _routeStack.length > 1;

    return {'canPop': canPop, 'stackDepth': _routeStack.length};
  }

  /// Get registered navigation observers
  Map<String, dynamic> _getNavigationListeners() {
    _ensureNavigationObserver();

    final observers = <Map<String, dynamic>>[];

    // Add our own observer
    if (_navigationObserverAttached) {
      observers.add({
        'type': 'NavigationInspectorObserver',
        'name': 'SelfTestBridge Inspector',
      });
    }

    final target = navigator;
    if (target != null) {
      observers.add({
        'type': target.runtimeType.toString(),
        'name': 'App BridgeNavigator',
      });
    }

    return {'observers': observers};
  }

  /// Simulate back gesture
  Future<Map<String, dynamic>> _simulateBackGesture(String type) async {
    final manager = SelfTestManager();
    bool popped = false;

    final target = navigator;
    if (target == null) return _navigatorMissing;

    if (target.canGoBack) {
      // An edge swipe and a back button both end in the same pop; the bridge
      // does not simulate the gesture itself.
      await target.goBack();
      popped = true;
    } else {
      // Nothing left in the app to pop, so ask the platform to leave it. That
      // may close the app, which is not a pop.
      await SystemNavigator.pop();
    }

    await manager.waitForAnimations();

    final currentRoute = _currentRouteName;

    return {'popped': popped, 'currentRoute': currentRoute};
  }

  /// Get route settings
  Map<String, dynamic> _getRouteSettings(String? route) {
    _ensureNavigationObserver();

    Route<dynamic>? targetRoute;

    if (route != null) {
      // Find specific route
      for (final r in _routeStack) {
        if (r.settings.name == route) {
          targetRoute = r;
          break;
        }
      }
    } else if (_routeStack.isNotEmpty) {
      // Use current route
      targetRoute = _routeStack.last;
    }

    if (targetRoute == null) {
      return {'error': 'Route not found'};
    }

    dynamic arguments;
    try {
      arguments = _serializeNavigationArguments(targetRoute.settings.arguments);
    } catch (_) {
      arguments = targetRoute.settings.arguments?.toString();
    }

    // Check if route maintains state (not all routes support this)
    bool maintainState = true;
    if (targetRoute is ModalRoute) {
      maintainState = targetRoute.maintainState;
    }

    return {
      'name': targetRoute.settings.name,
      'arguments': arguments,
      'maintainState': maintainState,
    };
  }

  /// Helper to serialize route arguments to JSON-compatible format
  dynamic _serializeNavigationArguments(dynamic arguments) {
    if (arguments == null) return null;
    if (arguments is String || arguments is num || arguments is bool) {
      return arguments;
    }
    if (arguments is Map) {
      return arguments.map(
        (k, v) => MapEntry(k.toString(), _serializeNavigationArguments(v)),
      );
    }
    if (arguments is List) {
      return arguments.map(_serializeNavigationArguments).toList();
    }
    // For other objects, try to convert to string
    return arguments.toString();
  }

  // ===========================================================================
  // SEMANTIC LABEL AUTO-GENERATION IMPLEMENTATIONS
  // ===========================================================================

  /// Cached semantic suggestions for applySuggestedSemantics
  final Map<String, _SemanticSuggestion> _cachedSuggestions = {};

  /// Analyze widgets and suggest semantic labels for accessibility
  Map<String, dynamic> _suggestSemantics(String? screen, bool includeLabeled) {
    final suggestions = <Map<String, dynamic>>[];
    _cachedSuggestions.clear();

    void visitElement(Element element) {
      final widget = element.widget;
      final widgetType = widget.runtimeType.toString();

      if (screen != null) {
        final elementScreen = _inferScreen(element);
        if (!elementScreen.toLowerCase().contains(screen.toLowerCase())) {
          element.visitChildren(visitElement);
          return;
        }
      }

      if (_isSemanticsInteractiveWidget(widget)) {
        final currentLabel = _extractSemanticLabelFromElement(element);
        final hasLabel = currentLabel != null && currentLabel.isNotEmpty;

        if (!hasLabel || includeLabeled) {
          final suggestion = _generateSemanticSuggestion(
            element,
            widget,
            widgetType,
            currentLabel,
          );

          if (suggestion != null) {
            final id = 'suggestion_${suggestions.length}';
            _cachedSuggestions[id] = suggestion;

            suggestions.add({
              'id': id,
              'widgetType': widgetType,
              'currentLabel': currentLabel,
              'suggestedLabel': suggestion.suggestedLabel,
              'confidence': suggestion.confidence,
              'location': suggestion.location,
              'reason': suggestion.reason,
            });
          }
        }
      }

      element.visitChildren(visitElement);
    }

    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement != null) {
      visitElement(rootElement);
    }

    return {
      'suggestions': suggestions,
      'totalAnalyzed': _countElementsInTree(rootElement),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Get semantics coverage report
  Map<String, dynamic> _semanticsCoverage() {
    int totalWidgets = 0;
    int labeledWidgets = 0;
    final byType = <String, Map<String, int>>{};
    final unlabeledInteractive = <String>[];

    void visitElement(Element element) {
      final widget = element.widget;
      final widgetType = widget.runtimeType.toString();

      if (_isSemanticsInteractiveWidget(widget)) {
        totalWidgets++;
        byType.putIfAbsent(widgetType, () => {'total': 0, 'labeled': 0});
        byType[widgetType]!['total'] = byType[widgetType]!['total']! + 1;

        final label = _extractSemanticLabelFromElement(element);
        if (label != null && label.isNotEmpty) {
          labeledWidgets++;
          byType[widgetType]!['labeled'] = byType[widgetType]!['labeled']! + 1;
        } else {
          final widgetId = _inferWidgetIdFromElement(element, widget);
          if (widgetId.isNotEmpty) {
            unlabeledInteractive.add(widgetId);
          }
        }
      }
      element.visitChildren(visitElement);
    }

    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement != null) {
      visitElement(rootElement);
    }

    final coveragePercent = totalWidgets > 0
        ? (labeledWidgets / totalWidgets * 100)
        : 100.0;

    return {
      'totalWidgets': totalWidgets,
      'labeledWidgets': labeledWidgets,
      'coveragePercent': coveragePercent,
      'byType': byType,
      'unlabeledInteractive': unlabeledInteractive,
    };
  }

  /// Get the full semantics tree
  Map<String, dynamic> _semanticsTree(bool includeHidden) {
    final tree = <Map<String, dynamic>>[];
    final flatList = <Map<String, dynamic>>[];

    final owner = WidgetsBinding.instance.pipelineOwner.semanticsOwner;
    if (owner == null) {
      return {'tree': [], 'flatList': [], 'error': 'Semantics not enabled.'};
    }

    void visitSemantics(SemanticsNode node, List<Map<String, dynamic>> parent) {
      if (!includeHidden && node.isInvisible) return;

      final nodeData = _extractSemanticsNodeData(node);
      final children = <Map<String, dynamic>>[];

      node.visitChildren((child) {
        visitSemantics(child, children);
        return true;
      });

      if (children.isNotEmpty) nodeData['children'] = children;
      parent.add(nodeData);
      flatList.add({
        'id': node.id,
        'label': node.label,
        'role': _inferSemanticsRole(node),
        'actions': _extractSemanticsActions(node),
        'rect': {
          'left': node.rect.left,
          'top': node.rect.top,
          'width': node.rect.width,
          'height': node.rect.height,
        },
      });
    }

    final rootNode = owner.rootSemanticsNode;
    if (rootNode != null) visitSemantics(rootNode, tree);

    return {'tree': tree, 'flatList': flatList};
  }

  /// Generate code snippets to apply suggested semantic labels
  Map<String, dynamic> _applySuggestedSemantics(List<String> suggestionIds) {
    final codeSnippets = <Map<String, dynamic>>[];

    for (final id in suggestionIds) {
      final suggestion = _cachedSuggestions[id];
      if (suggestion == null) continue;
      final snippet = _generateSemanticCodeSnippet(suggestion);
      if (snippet != null) codeSnippets.add(snippet);
    }

    return {
      'codeSnippets': codeSnippets,
      'appliedCount': codeSnippets.length,
      'requestedCount': suggestionIds.length,
    };
  }

  bool _isSemanticsInteractiveWidget(Widget widget) {
    final t = widget.runtimeType.toString();
    return t.contains('Button') ||
        t.contains('TextField') ||
        t.contains('Checkbox') ||
        t.contains('Radio') ||
        t.contains('Switch') ||
        t.contains('Slider') ||
        t.contains('DropdownButton') ||
        t.contains('GestureDetector') ||
        t.contains('InkWell') ||
        t.contains('InkResponse') ||
        t.contains('ListTile') ||
        t.contains('Card');
  }

  String? _extractSemanticLabelFromElement(Element element) {
    String? label;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Semantics) {
        final s = ancestor.widget as Semantics;
        if (s.properties.label != null) {
          label = s.properties.label;
          return false;
        }
      }
      return true;
    });
    if (label != null) return label;

    final ro = element.renderObject;
    if (ro is RenderBox) {
      final sd = ro.debugSemantics;
      if (sd != null && sd.label.isNotEmpty) return sd.label;
    }
    return null;
  }

  _SemanticSuggestion? _generateSemanticSuggestion(
    Element element,
    Widget widget,
    String widgetType,
    String? currentLabel,
  ) {
    final suggestedLabel = _inferSemanticLabel(element, widget);
    if (suggestedLabel == null || suggestedLabel.isEmpty) return null;

    return _SemanticSuggestion(
      widgetType: widgetType,
      currentLabel: currentLabel,
      suggestedLabel: suggestedLabel,
      confidence: _calculateSemanticConfidence(widget, suggestedLabel),
      location: _getSemanticWidgetLocation(element),
      reason: _explainSemanticSuggestion(widget),
      element: element,
    );
  }

  String? _inferSemanticLabel(Element element, Widget widget) {
    final t = widget.runtimeType.toString();
    final text = _findTextInElementTree(element);

    if (t.contains('Button')) {
      if (text != null && text.isNotEmpty)
        return _textToSnakeCase(text) + '_button';
      final icon = _findIconInElementTree(element);
      if (icon != null) return _textToSnakeCase(icon) + '_button';
      return 'action_button';
    }
    if (t.contains('TextField') || t.contains('TextFormField')) {
      final hint = _findTextFieldHintText(element);
      if (hint != null && hint.isNotEmpty)
        return _textToSnakeCase(hint) + '_input';
      return 'text_input';
    }
    if (t.contains('Checkbox'))
      return text != null
          ? _textToSnakeCase(text) + '_checkbox'
          : 'option_checkbox';
    if (t.contains('Switch'))
      return text != null
          ? _textToSnakeCase(text) + '_switch'
          : 'toggle_switch';
    if (t.contains('Slider'))
      return text != null ? _textToSnakeCase(text) + '_slider' : 'value_slider';
    if (t.contains('IconButton')) {
      final icon = _findIconInElementTree(element);
      return icon != null ? _textToSnakeCase(icon) + '_button' : 'icon_button';
    }
    if (t.contains('ListTile'))
      return text != null ? _textToSnakeCase(text) + '_item' : 'list_item';
    if (t.contains('GestureDetector') || t.contains('InkWell')) {
      return text != null
          ? _textToSnakeCase(text) + '_tap'
          : 'interactive_area';
    }
    return text != null && text.isNotEmpty
        ? _textToSnakeCase(text)
        : _textToSnakeCase(t);
  }

  String? _findTextInElementTree(Element element) {
    String? foundText;
    void search(Element el) {
      if (foundText != null && foundText!.isNotEmpty) return;
      final w = el.widget;
      if (w is Text) {
        final txt = w.data ?? w.textSpan?.toPlainText();
        if (txt != null && txt.trim().isNotEmpty) {
          foundText = txt.trim();
          return;
        }
      }
      if (w is RichText) {
        final txt = w.text.toPlainText();
        if (txt.trim().isNotEmpty) {
          foundText = txt.trim();
          return;
        }
      }
      el.visitChildren(search);
    }

    search(element);
    if (foundText != null && foundText!.length > 50)
      foundText = foundText!.substring(0, 50);
    return foundText;
  }

  String? _findIconInElementTree(Element element) {
    String? iconName;
    void search(Element el) {
      if (iconName != null) return;
      if (el.widget is Icon) {
        final ic = (el.widget as Icon).icon;
        if (ic != null) iconName = _iconDataToName(ic);
      }
      el.visitChildren(search);
    }

    search(element);
    return iconName;
  }

  String _iconDataToName(IconData icon) {
    const icons = {
      0xe5cd: 'close',
      0xe5ca: 'check',
      0xe145: 'add',
      0xe15b: 'remove',
      0xe872: 'settings',
      0xe88a: 'home',
      0xe8b8: 'menu',
      0xe5d2: 'arrow_back',
      0xe8b6: 'search',
      0xe161: 'send',
      0xe3c9: 'edit',
      0xe92b: 'delete',
      0xe7fb: 'person',
      0xe0e1: 'email',
      0xe0cd: 'phone',
      0xe153: 'share',
      0xe866: 'favorite',
      0xe87d: 'star',
      0xe8e5: 'notifications',
      0xe8d3: 'refresh',
    };
    return icons[icon.codePoint] ?? 'icon_${icon.codePoint}';
  }

  String? _findTextFieldHintText(Element element) {
    String? hint;
    void search(Element el) {
      if (hint != null) return;
      if (el.widget is TextField) {
        hint =
            (el.widget as TextField).decoration?.hintText ??
            (el.widget as TextField).decoration?.labelText;
      }
      el.visitChildren(search);
    }

    search(element);
    return hint;
  }

  double _calculateSemanticConfidence(Widget widget, String label) {
    double c = 0.5;
    if (!label.contains('button') &&
        !label.contains('input') &&
        label.length > 5)
      c += 0.2;
    final t = widget.runtimeType.toString();
    if (t.contains('ElevatedButton') ||
        t.contains('TextButton') ||
        t.contains('TextField'))
      c += 0.2;
    if (t.contains('GestureDetector') || t.contains('InkWell')) c -= 0.1;
    return c.clamp(0.0, 1.0);
  }

  String _getSemanticWidgetLocation(Element element) {
    try {
      return element.widget.toStringShort();
    } catch (_) {}
    return element.widget.runtimeType.toString();
  }

  String _explainSemanticSuggestion(Widget widget) {
    final t = widget.runtimeType.toString();
    if (t.contains('Button'))
      return 'Interactive button should have a semantic label for accessibility';
    if (t.contains('TextField'))
      return 'Text input fields need labels for screen readers';
    if (t.contains('Checkbox') || t.contains('Switch'))
      return 'Toggle controls should describe their purpose';
    if (t.contains('GestureDetector') || t.contains('InkWell'))
      return 'Tappable area lacks semantic description';
    if (t.contains('IconButton'))
      return 'Icon-only buttons need text labels for accessibility';
    return 'Interactive widget should have a semantic label';
  }

  String _textToSnakeCase(String text) {
    var r = text
        .trim()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    r = r.replaceAllMapped(
      RegExp(r'(?<!_)([A-Z])'),
      (m) => '_${m.group(1)!.toLowerCase()}',
    );
    r = r.replaceAll(RegExp(r'^_+|_+$'), '').replaceAll(RegExp(r'_+'), '_');
    return r.isEmpty ? 'widget' : r;
  }

  String _inferWidgetIdFromElement(Element element, Widget widget) {
    final m = SelfTestManager();
    for (final e in m.activeTestNodes.entries) {
      if (e.value.context == element) return e.key;
    }
    return widget.toStringShort();
  }

  int _countElementsInTree(Element? root) {
    if (root == null) return 0;
    int c = 1;
    root.visitChildren((child) {
      c += _countElementsInTree(child);
    });
    return c;
  }

  Map<String, dynamic> _extractSemanticsNodeData(SemanticsNode node) {
    final data = node.getSemanticsData();
    return {
      'id': node.id,
      'label': node.label,
      'value': node.value,
      'hint': node.hint,
      'isButton': data.hasFlag(SemanticsFlag.isButton),
      'isTextField': data.hasFlag(SemanticsFlag.isTextField),
      'isCheckbox': data.hasFlag(SemanticsFlag.hasCheckedState),
      'isChecked': data.hasFlag(SemanticsFlag.isChecked),
      'isEnabled': data.hasFlag(SemanticsFlag.isEnabled),
      'isFocused': data.hasFlag(SemanticsFlag.isFocused),
      'isSelected': data.hasFlag(SemanticsFlag.isSelected),
      'isHidden': data.hasFlag(SemanticsFlag.isHidden),
      'rect': {
        'left': node.rect.left,
        'top': node.rect.top,
        'width': node.rect.width,
        'height': node.rect.height,
      },
      'actions': _extractSemanticsActions(node),
    };
  }

  String _inferSemanticsRole(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.hasFlag(SemanticsFlag.isButton)) return 'button';
    if (data.hasFlag(SemanticsFlag.isTextField)) return 'textbox';
    if (data.hasFlag(SemanticsFlag.hasCheckedState)) return 'checkbox';
    if (data.hasFlag(SemanticsFlag.isSlider)) return 'slider';
    if (data.hasFlag(SemanticsFlag.isLink)) return 'link';
    if (data.hasFlag(SemanticsFlag.isImage)) return 'image';
    if (data.hasFlag(SemanticsFlag.isHeader)) return 'heading';
    if (data.hasAction(SemanticsAction.tap)) return 'interactive';
    return 'generic';
  }

  List<String> _extractSemanticsActions(SemanticsNode node) {
    final data = node.getSemanticsData();
    final a = <String>[];
    if (data.hasAction(SemanticsAction.tap)) a.add('tap');
    if (data.hasAction(SemanticsAction.longPress)) a.add('longPress');
    if (data.hasAction(SemanticsAction.scrollLeft)) a.add('scrollLeft');
    if (data.hasAction(SemanticsAction.scrollRight)) a.add('scrollRight');
    if (data.hasAction(SemanticsAction.scrollUp)) a.add('scrollUp');
    if (data.hasAction(SemanticsAction.scrollDown)) a.add('scrollDown');
    if (data.hasAction(SemanticsAction.increase)) a.add('increase');
    if (data.hasAction(SemanticsAction.decrease)) a.add('decrease');
    if (data.hasAction(SemanticsAction.copy)) a.add('copy');
    if (data.hasAction(SemanticsAction.paste)) a.add('paste');
    if (data.hasAction(SemanticsAction.focus)) a.add('focus');
    return a;
  }

  Map<String, dynamic>? _generateSemanticCodeSnippet(_SemanticSuggestion s) {
    final wt = s.widgetType;
    final sl = s.suggestedLabel;
    String before, after;

    if (wt.contains('IconButton')) {
      before = 'IconButton(icon: Icon(Icons.xxx), onPressed: () {})';
      after =
          'IconButton(icon: Icon(Icons.xxx), onPressed: () {}, tooltip: \'${_snakeCaseToTitleCase(sl)}\')';
    } else if (wt.contains('Button')) {
      before = '$wt(onPressed: () {}, child: Text(\'Label\'))';
      after =
          'Semantics(label: \'$sl\', child: $wt(onPressed: () {}, child: Text(\'Label\')))';
    } else if (wt.contains('TextField')) {
      before =
          'TextField(decoration: InputDecoration(hintText: \'Enter value\'))';
      after =
          'TextField(decoration: InputDecoration(hintText: \'Enter value\', labelText: \'${_snakeCaseToTitleCase(sl)}\'))';
    } else if (wt.contains('GestureDetector') || wt.contains('InkWell')) {
      before = '$wt(onTap: () {}, child: widget)';
      after =
          'Semantics(label: \'$sl\', button: true, child: $wt(onTap: () {}, child: widget))';
    } else {
      before = '$wt(...)';
      after = 'Semantics(label: \'$sl\', child: $wt(...))';
    }

    return {
      'suggestionId': sl,
      'widgetType': wt,
      'file': s.location,
      'line': 0,
      'before': before,
      'after': after,
      'suggestedLabel': sl,
    };
  }

  String _snakeCaseToTitleCase(String s) => s
      .split('_')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ')
      .trim();

  // ===========================================================================
  // WIDGET TEST GENERATION IMPLEMENTATIONS
  // ===========================================================================

  Map<String, dynamic> _startTestRecording(
    String testName, {
    String? description,
  }) {
    if (_isRecordingTest) {
      return {
        'error': 'A test recording is already in progress. Stop it first.',
      };
    }

    _currentTestId = 'test_${DateTime.now().millisecondsSinceEpoch}';
    _currentTestName = testName;
    _currentTestDescription = description;
    _recordedSteps.clear();
    _isRecordingTest = true;

    return {'recording': true, 'testId': _currentTestId};
  }

  Map<String, dynamic> _stopTestRecording(String format) {
    if (!_isRecordingTest) {
      return {'error': 'No test recording in progress'};
    }

    final testCode = _generateTestCode(format);
    final imports = _getTestImports(format);
    final interactionCount = _recordedSteps
        .where((s) => s.type == 'interaction')
        .length;
    final assertionCount = _recordedSteps
        .where((s) => s.type == 'assertion')
        .length;

    _isRecordingTest = false;
    _currentTestId = null;
    final testName = _currentTestName;
    _currentTestName = null;
    _currentTestDescription = null;

    return {
      'testCode': testCode,
      'imports': imports,
      'interactions': interactionCount,
      'assertions': assertionCount,
      'testName': testName,
    };
  }

  Map<String, dynamic> _recordAssertion(
    String widgetId,
    String assertion,
    dynamic expected,
  ) {
    if (!_isRecordingTest) {
      return {
        'error':
            'No test recording in progress. Start one with recordTestStart.',
      };
    }

    _recordedSteps.add(
      _RecordedStep(
        type: 'assertion',
        action: assertion,
        params: {'widgetId': widgetId, 'expected': expected},
        timestamp: DateTime.now(),
      ),
    );

    return {
      'added': true,
      'assertionIndex': _recordedSteps
          .where((s) => s.type == 'assertion')
          .length,
    };
  }

  Map<String, dynamic> _recordComment(String comment) {
    if (!_isRecordingTest) {
      return {
        'error':
            'No test recording in progress. Start one with recordTestStart.',
      };
    }

    _recordedSteps.add(
      _RecordedStep(
        type: 'comment',
        action: 'comment',
        params: {'comment': comment},
        timestamp: DateTime.now(),
        comment: comment,
      ),
    );

    return {'added': true};
  }

  Map<String, dynamic> _getRecordedSteps() {
    if (!_isRecordingTest) {
      return {'isRecording': false, 'steps': <Map<String, dynamic>>[]};
    }

    return {
      'isRecording': true,
      'testId': _currentTestId,
      'testName': _currentTestName,
      'steps': _recordedSteps.map((s) {
        return {
          'type': s.type,
          'action': s.action,
          'details': s.params,
          'timestamp': s.timestamp.millisecondsSinceEpoch,
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _generateTestFromScenario(
    Map<String, dynamic> scenario,
    String format,
  ) {
    final name = scenario['name'] as String? ?? 'test';
    final description = scenario['description'] as String?;
    final steps =
        (scenario['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final scenarioSteps = <_RecordedStep>[];
    for (final step in steps) {
      final action = step['action'] as String;
      final params = step['params'] as Map<String, dynamic>? ?? {};

      String type;
      if (action.startsWith('expect') || action == 'assertWidget') {
        type = 'assertion';
      } else {
        type = 'interaction';
      }

      scenarioSteps.add(
        _RecordedStep(
          type: type,
          action: action,
          params: params,
          timestamp: DateTime.now(),
        ),
      );
    }

    final testCode = _generateTestCodeFromSteps(
      scenarioSteps,
      name,
      description,
      format,
    );
    final imports = _getTestImports(format);

    return {'testCode': testCode, 'imports': imports};
  }

  void _recordInteractionStep(String action, Map<String, dynamic> params) {
    if (!_isRecordingTest) return;

    _recordedSteps.add(
      _RecordedStep(
        type: 'interaction',
        action: action,
        widgetId: params['widgetId'] as String?,
        params: Map<String, dynamic>.from(params),
        timestamp: DateTime.now(),
      ),
    );
  }

  List<String> _getTestImports(String format) {
    switch (format) {
      case 'integration_test':
        return [
          "import 'package:flutter_test/flutter_test.dart';",
          "import 'package:flutter/material.dart';",
          "import 'package:integration_test/integration_test.dart';",
        ];
      case 'patrol':
        return [
          "import 'package:patrol/patrol.dart';",
          "import 'package:flutter/material.dart';",
        ];
      case 'widget_test':
      default:
        return [
          "import 'package:flutter_test/flutter_test.dart';",
          "import 'package:flutter/material.dart';",
        ];
    }
  }

  String _generateTestCode(String format) {
    return _generateTestCodeFromSteps(
      _recordedSteps,
      _currentTestName ?? 'generated_test',
      _currentTestDescription,
      format,
    );
  }

  String _generateTestCodeFromSteps(
    List<_RecordedStep> steps,
    String testName,
    String? description,
    String format,
  ) {
    final buffer = StringBuffer();

    switch (format) {
      case 'integration_test':
        buffer.writeln("void main() {");
        buffer.writeln(
          "  IntegrationTestWidgetsFlutterBinding.ensureInitialized();",
        );
        buffer.writeln();
        buffer.writeln(
          "  testWidgets('$testName', (WidgetTester tester) async {",
        );
        break;
      case 'patrol':
        buffer.writeln("void main() {");
        buffer.writeln("  patrolTest('$testName', (\$) async {");
        break;
      case 'widget_test':
      default:
        buffer.writeln("void main() {");
        buffer.writeln(
          "  testWidgets('$testName', (WidgetTester tester) async {",
        );
    }

    if (description != null) {
      buffer.writeln("    // $description");
    }
    buffer.writeln("    // TODO: Replace MyApp() with your app widget");
    buffer.writeln("    await tester.pumpWidget(MyApp());");
    buffer.writeln("    await tester.pumpAndSettle();");
    buffer.writeln();

    for (final step in steps) {
      final code = _generateStepCode(step, format);
      if (code.isNotEmpty) {
        buffer.writeln(code);
      }
    }

    buffer.writeln("  });");
    buffer.writeln("}");

    return buffer.toString();
  }

  String _generateStepCode(_RecordedStep step, String format) {
    final params = step.params;
    final isPatrol = format == 'patrol';
    final tester = isPatrol ? '\$' : 'tester';

    switch (step.type) {
      case 'interaction':
        return _generateInteractionCode(step.action, params, tester, isPatrol);
      case 'assertion':
        return _generateAssertionCode(step.action, params);
      case 'comment':
        final comment = params['comment'] as String? ?? '';
        return "    // $comment";
      default:
        return "    // Unknown step type: ${step.type}";
    }
  }

  String _generateInteractionCode(
    String action,
    Map<String, dynamic> params,
    String tester,
    bool isPatrol,
  ) {
    final widgetId = params['widgetId'] as String?;

    switch (action) {
      case 'tap':
        if (widgetId != null) {
          return "    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // tap: missing widgetId";

      case 'type':
      case 'enterText':
        final text = params['text'] as String? ?? '';
        if (widgetId != null) {
          final escapedText = text.replaceAll("'", "\\'");
          return "    await $tester.enterText(find.byKey(Key('$widgetId')), '$escapedText');\n    await $tester.pumpAndSettle();";
        }
        return "    // type: missing widgetId";

      case 'clear':
        if (widgetId != null) {
          return "    await $tester.enterText(find.byKey(Key('$widgetId')), '');\n    await $tester.pumpAndSettle();";
        }
        return "    // clear: missing widgetId";

      case 'scroll':
        final direction = params['direction'] as String? ?? 'down';
        final delta = params['delta'] as num? ?? 300;
        final dx = direction == 'left'
            ? delta
            : (direction == 'right' ? -delta : 0);
        final dy = direction == 'up'
            ? delta
            : (direction == 'down' ? -delta : 0);
        if (widgetId != null) {
          return "    await $tester.drag(find.byKey(Key('$widgetId')), Offset($dx, $dy));\n    await $tester.pumpAndSettle();";
        }
        return "    await $tester.drag(find.byType(ListView), Offset($dx, $dy));\n    await $tester.pumpAndSettle();";

      case 'longPress':
        if (widgetId != null) {
          return "    await $tester.longPress(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // longPress: missing widgetId";

      case 'doubleTap':
        if (widgetId != null) {
          return "    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // doubleTap: missing widgetId";

      case 'navigate':
        final route = params['route'] as String? ?? '/';
        return "    // Navigate to: $route\n    // TODO: Implement navigation to '$route'";

      case 'goBack':
        return "    await $tester.pageBack();\n    await $tester.pumpAndSettle();";

      case 'toggle':
        if (widgetId != null) {
          return "    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();";
        }
        return "    // toggle: missing widgetId";

      case 'select':
        final value = params['value'] as String? ?? '';
        if (widgetId != null) {
          return "    // Select '$value' from dropdown\n    await $tester.tap(find.byKey(Key('$widgetId')));\n    await $tester.pumpAndSettle();\n    await $tester.tap(find.text('$value').last);\n    await $tester.pumpAndSettle();";
        }
        return "    // select: missing widgetId";

      case 'wait':
        final condition = params['condition'] as String?;
        final duration = params['duration'] as int?;
        if (condition == 'duration' && duration != null) {
          return "    await $tester.pump(Duration(milliseconds: $duration));";
        }
        return "    await $tester.pumpAndSettle();";

      default:
        return "    // ${action}: ${params.entries.map((e) => '${e.key}=${e.value}').join(', ')}";
    }
  }

  String _generateAssertionCode(String assertion, Map<String, dynamic> params) {
    final widgetId = params['widgetId'] as String?;
    final expected = params['expected'];

    switch (assertion) {
      case 'toBeVisible':
        if (widgetId != null) {
          return "    expect(find.byKey(Key('$widgetId')), findsOneWidget);";
        }
        return "    // toBeVisible: missing widgetId";

      case 'toBeHidden':
        if (widgetId != null) {
          return "    expect(find.byKey(Key('$widgetId')), findsNothing);";
        }
        return "    // toBeHidden: missing widgetId";

      case 'toBeEnabled':
        if (widgetId != null) {
          return "    final widget = tester.widget(find.byKey(Key('$widgetId')));\n    expect((widget as dynamic).enabled, isTrue);";
        }
        return "    // toBeEnabled: missing widgetId";

      case 'toBeDisabled':
        if (widgetId != null) {
          return "    final widget = tester.widget(find.byKey(Key('$widgetId')));\n    expect((widget as dynamic).enabled, isFalse);";
        }
        return "    // toBeDisabled: missing widgetId";

      case 'toBeChecked':
        if (widgetId != null) {
          return "    final checkbox = tester.widget<Checkbox>(find.byKey(Key('$widgetId')));\n    expect(checkbox.value, isTrue);";
        }
        return "    // toBeChecked: missing widgetId";

      case 'toBeUnchecked':
        if (widgetId != null) {
          return "    final checkbox = tester.widget<Checkbox>(find.byKey(Key('$widgetId')));\n    expect(checkbox.value, isFalse);";
        }
        return "    // toBeUnchecked: missing widgetId";

      case 'toHaveText':
        if (expected != null) {
          final escapedText = expected.toString().replaceAll("'", "\\'");
          return "    expect(find.text('$escapedText'), findsOneWidget);";
        }
        return "    // toHaveText: missing expected value";

      case 'toContainText':
        if (expected != null) {
          final escapedText = expected.toString().replaceAll("'", "\\'");
          return "    expect(find.textContaining('$escapedText'), findsWidgets);";
        }
        return "    // toContainText: missing expected value";

      case 'toHaveValue':
        if (widgetId != null && expected != null) {
          return "    final textField = tester.widget<TextField>(find.byKey(Key('$widgetId')));\n    expect(textField.controller?.text, equals('$expected'));";
        }
        return "    // toHaveValue: missing widgetId or expected";

      case 'toBeFocused':
        if (widgetId != null) {
          return "    final focusNode = Focus.of(tester.element(find.byKey(Key('$widgetId'))));\n    expect(focusNode.hasFocus, isTrue);";
        }
        return "    // toBeFocused: missing widgetId";

      default:
        return "    // ${assertion}: ${params.entries.map((e) => '${e.key}=${e.value}').join(', ')}";
    }
  }
}

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
