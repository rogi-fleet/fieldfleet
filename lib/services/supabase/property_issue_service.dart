import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/property_issue.dart';
import '../../utils/app_logger.dart';

/// Staff-side service for property_issues. Portal (unit holder) access goes
/// exclusively through the portal_* RPCs in SupabaseClientPortalService —
/// this service is for the internal Issues tab only, which passes the
/// staff-only RLS policy directly.
class SupabasePropertyIssueService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Watch issues for a property (real-time updates), newest first.
  Stream<List<PropertyIssue>> watchPropertyIssues(String propertyId) {
    return _supabase
        .from('property_issues')
        .stream(primaryKey: ['id'])
        .eq('property_id', propertyId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(PropertyIssue.fromRow).toList());
  }

  Future<void> updateIssueStatus(String issueId, String status) async {
    try {
      final updates = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (status == 'resolved' || status == 'closed') {
        updates['resolved_at'] = DateTime.now().toIso8601String();
        updates['resolved_by'] = _supabase.auth.currentUser?.id;
      } else {
        updates['resolved_at'] = null;
        updates['resolved_by'] = null;
      }
      await _supabase.from('property_issues').update(updates).eq('id', issueId);
    } catch (e) {
      AppLogger.error(
        'Failed to update property issue status',
        error: e,
        metadata: {'issueId': issueId, 'status': status},
      );
      rethrow;
    }
  }
}
