import 'package:hive_flutter/hive_flutter.dart';
import '../models/plan.dart';
import '../models/room.dart';
import '../models/room_point.dart';
import '../models/attachment.dart';
import '../models/wall_opening.dart';

class DatabaseService {
  static const String _plansBoxName = 'plans';
  
  static Future<void> init() async {
    await Hive.initFlutter();
    
    // Register Adapters
    Hive.registerAdapter(PlanAdapter());
    Hive.registerAdapter(RoomAdapter());
    Hive.registerAdapter(RoomPointAdapter());
    Hive.registerAdapter(AttachmentAdapter());
    Hive.registerAdapter(AttachmentTypeAdapter());
    Hive.registerAdapter(RoomSourceAdapter());
    Hive.registerAdapter(WallOpeningAdapter());
    Hive.registerAdapter(OpeningTypeAdapter());
    
    // Open Boxes
    await Hive.openBox<Plan>(_plansBoxName);
  }
  
  static Box<Plan> get plansBox => Hive.box<Plan>(_plansBoxName);
  
  static List<Plan> getAllPlans() {
    return plansBox.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  
  static Future<void> savePlan(Plan plan) async {
    plan.updatedAt = DateTime.now();
    if (plan.isInBox) {
      await plan.save();
    } else {
      await plansBox.put(plan.id, plan);
    }
  }
  
  static Future<void> deletePlan(String planId) async {
    await plansBox.delete(planId);
  }
}
