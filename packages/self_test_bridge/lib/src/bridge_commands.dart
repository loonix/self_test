/// Available bridge commands - Playwright parity
class BridgeCommands {
  // =====================================================================
  // LOCATORS
  //
  // These five take a `locator` object rather than a registered widget id:
  //
  //   {"by": "text|key|id|semanticsLabel|type|tooltip",
  //    "value": "Sign in", "exact": true, "index": 0}
  //
  // `exact` and `index` are optional. Every action command accepts the same
  // object and prefers it over `widgetId`.
  // =====================================================================

  /// Every actionable widget on screen, as WidgetSnapshot JSON.
  static const String describeScreen = 'describeScreen';

  /// The first widget a locator matches, or null.
  static const String find = 'find';

  /// Whether a locator matches anything in the tree.
  static const String exists = 'exists';

  /// Whether a locator matches something the user can see.
  static const String isVisible = 'isVisible';

  /// The text the widget a locator matches is showing.
  static const String readText = 'readText';

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

  /// Fires the keyboard action of a text field.
  static const String submit = 'submit';

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
