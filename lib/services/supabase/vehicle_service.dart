import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/vehicle.dart';
import '../../models/maintenance_log.dart';
import '../../models/vehicle_expense.dart';

/// Supabase implementation of VehicleService
class SupabaseVehicleService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String workspaceId;

  SupabaseVehicleService({required this.workspaceId});

  /// Get all vehicles for the workspace
  Stream<List<Vehicle>> getVehicles() {
    // Guard against an unhydrated workspace id (PostgREST returns
    // 400 invalid uuid otherwise).
    if (workspaceId.isEmpty) {
      return Stream<List<Vehicle>>.value(const []);
    }
    return _supabase
        .from('vehicles')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('name')
        .map((data) {
          return data.map((row) => _toVehicle(row)).toList();
        });
  }

  /// Get vehicles (one-time fetch)
  Future<List<Vehicle>> getVehiclesOnce() async {
    try {
      final response = await _supabase
          .from('vehicles')
          .select()
          .eq('workspace_id', workspaceId)
          .order('name');

      return response.map((row) => _toVehicle(row)).toList();
    } catch (e) {
      throw Exception('Error fetching vehicles: $e');
    }
  }

  /// Get a single vehicle
  Future<Vehicle?> getVehicle(String vehicleId) async {
    try {
      final response = await _supabase
          .from('vehicles')
          .select()
          .eq('id', vehicleId)
          .maybeSingle();

      if (response == null) return null;
      return _toVehicle(response);
    } catch (e) {
      throw Exception('Error fetching vehicle: $e');
    }
  }

  /// Add a new vehicle
  Future<Vehicle> addVehicle(Vehicle vehicle) async {
    try {
      final vehicleData = _toSupabaseFormat(vehicle);
      vehicleData['workspace_id'] = workspaceId;

      final response = await _supabase
          .from('vehicles')
          .insert(vehicleData)
          .select()
          .single();

      return _toVehicle(response);
    } catch (e) {
      throw Exception('Error adding vehicle: $e');
    }
  }

  /// Update a vehicle
  Future<void> updateVehicle(Vehicle vehicle) async {
    try {
      final vehicleData = _toSupabaseFormat(vehicle);
      vehicleData['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('vehicles')
          .update(vehicleData)
          .eq('id', vehicle.id);
    } catch (e) {
      throw Exception('Error updating vehicle: $e');
    }
  }

  /// Update only the vehicle image without overwriting other unsaved fields.
  Future<void> updateVehicleImage(String vehicleId, String imageUrl) async {
    try {
      await _supabase.from('vehicles').update({
        'image_url': imageUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error updating vehicle image: $e');
    }
  }

  /// Delete a vehicle
  Future<void> deleteVehicle(String vehicleId) async {
    try {
      await _supabase
          .from('maintenance_logs')
          .delete()
          .eq('entity_id', vehicleId);

      await _supabase
          .from('vehicle_expenses')
          .delete()
          .eq('vehicle_id', vehicleId);

      await _supabase.from('vehicles').delete().eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error deleting vehicle: $e');
    }
  }

  /// Set the primary driver
  Future<void> assignVehicleToUser(String vehicleId, String userId) async {
    try {
      await _supabase.from('vehicles').update({
        'assigned_to_user_id': userId,
        'status': 'active',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error assigning vehicle: $e');
    }
  }

  /// Clear the primary driver assignment.
  Future<void> unassignVehicle(String vehicleId) async {
    try {
      await _supabase.from('vehicles').update({
        'assigned_to_user_id': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error unassigning vehicle: $e');
    }
  }

  /// Pin the vehicle to a project.
  Future<void> assignVehicleToProject(
    String vehicleId,
    String projectId,
  ) async {
    try {
      await _supabase.from('vehicles').update({
        'assigned_to_project_id': projectId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error assigning vehicle to project: $e');
    }
  }

  /// Remove the project pin.
  Future<void> unassignVehicleFromProject(String vehicleId) async {
    try {
      await _supabase.from('vehicles').update({
        'assigned_to_project_id': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error clearing vehicle project: $e');
    }
  }

  /// Check the vehicle out to a driver right now.
  Future<void> checkOutVehicle(String vehicleId, String userId) async {
    try {
      await _supabase.from('vehicles').update({
        'current_driver_id': userId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error checking out vehicle: $e');
    }
  }

  /// Check the vehicle back in.
  Future<void> checkInVehicle(String vehicleId) async {
    try {
      await _supabase.from('vehicles').update({
        'current_driver_id': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error checking in vehicle: $e');
    }
  }

  /// Get vehicles by status
  Future<List<Vehicle>> getVehiclesByStatus(String status) async {
    try {
      final response = await _supabase
          .from('vehicles')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('status', status)
          .order('name');

      return response.map((row) => _toVehicle(row)).toList();
    } catch (e) {
      throw Exception('Error fetching vehicles by status: $e');
    }
  }

  /// Vehicles where the user is either the primary driver or currently
  /// has the keys.
  Future<List<Vehicle>> getVehiclesAssignedToUser(String userId) async {
    try {
      final response = await _supabase
          .from('vehicles')
          .select()
          .eq('workspace_id', workspaceId)
          .or('assigned_to_user_id.eq.$userId,current_driver_id.eq.$userId')
          .order('name');

      return response.map((row) => _toVehicle(row)).toList();
    } catch (e) {
      throw Exception('Error fetching assigned vehicles: $e');
    }
  }

  /// Vehicles currently pinned to a project.
  Future<List<Vehicle>> getVehiclesAssignedToProject(String projectId) async {
    try {
      final response = await _supabase
          .from('vehicles')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('assigned_to_project_id', projectId)
          .order('name');

      return response.map((row) => _toVehicle(row)).toList();
    } catch (e) {
      throw Exception('Error fetching project vehicles: $e');
    }
  }

  // ============================================================================
  // Maintenance Logs
  // ============================================================================

  /// Get maintenance logs for an entity (vehicle or equipment)
  Stream<List<MaintenanceLog>> getMaintenanceLogs(String entityId) {
    return _supabase
        .from('maintenance_logs')
        .stream(primaryKey: ['id'])
        .eq('entity_id', entityId)
        .order('date', ascending: false)
        .map((data) {
          return data.map((row) => _toMaintenanceLog(row)).toList();
        });
  }

  /// Get maintenance logs (one-time fetch)
  Future<List<MaintenanceLog>> getMaintenanceLogsOnce(String entityId) async {
    try {
      final response = await _supabase
          .from('maintenance_logs')
          .select()
          .eq('entity_id', entityId)
          .order('date', ascending: false);

      return response.map((row) => _toMaintenanceLog(row)).toList();
    } catch (e) {
      throw Exception('Error fetching maintenance logs: $e');
    }
  }

  /// Add a maintenance log
  Future<MaintenanceLog> addMaintenanceLog(MaintenanceLog log) async {
    try {
      final logData = _toMaintenanceLogSupabaseFormat(log);

      final response = await _supabase
          .from('maintenance_logs')
          .insert(logData)
          .select()
          .single();

      return _toMaintenanceLog(response);
    } catch (e) {
      throw Exception('Error adding maintenance log: $e');
    }
  }

  /// Update a maintenance log
  Future<void> updateMaintenanceLog(MaintenanceLog log) async {
    try {
      final logData = _toMaintenanceLogSupabaseFormat(log);

      await _supabase
          .from('maintenance_logs')
          .update(logData)
          .eq('id', log.id);
    } catch (e) {
      throw Exception('Error updating maintenance log: $e');
    }
  }

  /// Delete a maintenance log
  Future<void> deleteMaintenanceLog(String logId) async {
    try {
      await _supabase.from('maintenance_logs').delete().eq('id', logId);
    } catch (e) {
      throw Exception('Error deleting maintenance log: $e');
    }
  }

  // ============================================================================
  // Vehicle Expenses
  // ============================================================================

  /// Stream of all expenses for a vehicle, newest first.
  Stream<List<VehicleExpense>> getExpenses(String vehicleId) {
    return _supabase
        .from('vehicle_expenses')
        .stream(primaryKey: ['id'])
        .eq('vehicle_id', vehicleId)
        .order('date', ascending: false)
        .map((data) => data.map((row) => _toExpense(row)).toList());
  }

  /// One-time fetch of expenses for a vehicle.
  Future<List<VehicleExpense>> getExpensesOnce(String vehicleId) async {
    try {
      final response = await _supabase
          .from('vehicle_expenses')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('date', ascending: false);

      return response.map((row) => _toExpense(row)).toList();
    } catch (e) {
      // Return empty list if the table doesn't exist yet.
      return [];
    }
  }

  /// Add an expense record.
  Future<VehicleExpense> addExpense(VehicleExpense expense) async {
    try {
      final data = _toExpenseSupabaseFormat(expense);
      data['workspace_id'] = workspaceId;

      final response = await _supabase
          .from('vehicle_expenses')
          .insert(data)
          .select()
          .single();

      return _toExpense(response);
    } catch (e) {
      throw Exception('Error adding expense: $e');
    }
  }

  /// Update an existing expense record.
  Future<void> updateExpense(VehicleExpense expense) async {
    try {
      final data = _toExpenseSupabaseFormat(expense);
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('vehicle_expenses')
          .update(data)
          .eq('id', expense.id);
    } catch (e) {
      throw Exception('Error updating expense: $e');
    }
  }

  /// Delete an expense record.
  Future<void> deleteExpense(String expenseId) async {
    try {
      await _supabase
          .from('vehicle_expenses')
          .delete()
          .eq('id', expenseId);
    } catch (e) {
      throw Exception('Error deleting expense: $e');
    }
  }

  /// Workspace-wide summary: total expenses grouped by category.
  Future<Map<String, double>> getExpenseSummaryByCategory() async {
    try {
      final response = await _supabase
          .from('vehicle_expenses')
          .select('category, amount')
          .eq('workspace_id', workspaceId);

      final Map<String, double> totals = {};
      for (final row in response) {
        final cat = row['category'] as String? ?? 'other';
        final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
        totals[cat] = (totals[cat] ?? 0.0) + amount;
      }
      return totals;
    } catch (e) {
      return {};
    }
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  Vehicle _toVehicle(Map<String, dynamic> row) {
    return Vehicle(
      id: row['id'],
      workspaceId: row['workspace_id'] ?? '',
      name: row['name'] ?? '',
      make: row['make'] ?? '',
      model: row['model'] ?? '',
      year: row['year'] ?? 0,
      licensePlate: row['license_plate'] ?? '',
      vin: row['vin'],
      currentMileage: row['current_mileage'] ?? 0,
      assignedToUserId: row['assigned_to_user_id'],
      currentDriverId: row['current_driver_id'],
      assignedToProjectId: row['assigned_to_project_id'],
      status: row['status'] ?? 'active',
      qrCode: row['qr_code'],
      imageUrl: row['image_url'],
      insuranceExpiry: row['insurance_expiry'] != null
          ? DateTime.tryParse('${row['insurance_expiry']}')
          : null,
      registrationExpiry: row['registration_expiry'] != null
          ? DateTime.tryParse('${row['registration_expiry']}')
          : null,
    );
  }

  Map<String, dynamic> _toSupabaseFormat(Vehicle vehicle) {
    return {
      'name': vehicle.name,
      'make': vehicle.make,
      'model': vehicle.model,
      'year': vehicle.year,
      'license_plate': vehicle.licensePlate,
      'vin': vehicle.vin,
      'status': vehicle.status,
      'assigned_to_user_id': vehicle.assignedToUserId,
      'current_driver_id': vehicle.currentDriverId,
      'assigned_to_project_id': vehicle.assignedToProjectId,
      'current_mileage': vehicle.currentMileage,
      'qr_code': vehicle.qrCode,
      'image_url': vehicle.imageUrl,
      'insurance_expiry':
          vehicle.insuranceExpiry?.toIso8601String().split('T').first,
      'registration_expiry':
          vehicle.registrationExpiry?.toIso8601String().split('T').first,
    };
  }

  MaintenanceLog _toMaintenanceLog(Map<String, dynamic> row) {
    return MaintenanceLog(
      id: row['id'],
      workspaceId: row['workspace_id'] ?? workspaceId,
      entityId: row['entity_id'] ?? '',
      entityType: row['entity_type'] ?? 'vehicle',
      date: row['date'] != null ? DateTime.parse(row['date']) : DateTime.now(),
      type: row['type'] ?? 'other',
      description: row['description'] ?? '',
      cost: (row['cost'] as num?)?.toDouble() ?? 0.0,
      performedBy: row['performed_by'],
      nextMaintenanceDate: row['next_maintenance_date'] != null
          ? DateTime.parse(row['next_maintenance_date'])
          : null,
      nextMaintenanceMileage: row['next_maintenance_mileage'],
    );
  }

  Map<String, dynamic> _toMaintenanceLogSupabaseFormat(MaintenanceLog log) {
    return {
      'workspace_id': log.workspaceId,
      'entity_id': log.entityId,
      'entity_type': log.entityType,
      'type': log.type,
      'description': log.description,
      'date': log.date.toIso8601String(),
      'cost': log.cost,
      'performed_by': log.performedBy,
      'next_maintenance_date': log.nextMaintenanceDate?.toIso8601String(),
      'next_maintenance_mileage': log.nextMaintenanceMileage,
    };
  }

  VehicleExpense _toExpense(Map<String, dynamic> row) {
    return VehicleExpense(
      id: row['id'],
      workspaceId: row['workspace_id'] ?? workspaceId,
      vehicleId: row['vehicle_id'] ?? '',
      date: row['date'] != null ? DateTime.parse(row['date']) : DateTime.now(),
      category: row['category'] ?? 'other',
      amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
      description: row['description'],
      odometer: row['odometer'],
      vendor: row['vendor'],
      attachmentUrl: row['attachment_url'],
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : null,
    );
  }

  Map<String, dynamic> _toExpenseSupabaseFormat(VehicleExpense expense) {
    return {
      'vehicle_id': expense.vehicleId,
      'date': expense.date.toIso8601String(),
      'category': expense.category,
      'amount': expense.amount,
      'description': expense.description,
      'odometer': expense.odometer,
      'vendor': expense.vendor,
      'attachment_url': expense.attachmentUrl,
    };
  }
}
