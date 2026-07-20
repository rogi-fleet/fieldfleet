import 'package:hive/hive.dart';
import 'package:vector_math/vector_math_64.dart';

part 'room_point.g.dart';

@HiveType(typeId: 2)
class RoomPoint {
  @HiveField(0)
  final double x;
  
  @HiveField(1)
  final double z;
  
  @HiveField(2)
  double? y;
  
  @HiveField(3)
  String? roomLabel; // e.g. "Kitchen", "Bedroom"
  
  @HiveField(4)
  int floorLevel; // 0 = ground, 1 = 1st floor, etc.

  RoomPoint(this.x, this.z, {this.y, this.roomLabel, this.floorLevel = 0});

  double distanceTo(RoomPoint other) {
    return Vector3(x, y ?? 0, z).distanceTo(Vector3(other.x, other.y ?? 0, other.z));
  }
  
  Vector3 get position => Vector3(x, y ?? 0.0, z);
}
