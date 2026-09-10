/// A recorded test script: a named sequence of user actions captured from a
/// running app.
///
/// Plain data. Persisting it is the job of a [RecordingStore] implementation,
/// so nothing here depends on a storage engine.
class TestScript {
  int id;
  String name;
  DateTime createdAt;
  String lastRunStatus;
  DateTime? lastRunDate;

  TestScript({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastRunStatus = 'PENDING',
    this.lastRunDate,
  });

  factory TestScript.fromJson(Map<String, dynamic> json) {
    return TestScript(
      id: json['id'] as int,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastRunStatus: json['lastRunStatus'] as String? ?? 'PENDING',
      lastRunDate: json['lastRunDate'] == null
          ? null
          : DateTime.parse(json['lastRunDate'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'lastRunStatus': lastRunStatus,
      'lastRunDate': lastRunDate?.toIso8601String(),
    };
  }
}

/// One action inside a recorded [TestScript].
///
/// Named `RecordedStep` rather than `TestStep` on purpose: `TestStep` is the
/// published scenario-command type in `self_test.dart`, which is a different
/// concept (an instruction to execute, not a stored row).
class RecordedStep {
  int id;
  int scriptId;
  int order;

  /// One of `trigger`, `enterText`, `assertText`, `assertExists`.
  String action;
  String targetId;
  String? value;

  RecordedStep({
    required this.id,
    required this.scriptId,
    required this.order,
    required this.action,
    required this.targetId,
    this.value,
  });

  factory RecordedStep.fromJson(Map<String, dynamic> json) {
    return RecordedStep(
      id: json['id'] as int,
      scriptId: json['scriptId'] as int,
      order: json['order'] as int,
      action: json['action'] as String,
      targetId: json['targetId'] as String,
      value: json['value'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptId': scriptId,
      'order': order,
      'action': action,
      'targetId': targetId,
      'value': value,
    };
  }
}
