// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wall_opening.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WallOpeningAdapter extends TypeAdapter<WallOpening> {
  @override
  final int typeId = 6;

  @override
  WallOpening read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WallOpening(
      position: fields[0] as RoomPoint,
      rotation: fields[1] as double,
      width: fields[2] as double,
      type: fields[3] as OpeningType,
    );
  }

  @override
  void write(BinaryWriter writer, WallOpening obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.position)
      ..writeByte(1)
      ..write(obj.rotation)
      ..writeByte(2)
      ..write(obj.width)
      ..writeByte(3)
      ..write(obj.type);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WallOpeningAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class OpeningTypeAdapter extends TypeAdapter<OpeningType> {
  @override
  final int typeId = 7;

  @override
  OpeningType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return OpeningType.door;
      case 1:
        return OpeningType.window;
      default:
        return OpeningType.door;
    }
  }

  @override
  void write(BinaryWriter writer, OpeningType obj) {
    switch (obj) {
      case OpeningType.door:
        writer.writeByte(0);
        break;
      case OpeningType.window:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpeningTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
