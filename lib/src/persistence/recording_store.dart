import '../locator/locator.dart';
import '../models.dart';

/// Storage for recorded test scripts and their steps.
///
/// The package ships [InMemoryRecordingStore] and nothing else on purpose. A
/// testing library has no business dragging a database and a path resolver
/// into every app that depends on it, so durable storage is an app-level
/// choice: implement this interface over whatever the host app already uses
/// (Hive, sqflite, Isar, a file, a server) and hand it to
/// `SelfTestManager().useRecordingStore(...)`.
abstract class RecordingStore {
  /// Whether the store is ready to read and write.
  bool get isInitialized;

  /// Prepares the store. Must be safe to call more than once.
  Future<void> initialize();

  /// Creates a new script with the given name and returns it, id assigned.
  Future<TestScript> createScript(String name);

  /// Appends a step to [scriptId], ordered after the steps already stored.
  Future<RecordedStep> recordStep({
    required int scriptId,
    required String action,
    required String targetId,
    String? value,
    SelfTestLocator? locator,
  });

  /// All stored scripts. Returns empty rather than throwing when the store is
  /// not initialized, because the UI reads this during its first build.
  List<TestScript> getScripts();

  /// All stored scripts, initializing the store first if needed.
  Future<List<TestScript>> getScriptsAsync();

  /// The steps of [scriptId], in recorded order.
  List<RecordedStep> getSteps(int scriptId);

  /// Deletes [scriptId] and every step belonging to it.
  Future<void> deleteScript(int scriptId);

  /// Removes everything and resets id assignment.
  Future<void> clear();
}

/// The default [RecordingStore]: keeps everything in memory for the lifetime
/// of the process.
///
/// Recordings are lost on restart, which is the right default for a package
/// used during a debug session. Export the script (see `TestCodeGenerator`)
/// to keep it, or supply a durable [RecordingStore].
class InMemoryRecordingStore implements RecordingStore {
  final Map<int, TestScript> _scripts = {};
  final Map<int, RecordedStep> _steps = {};
  int _nextScriptId = 0;
  int _nextStepId = 0;

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<TestScript> createScript(String name) async {
    final script = TestScript(
      id: _nextScriptId++,
      name: name,
      createdAt: DateTime.now(),
    );
    _scripts[script.id] = script;
    return script;
  }

  @override
  Future<RecordedStep> recordStep({
    required int scriptId,
    required String action,
    required String targetId,
    String? value,
    SelfTestLocator? locator,
  }) async {
    final order = _steps.values.where((s) => s.scriptId == scriptId).length;
    final step = RecordedStep(
      id: _nextStepId++,
      scriptId: scriptId,
      order: order,
      action: action,
      targetId: targetId,
      locator: locator,
      value: value,
    );
    _steps[step.id] = step;
    return step;
  }

  @override
  List<TestScript> getScripts() => _scripts.values.toList();

  @override
  Future<List<TestScript>> getScriptsAsync() async => getScripts();

  @override
  List<RecordedStep> getSteps(int scriptId) {
    return _steps.values.where((s) => s.scriptId == scriptId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<void> deleteScript(int scriptId) async {
    _steps.removeWhere((_, step) => step.scriptId == scriptId);
    _scripts.remove(scriptId);
  }

  @override
  Future<void> clear() async {
    _scripts.clear();
    _steps.clear();
    _nextScriptId = 0;
    _nextStepId = 0;
  }
}
