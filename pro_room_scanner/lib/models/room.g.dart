// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RoomAdapter extends TypeAdapter<Room> {
  @override
  final int typeId = 1;

  @override
  Room read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Room(
      id: fields[0] as String,
      label: fields[1] as String,
      points: (fields[2] as List).cast<RoomPoint>(),
      openings: (fields[3] as List?)?.cast<WallOpening>(),
      attachments: (fields[4] as List?)?.cast<Attachment>(),
      floorLevel: fields[5] as int,
      ceilingHeight: fields[6] as double?,
      source: fields[7] as RoomSource,
      isVisible: fields[8] as bool,
      layoutPositionX: fields[9] as double,
      layoutPositionY: fields[10] as double,
      layoutRotation: fields[11] as double,
    );
  }

  @override
  void write(BinaryWriter writer, Room obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.points)
      ..writeByte(3)
      ..write(obj.openings)
      ..writeByte(4)
      ..write(obj.attachments)
      ..writeByte(5)
      ..write(obj.floorLevel)
      ..writeByte(6)
      ..write(obj.ceilingHeight)
      ..writeByte(7)
      ..write(obj.source)
      ..writeByte(8)
      ..write(obj.isVisible)
      ..writeByte(9)
      ..write(obj.layoutPositionX)
      ..writeByte(10)
      ..write(obj.layoutPositionY)
      ..writeByte(11)
      ..write(obj.layoutRotation);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RoomSourceAdapter extends TypeAdapter<RoomSource> {
  @override
  final int typeId = 5;

  @override
  RoomSource read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return RoomSource.arScan;
      case 1:
        return RoomSource.manualDraw;
      default:
        return RoomSource.arScan;
    }
  }

  @override
  void write(BinaryWriter writer, RoomSource obj) {
    switch (obj) {
      case RoomSource.arScan:
        writer.writeByte(0);
        break;
      case RoomSource.manualDraw:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
