import 'package:hive/hive.dart';
import 'room_point.dart';

part 'wall_opening.g.dart';

@HiveType(typeId: 7)
enum OpeningType {
  @HiveField(0)
  door,
  @HiveField(1)
  window
}

@HiveType(typeId: 6)
class WallOpening {
  @HiveField(0)
  final RoomPoint position; // Changed from start/end to position/rotation/width to match existing logic
  
  @HiveField(1)
  final double rotation;
  
  @HiveField(2)
  final double width;
  
  @HiveField(3)
  final OpeningType type;

  WallOpening({
    required this.position,
    this.rotation = 0.0,
    this.width = 0.9,
    this.type = OpeningType.door,
  });
}
