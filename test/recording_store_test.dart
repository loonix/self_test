import 'package:flutter_test/flutter_test.dart';
import 'package:self_test/self_test.dart';

void main() {
  group('InMemoryRecordingStore', () {
    late InMemoryRecordingStore store;

    setUp(() {
      store = InMemoryRecordingStore();
    });

    test('is usable without initialize, so a first build can read it', () {
      expect(store.isInitialized, isTrue);
      expect(store.getScripts(), isEmpty);
      expect(store.getSteps(0), isEmpty);
    });

    test('assigns incrementing script ids', () async {
      final first = await store.createScript('login');
      final second = await store.createScript('checkout');

      expect(first.id, 0);
      expect(second.id, 1);
      expect(
        store.getScripts().map((s) => s.name),
        containsAll(['login', 'checkout']),
      );
    });

    test('orders steps per script, not globally', () async {
      final a = await store.createScript('a');
      final b = await store.createScript('b');

      await store.recordStep(scriptId: a.id, action: 'trigger', targetId: 'a1');
      await store.recordStep(scriptId: b.id, action: 'trigger', targetId: 'b1');
      await store.recordStep(scriptId: a.id, action: 'trigger', targetId: 'a2');

      expect(store.getSteps(a.id).map((s) => s.order), [0, 1]);
      expect(store.getSteps(a.id).map((s) => s.targetId), ['a1', 'a2']);
      expect(store.getSteps(b.id).map((s) => s.order), [0]);
    });

    test('records the value of a text entry step', () async {
      final script = await store.createScript('login');
      final step = await store.recordStep(
        scriptId: script.id,
        action: 'enterText',
        targetId: 'username',
        value: 'daniel',
      );

      expect(step.action, 'enterText');
      expect(step.value, 'daniel');
      expect(store.getSteps(script.id).single.value, 'daniel');
    });

    test('deleting a script takes its steps and leaves others alone', () async {
      final doomed = await store.createScript('doomed');
      final kept = await store.createScript('kept');
      await store.recordStep(
        scriptId: doomed.id,
        action: 'trigger',
        targetId: 'x',
      );
      await store.recordStep(
        scriptId: kept.id,
        action: 'trigger',
        targetId: 'y',
      );

      await store.deleteScript(doomed.id);

      expect(store.getScripts().map((s) => s.name), ['kept']);
      expect(store.getSteps(doomed.id), isEmpty);
      expect(store.getSteps(kept.id), hasLength(1));
    });

    test('clear resets ids so a fresh session starts from zero', () async {
      await store.createScript('one');
      await store.clear();

      expect(store.getScripts(), isEmpty);
      expect((await store.createScript('two')).id, 0);
    });
  });

  group('model serialization', () {
    test('TestScript survives a JSON round trip', () {
      final original = TestScript(
        id: 7,
        name: 'login',
        createdAt: DateTime.utc(2026, 9, 10, 12, 30),
        lastRunStatus: 'PASSED',
        lastRunDate: DateTime.utc(2026, 9, 10, 13, 0),
      );

      final restored = TestScript.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.createdAt, original.createdAt);
      expect(restored.lastRunStatus, 'PASSED');
      expect(restored.lastRunDate, original.lastRunDate);
    });

    test('TestScript.fromJson defaults a missing status to PENDING', () {
      final restored = TestScript.fromJson({
        'id': 1,
        'name': 'x',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      });

      expect(restored.lastRunStatus, 'PENDING');
      expect(restored.lastRunDate, isNull);
    });

    test('RecordedStep survives a JSON round trip', () {
      final original = RecordedStep(
        id: 3,
        scriptId: 7,
        order: 2,
        action: 'enterText',
        targetId: 'username',
        value: 'daniel',
      );

      final restored = RecordedStep.fromJson(original.toJson());

      expect(restored.id, 3);
      expect(restored.scriptId, 7);
      expect(restored.order, 2);
      expect(restored.action, 'enterText');
      expect(restored.targetId, 'username');
      expect(restored.value, 'daniel');
    });
  });
}
