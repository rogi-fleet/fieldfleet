import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/vendor_subdivision.dart';
import '../../utils/app_logger.dart';

class SupabaseVendorSubdivisionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all active subdivisions for a vendor (realtime stream)
  Stream<List<VendorSubdivision>> getSubdivisions(String vendorId) {
    return _supabase
        .from('vendor_subdivisions')
        .stream(primaryKey: ['id'])
        .eq('vendor_id', vendorId)
        .order('created_at', ascending: true)
        .map((data) => data
            .where((row) => row['is_active'] == true)
            .map((row) => VendorSubdivision.fromJson(row))
            .toList());
  }

  /// Get a single subdivision by ID
  Future<VendorSubdivision?> getSubdivision(String subdivisionId) async {
    try {
      final response = await _supabase
          .from('vendor_subdivisions')
          .select()
          .eq('id', subdivisionId)
          .maybeSingle();

      if (response == null) return null;
      return VendorSubdivision.fromJson(response);
    } catch (e) {
      AppLogger.error('Error fetching vendor subdivision', error: e);
      return null;
    }
  }

  /// Create a new subdivision
  Future<String> createSubdivision(VendorSubdivision subdivision) async {
    try {
      final now = DateTime.now().toIso8601String();
      final data = subdivision.toJson();
      data['created_at'] = now;
      data['updated_at'] = now;

      final response = await _supabase
          .from('vendor_subdivisions')
          .insert(data)
          .select('id')
          .single();

      AppLogger.info(
        'Vendor subdivision created',
        metadata: {'subdivisionId': response['id'], 'name': subdivision.name},
      );
      return response['id'] as String;
    } catch (e) {
      AppLogger.error('Error creating vendor subdivision', error: e);
      throw Exception('Error creating subdivision: $e');
    }
  }

  /// Update an existing subdivision
  Future<void> updateSubdivision(VendorSubdivision subdivision) async {
    try {
      final data = subdivision.toJson();
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('vendor_subdivisions')
          .update(data)
          .eq('id', subdivision.id);

      AppLogger.info(
        'Vendor subdivision updated',
        metadata: {'subdivisionId': subdivision.id},
      );
    } catch (e) {
      AppLogger.error('Error updating vendor subdivision', error: e);
      throw Exception('Error updating subdivision: $e');
    }
  }

  /// Soft-delete a subdivision
  Future<void> deleteSubdivision(String subdivisionId) async {
    try {
      await _supabase
          .from('vendor_subdivisions')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subdivisionId);

      AppLogger.info(
        'Vendor subdivision archived',
        metadata: {'subdivisionId': subdivisionId},
      );
    } catch (e) {
      AppLogger.error('Error archiving vendor subdivision', error: e);
      throw Exception('Error archiving subdivision: $e');
    }
  }

  /// Fetch every active subdivision in a workspace — used by the Files screen
  /// to resolve a file's vendor via `project.vendorSubdivisionId` without
  /// round-tripping per vendor.
  Future<List<VendorSubdivision>> getWorkspaceSubdivisions(
    String workspaceId,
  ) async {
    try {
      final response = await _supabase
          .from('vendor_subdivisions')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('is_active', true);

      return (response as List)
          .map((row) => VendorSubdivision.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching workspace subdivisions', error: e);
      return [];
    }
  }

  /// Get all subdivisions for a vendor (non-stream, for dropdowns)
  Future<List<VendorSubdivision>> getSubdivisionsForVendor(
    String vendorId,
  ) async {
    try {
      final response = await _supabase
          .from('vendor_subdivisions')
          .select()
          .eq('vendor_id', vendorId)
          .eq('is_active', true)
          .order('name', ascending: true);

      return response
          .map((row) => VendorSubdivision.fromJson(row))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching subdivisions for vendor', error: e);
      return [];
    }
  }

  /// Get projects linked to a specific vendor subdivision
  Future<List<Map<String, dynamic>>> getProjectsForSubdivision(
    String subdivisionId,
  ) async {
    try {
      final response = await _supabase
          .from('projects')
          .select('id, name, status')
          .eq('vendor_subdivision_id', subdivisionId)
          .order('updated_at', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('Error fetching projects for subdivision', error: e);
      return [];
    }
  }
}
