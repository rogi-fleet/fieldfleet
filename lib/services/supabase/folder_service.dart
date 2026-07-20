import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/file_folder.dart';
import '../../utils/app_logger.dart';

/// Supabase implementation of FolderService
class SupabaseFolderService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Creates a new folder
  Future<FileFolder> createFolder({
    required String workspaceId,
    required String projectId,
    required String name,
    String? parentFolderId,
    required String createdBy,
    bool isVirtual = false,
    String? virtualType,
  }) async {
    try {
      final now = DateTime.now();

      final folderData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'name': name,
        'parent_folder_id': parentFolderId,
        'is_virtual': isVirtual,
        'virtual_type': virtualType,
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('file_folders')
          .insert(folderData)
          .select()
          .single();

      return _toFileFolder(response);
    } catch (e) {
      AppLogger.error('Failed to create folder', error: e, metadata: {
        'name': name,
        'projectId': projectId,
      });
      throw Exception('Failed to create folder: $e');
    }
  }

  /// Renames a folder
  Future<void> renameFolder(String folderId, String newName) async {
    try {
      await _supabase.from('file_folders').update({
        'name': newName,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', folderId);
    } catch (e) {
      AppLogger.error('Failed to rename folder', error: e, metadata: {
        'folderId': folderId,
        'newName': newName,
      });
      throw Exception('Failed to rename folder: $e');
    }
  }

  /// Deletes a folder
  Future<void> deleteFolder(String folderId) async {
    try {
      await _supabase.from('file_folders').delete().eq('id', folderId);
    } catch (e) {
      AppLogger.error('Failed to delete folder', error: e, metadata: {
        'folderId': folderId,
      });
      throw Exception('Failed to delete folder: $e');
    }
  }

  /// Gets all folders for a project as a stream
  Stream<List<FileFolder>> getProjectFolders(String workspaceId, String projectId) {
    return _supabase
        .from('file_folders')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .map((data) {
          final filtered = data
              .where((row) => row['project_id'] == projectId)
              .map((row) => _toFileFolder(row))
              .toList();
          filtered.sort(_compareFolders);
          // Dedupe defensively. The realtime `.stream()` can momentarily
          // emit a row twice when a backfill INSERT (see
          // [ensureModuleVirtualFolders]) lands at the same instant the
          // subscription's initial snapshot is delivered — both the snapshot
          // and the INSERT event carry the new row, producing a duplicate
          // tree node (e.g. two "Warranties" folders) that sticks until
          // refresh. We also collapse virtual folders that share a
          // virtual_type so a stale duplicate row from a past race can never
          // render twice. Keep the canonically-first row of each group.
          final seenIds = <String>{};
          final seenVirtualTypes = <String>{};
          final deduped = <FileFolder>[];
          for (final folder in filtered) {
            if (!seenIds.add(folder.id)) continue;
            final vType = folder.virtualType;
            if (folder.isVirtual && vType != null && vType.isNotEmpty) {
              if (!seenVirtualTypes.add(vType)) continue;
            }
            deduped.add(folder);
          }
          return deduped;
        });
  }

  /// Gets a single folder by ID
  Future<FileFolder?> getFolder(String folderId) async {
    try {
      final response = await _supabase
          .from('file_folders')
          .select()
          .eq('id', folderId)
          .maybeSingle();

      if (response == null) return null;
      return _toFileFolder(response);
    } catch (e) {
      AppLogger.error('Failed to get folder', error: e, metadata: {
        'folderId': folderId,
      });
      return null;
    }
  }

  /// Canonical display order for virtual folders. Real (user-created)
  /// folders fall back to createdAt; virtual folders use this index so
  /// backfilled folders (e.g. Specifications added to an older project
  /// long after Inspections) still appear in the intended position.
  static const List<String> _virtualFolderOrder = [
    'tasks',
    'messages',
    'forms',
    'documents',
    'plans',
    'daily-logs',
    'inspections',
    'specifications',
    'punch-list',
    'warranties',
  ];

  static int _virtualRank(FileFolder f) {
    if (!f.isVirtual) return -1;
    final idx = _virtualFolderOrder.indexOf(f.virtualType ?? '');
    return idx < 0 ? _virtualFolderOrder.length : idx;
  }

  static int _compareFolders(FileFolder a, FileFolder b) {
    // Real folders sort before virtual ones, by createdAt.
    if (a.isVirtual != b.isVirtual) {
      return a.isVirtual ? 1 : -1;
    }
    if (a.isVirtual && b.isVirtual) {
      final cmp = _virtualRank(a).compareTo(_virtualRank(b));
      if (cmp != 0) return cmp;
    }
    return a.createdAt.compareTo(b.createdAt);
  }

  /// Default virtual folders seeded under the Content folder. Tasks,
  /// Messages, Forms, Documents are file-attachment lists; Daily Logs,
  /// Inspections, Punch List, Warranties, Plans and Specifications are
  /// module sections that used to be top-level project tabs.
  static const List<Map<String, String>> _defaultVirtualFolders = [
    {'name': 'Task Files', 'virtualType': 'tasks'},
    {'name': 'Message Files', 'virtualType': 'messages'},
    {'name': 'Forms', 'virtualType': 'forms'},
    {'name': 'Financials', 'virtualType': 'documents'},
    {'name': 'Plans', 'virtualType': 'plans'},
    {'name': 'Daily Logs', 'virtualType': 'daily-logs'},
    {'name': 'Inspections', 'virtualType': 'inspections'},
    {'name': 'Specifications', 'virtualType': 'specifications'},
    {'name': 'Punch List', 'virtualType': 'punch-list'},
    {'name': 'Warranties', 'virtualType': 'warranties'},
  ];

  /// Backfills any missing entries from [_defaultVirtualFolders] for a
  /// project that already exists. Used to introduce new virtual-folder
  /// sections (Plans, Specifications, Daily Logs, etc.) without a
  /// data-migration step. Idempotent — safe to call on every Files tab
  /// open.
  Future<void> ensureDefaultVirtualFolders({
    required String workspaceId,
    required String projectId,
    required String createdBy,
  }) async {
    try {
      final existing = await _supabase
          .from('file_folders')
          .select('virtual_type, parent_folder_id')
          .eq('workspace_id', workspaceId)
          .eq('project_id', projectId)
          .eq('is_virtual', true);
      final existingTypes = <String>{
        for (final row in existing)
          if (row['virtual_type'] != null) row['virtual_type'] as String,
      };
      final missing = _defaultVirtualFolders
          .where((vf) => !existingTypes.contains(vf['virtualType']))
          .toList();
      if (missing.isEmpty) return;

      // Find the Content parent folder to nest under (fall back to root).
      final contentRows = await _supabase
          .from('file_folders')
          .select('id')
          .eq('workspace_id', workspaceId)
          .eq('project_id', projectId)
          .eq('name', 'Content')
          .eq('is_virtual', false)
          .limit(1);
      final contentFolderId =
          contentRows.isNotEmpty ? contentRows.first['id'] as String? : null;

      final now = DateTime.now();
      for (final vf in missing) {
        await _supabase.from('file_folders').insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'name': vf['name'],
          'parent_folder_id': contentFolderId,
          'is_virtual': true,
          'virtual_type': vf['virtualType'],
          'created_by': createdBy,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
    } catch (e) {
      AppLogger.error('Failed to ensure module virtual folders',
          error: e, metadata: {'projectId': projectId});
    }
  }

  /// Initializes default folders for a project if they don't exist
  Future<void> initializeDefaultFolders({
    required String workspaceId,
    required String projectId,
    required String createdBy,
  }) async {
    try {
      // Check if folders already exist
      final existing = await _supabase
          .from('file_folders')
          .select('id')
          .eq('workspace_id', workspaceId)
          .eq('project_id', projectId)
          .limit(1);

      if (existing.isNotEmpty) {
        return;
      }

      final now = DateTime.now();

      // Create General folder
      await _supabase.from('file_folders').insert({
        'workspace_id': workspaceId,
        'project_id': projectId,
        'name': 'General',
        'is_virtual': false,
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Create Content folder and get its ID
      final contentResult = await _supabase.from('file_folders').insert({
        'workspace_id': workspaceId,
        'project_id': projectId,
        'name': 'Content',
        'is_virtual': false,
        'created_by': createdBy,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).select('id').single();

      final contentFolderId = contentResult['id'];

      // Create virtual subfolders under Content
      for (final vf in _defaultVirtualFolders) {
        await _supabase.from('file_folders').insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'name': vf['name'],
          'parent_folder_id': contentFolderId,
          'is_virtual': true,
          'virtual_type': vf['virtualType'],
          'created_by': createdBy,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }

      AppLogger.info('Initialized default folders for project', metadata: {
        'projectId': projectId,
      });
    } catch (e) {
      AppLogger.error('Failed to initialize default folders', error: e, metadata: {
        'projectId': projectId,
      });
      throw Exception('Failed to initialize default folders: $e');
    }
  }

  /// Gets child folders of a parent folder
  List<FileFolder> getChildFolders(List<FileFolder> allFolders, String? parentFolderId) {
    return allFolders
        .where((f) => f.parentFolderId == parentFolderId)
        .toList();
  }

  /// Builds folder tree structure from flat list
  Map<String?, List<FileFolder>> buildFolderTree(List<FileFolder> folders) {
    final tree = <String?, List<FileFolder>>{};
    for (final folder in folders) {
      tree.putIfAbsent(folder.parentFolderId, () => []);
      tree[folder.parentFolderId]!.add(folder);
    }
    return tree;
  }

  /// Convert database row to FileFolder
  FileFolder _toFileFolder(Map<String, dynamic> row) {
    return FileFolder(
      id: row['id'],
      workspaceId: row['workspace_id'],
      projectId: row['project_id'],
      name: row['name'],
      parentFolderId: row['parent_folder_id'],
      isVirtual: row['is_virtual'] ?? false,
      virtualType: row['virtual_type'],
      createdBy: row['created_by'],
      createdAt: DateTime.parse(row['created_at']),
    );
  }
}
