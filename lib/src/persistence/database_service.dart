import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models.dart';

/// Service for managing test script and step persistence using Hive.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static bool _adaptersRegistered = false;

  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Box<TestScript>? _scriptBox;
  Box<TestStep>? _stepBox;
  int _nextScriptId = 0;
  int _nextStepId = 0;

  /// Whether the database has been initialized.
  bool get isInitialized => _scriptBox != null && _stepBox != null;

  /// Initializes the local database for storing test scripts and steps.
  Future<void> initialize() async {
    if (isInitialized) return;

    try {
      debugPrint('[SelfTest] Initializing database...');
      final dir = await getApplicationDocumentsDirectory();
      debugPrint('[SelfTest] Documents directory: ${dir.path}');
      Hive.init(dir.path);
      if (!_adaptersRegistered) {
        Hive.registerAdapter(TestScriptAdapter());
        Hive.registerAdapter(TestStepAdapter());
        _adaptersRegistered = true;
        debugPrint('[SelfTest] Hive adapters registered');
      }
      _scriptBox = await Hive.openBox<TestScript>('testScripts');
      _stepBox = await Hive.openBox<TestStep>('testSteps');
      _nextScriptId = (_scriptBox!.values.isEmpty
          ? 0
          : _scriptBox!.values.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1);
      _nextStepId = (_stepBox!.values.isEmpty
          ? 0
          : _stepBox!.values.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1);
      debugPrint(
          '[SelfTest] Database initialized successfully. Next IDs: script $_nextScriptId, step $_nextStepId');
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR initializing database: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Creates a new test script with the given name.
  Future<TestScript> createScript(String name) async {
    if (!isInitialized) await initialize();

    final script = TestScript(
      id: _nextScriptId++,
      name: name,
      createdAt: DateTime.now(),
    );
    await _scriptBox!.put(script.id, script);
    debugPrint('[SelfTest] Created script: "$name" (id: ${script.id})');
    return script;
  }

  /// Records a test step for the given script.
  Future<TestStep> recordStep({
    required int scriptId,
    required String action,
    required String targetId,
    String? value,
  }) async {
    if (!isInitialized) await initialize();

    final order = _stepBox!.values.where((s) => s.scriptId == scriptId).length;
    final step = TestStep(
      id: _nextStepId++,
      scriptId: scriptId,
      order: order,
      action: action,
      targetId: targetId,
      value: value,
    );
    await _stepBox!.put(step.id, step);
    debugPrint('[SelfTest] Recorded action: $action on "$targetId" (order: $order)');
    return step;
  }

  /// Gets all test scripts.
  List<TestScript> getScripts() {
    if (_scriptBox == null) return [];
    return _scriptBox!.values.toList();
  }

  /// Gets all test scripts (async version that initializes DB if needed).
  Future<List<TestScript>> getScriptsAsync() async {
    if (!isInitialized) await initialize();
    return _scriptBox!.values.toList();
  }

  /// Gets test steps for a specific script.
  List<TestStep> getSteps(int scriptId) {
    if (_stepBox == null) return [];
    return _stepBox!.values.where((s) => s.scriptId == scriptId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Deletes a test script and all its steps.
  Future<void> deleteScript(int scriptId) async {
    try {
      debugPrint('[SelfTest] Deleting test script: $scriptId');
      if (!isInitialized) await initialize();

      // Delete all steps for this script
      final stepsToDelete = _stepBox!.values.where((s) => s.scriptId == scriptId).toList();
      for (final step in stepsToDelete) {
        await _stepBox!.delete(step.id);
        debugPrint('[SelfTest] Deleted step: ${step.id}');
      }

      // Delete the script
      await _scriptBox!.delete(scriptId);
      debugPrint('[SelfTest] Deleted test script: $scriptId');
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR deleting test script $scriptId: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Clears all test scripts and steps (for testing purposes).
  Future<void> clear() async {
    if (_scriptBox != null) await _scriptBox!.clear();
    if (_stepBox != null) await _stepBox!.clear();
    _nextScriptId = 0;
    _nextStepId = 0;
  }
}
