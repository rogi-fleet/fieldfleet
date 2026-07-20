import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/customer_location.dart';
import '../../utils/app_logger.dart';

class SupabaseCustomerLocationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all active locations for a customer (realtime stream)
  Stream<List<CustomerLocation>> getLocations(String customerId) {
    return _supabase
        .from('customer_locations')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId)
        .order('created_at', ascending: true)
        .map((data) => data
            .where((row) => row['is_active'] == true)
            .map((row) => CustomerLocation.fromJson(row))
            .toList());
  }

  /// Get a single location by ID
  Future<CustomerLocation?> getLocation(String locationId) async {
    try {
      final response = await _supabase
          .from('customer_locations')
          .select()
          .eq('id', locationId)
          .maybeSingle();

      if (response == null) return null;
      return CustomerLocation.fromJson(response);
    } catch (e) {
      AppLogger.error('Error fetching customer location', error: e);
      return null;
    }
  }

  /// Create a new location
  Future<String> createLocation(CustomerLocation location) async {
    try {
      final now = DateTime.now().toIso8601String();
      final data = location.toJson();
      data['created_at'] = now;
      data['updated_at'] = now;

      final response = await _supabase
          .from('customer_locations')
          .insert(data)
          .select('id')
          .single();

      AppLogger.info(
        'Customer location created',
        metadata: {'locationId': response['id'], 'name': location.name},
      );
      return response['id'] as String;
    } catch (e) {
      AppLogger.error('Error creating customer location', error: e);
      throw Exception('Error creating location: $e');
    }
  }

  /// Update an existing location
  Future<void> updateLocation(CustomerLocation location) async {
    try {
      final data = location.toJson();
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('customer_locations')
          .update(data)
          .eq('id', location.id);

      AppLogger.info(
        'Customer location updated',
        metadata: {'locationId': location.id},
      );
    } catch (e) {
      AppLogger.error('Error updating customer location', error: e);
      throw Exception('Error updating location: $e');
    }
  }

  /// Soft-delete a location
  Future<void> deleteLocation(String locationId) async {
    try {
      await _supabase
          .from('customer_locations')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', locationId);

      AppLogger.info(
        'Customer location archived',
        metadata: {'locationId': locationId},
      );
    } catch (e) {
      AppLogger.error('Error archiving customer location', error: e);
      throw Exception('Error archiving location: $e');
    }
  }

  /// Get all locations for a workspace (for project form dropdowns)
  Future<List<CustomerLocation>> getLocationsForCustomer(
    String customerId,
  ) async {
    try {
      final response = await _supabase
          .from('customer_locations')
          .select()
          .eq('customer_id', customerId)
          .eq('is_active', true)
          .order('name', ascending: true);

      return response
          .map((row) => CustomerLocation.fromJson(row))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching locations for customer', error: e);
      return [];
    }
  }

  /// Get projects linked to a specific customer location
  Future<List<Map<String, dynamic>>> getProjectsForLocation(
    String locationId,
  ) async {
    try {
      final response = await _supabase
          .from('projects')
          .select('id, name, status')
          .eq('customer_location_id', locationId)
          .order('updated_at', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('Error fetching projects for location', error: e);
      return [];
    }
  }
}
