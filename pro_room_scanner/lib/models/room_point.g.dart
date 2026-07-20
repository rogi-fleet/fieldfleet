// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_point.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RoomPointAdapter extends TypeAdapter<RoomPoint> {
  @override
  final int typeId = 2;

  @override
  RoomPoint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RoomPoint(
      fields[0] as double,
      fields[1] as double,
      y: fields[2] as double?,
      roomLabel: fields[3] as String?,
      floorLevel: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, RoomPoint obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.x)
      ..writeByte(1)
      ..write(obj.z)
      ..writeByte(2)
      ..write(obj.y)
      ..writeByte(3)
      ..write(obj.roomLabel)
      ..writeByte(4)
      ..write(obj.floorLevel);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomPointAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
