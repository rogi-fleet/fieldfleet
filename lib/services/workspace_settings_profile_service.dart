import '../models/workspace_settings_profile.dart';

class WorkspaceSettingsProfileService {
  Future<List<WorkspaceSettingsProfile>> getProfiles({
    required String workspaceId,
  }) async {
    throw UnsupportedError('Workspace settings profiles require Supabase.');
  }

  Future<WorkspaceSettingsProfile> createFromCurrentWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    throw UnsupportedError('Workspace settings profiles require Supabase.');
  }

  Future<void> renameProfile({
    required String profileId,
    required String name,
  }) async {
    throw UnsupportedError('Workspace settings profiles require Supabase.');
  }

  Future<void> deleteProfile({required String profileId}) async {
    throw UnsupportedError('Workspace settings profiles require Supabase.');
  }

  Future<void> applyProfile({
    required String workspaceId,
    required String profileId,
  }) async {
    throw UnsupportedError('Workspace settings profiles require Supabase.');
  }
}
