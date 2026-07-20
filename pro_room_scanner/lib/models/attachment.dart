import 'package:hive/hive.dart';
import 'package:vector_math/vector_math_64.dart';

part 'attachment.g.dart';

@HiveType(typeId: 4)
enum AttachmentType {
  @HiveField(0)
  photo,
  @HiveField(1)
  note,
  @HiveField(2)
  moisture
}

@HiveType(typeId: 3)
class Attachment {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final AttachmentType type;
  
  // We store position as x,y,z for Hive serialization
  @HiveField(2)
  final double x;
  @HiveField(3)
  final double y;
  @HiveField(4)
  final double z;
  
  @HiveField(5)
  final String data; // File path or text content
  
  @HiveField(6)
  final DateTime timestamp;

  Attachment({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.z,
    required this.data,
    required this.timestamp,
  });

  factory Attachment.fromVector3({
    required String id,
    required AttachmentType type,
    required Vector3 position,
    required String data,
    required DateTime timestamp,
  }) {
    return Attachment(
      id: id,
      type: type,
      x: position.x,
      y: position.y,
      z: position.z,
      data: data,
      timestamp: timestamp,
    );
  }

  Vector3 get position => Vector3(x, y, z);
}
