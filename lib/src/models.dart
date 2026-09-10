import 'package:hive_ce/hive.dart';

part 'models.g.dart';

@HiveType(typeId: 0)
class TestScript extends HiveObject {
  @HiveField(0)
  int id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  String lastRunStatus;

  @HiveField(4)
  DateTime? lastRunDate;

  TestScript({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastRunStatus = 'PENDING',
    this.lastRunDate,
  });

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

@HiveType(typeId: 1)
class TestStep extends HiveObject {
  @HiveField(0)
  int id;

  @HiveField(1)
  int scriptId;

  @HiveField(2)
  int order;

  @HiveField(3)
  String action; // 'trigger', 'enterText', 'assertText', 'assertExists'

  @HiveField(4)
  String targetId;

  @HiveField(5)
  String? value;

  TestStep({
    required this.id,
    required this.scriptId,
    required this.order,
    required this.action,
    required this.targetId,
    this.value,
  });

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
