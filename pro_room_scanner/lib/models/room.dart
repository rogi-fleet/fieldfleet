import 'package:hive/hive.dart';
import 'room_point.dart';
import 'wall_opening.dart';
import 'attachment.dart';

part 'room.g.dart';

@HiveType(typeId: 5)
enum RoomSource {
  @HiveField(0)
  arScan,
  @HiveField(1)
  manualDraw
}

@HiveType(typeId: 1)
class Room {
  @HiveField(0)
  String id;
  
  @HiveField(1)
  String label; // "Living Room", "Bedroom 1", etc.
  
  @HiveField(2)
  List<RoomPoint> points;
  
  @HiveField(3)
  List<WallOpening> openings;
  
  @HiveField(4)
  List<Attachment> attachments;
  
  @HiveField(5)
  int floorLevel;
  
  @HiveField(6)
  double? ceilingHeight;
  
  @HiveField(7)
  RoomSource source;
  
  @HiveField(8)
  bool isVisible;
  
  @HiveField(9)
  double layoutPositionX; // Position in master floor plan
  
  @HiveField(10)
  double layoutPositionY; // Position in master floor plan
  
  @HiveField(11)
  double layoutRotation; // Rotation in master floor plan (radians)

  Room({
    required this.id,
    required this.label,
    required this.points,
    List<WallOpening>? openings,
    List<Attachment>? attachments,
    this.floorLevel = 0,
    this.ceilingHeight,
    this.source = RoomSource.arScan,
    this.isVisible = true,
    this.layoutPositionX = 0.0,
    this.layoutPositionY = 0.0,
    this.layoutRotation = 0.0,
  })  : openings = openings ?? [],
        attachments = attachments ?? [];
}
