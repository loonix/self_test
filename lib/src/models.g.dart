// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TestScriptAdapter extends TypeAdapter<TestScript> {
  @override
  final int typeId = 0;

  @override
  TestScript read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TestScript(
      id: (fields[0] as num).toInt(),
      name: fields[1] as String,
      createdAt: fields[2] as DateTime,
      lastRunStatus: fields[3] == null ? 'PENDING' : fields[3] as String,
      lastRunDate: fields[4] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, TestScript obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.lastRunStatus)
      ..writeByte(4)
      ..write(obj.lastRunDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestScriptAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TestStepAdapter extends TypeAdapter<TestStep> {
  @override
  final int typeId = 1;

  @override
  TestStep read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TestStep(
      id: (fields[0] as num).toInt(),
      scriptId: (fields[1] as num).toInt(),
      order: (fields[2] as num).toInt(),
      action: fields[3] as String,
      targetId: fields[4] as String,
      value: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TestStep obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.scriptId)
      ..writeByte(2)
      ..write(obj.order)
      ..writeByte(3)
      ..write(obj.action)
      ..writeByte(4)
      ..write(obj.targetId)
      ..writeByte(5)
      ..write(obj.value);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestStepAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
