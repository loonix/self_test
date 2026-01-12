/// Represents the current recording mode.
enum RecordingMode {
  /// No recording or viewing active
  inactive,

  /// Currently recording user interactions
  recording,

  /// Viewing a recorded test script
  viewing,

  /// Adding assertions to a test script
  asserting,
}
