import 'package:hive/hive.dart';
import 'room.dart';

part 'plan.g.dart';

@HiveType(typeId: 0)
class Plan extends HiveObject {
  @HiveField(0)
  String id;
  
  @HiveField(1)
  String name;
  
  @HiveField(2)
  DateTime createdAt;
  
  @HiveField(3)
  DateTime updatedAt;
  
  @HiveField(4)
  List<Room> rooms;
  
  @HiveField(5)
  String? address;
  
  @HiveField(6)
  String? clientName;

  Plan({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    List<Room>? rooms,
    this.address,
    this.clientName,
  }) : rooms = rooms ?? [];
}
