import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/asset_event.dart';
import '../../../models/user.dart';
import '../../../services/supabase/asset_event_service.dart';
import '../../../services/supabase/user_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/user_facing_error.dart';

/// Activity timeline for an asset — read-only feed of events from the
/// `asset_events` audit log. Resolves actor names from the users table
/// once per render and caches them for the lifetime of this widget.
class AssetActivitySection extends StatefulWidget {
  final String assetId;

  const AssetActivitySection({super.key, required this.assetId});

  @override
  State<AssetActivitySection> createState() => _AssetActivitySectionState();
}

class _AssetActivitySectionState extends State<AssetActivitySection> {
  final _service = SupabaseAssetEventService();
  final Map<String, AppUser?> _userCache = {};

  Future<AppUser?> _resolveActor(String? actorId) async {
    if (actorId == null) return null;
    if (_userCache.containsKey(actorId)) return _userCache[actorId];
    final user = await SupabaseUserService().getUserById(actorId);
    _userCache[actorId] = user;
    return user;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(),
            StreamBuilder<List<AssetEvent>>(
              stream: _service.streamEvents(widget.assetId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: SelectableText(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load activity',
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final events = snapshot.data ?? const <AssetEvent>[];
                if (events.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      'No activity yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (int i = 0; i < events.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _EventRow(
                        event: events[i],
                        resolveActor: _resolveActor,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final AssetEvent event;
  final Future<AppUser?> Function(String? id) resolveActor;

  const _EventRow({required this.event, required this.resolveActor});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: resolveActor(event.actorId),
      builder: (context, snapshot) {
        final actorName = _actorLabel(snapshot.data);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _actionColor(event.action).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _actionIcon(event.action),
                  size: 16,
                  color: _actionColor(event.action),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: actorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          TextSpan(
                            text: ' ${_describeAction(event)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatRelative(event.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _actorLabel(AppUser? user) {
    if (user == null) return 'Someone';
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      return user.displayName!;
    }
    if (user.email.isNotEmpty) return user.email;
    return 'Someone';
  }

  String _describeAction(AssetEvent event) {
    final p = event.payload;
    switch (event.action) {
      case 'created':
        final name = p['name'] as String?;
        return name == null ? 'created this equipment' : 'created "$name"';
      case 'renamed':
        final from = p['from'] as String?;
        final to = p['to'] as String?;
        if (from != null && to != null) {
          return 'renamed it from "$from" to "$to"';
        }
        return 'renamed this equipment';
      case 'status_changed':
        final from = p['from'] as String?;
        final to = p['to'] as String?;
        if (from != null && to != null) {
          return 'changed status from $from to $to';
        }
        if (to != null) return 'changed status to $to';
        return 'changed the status';
      case 'category_changed':
        final to = p['to'] as String?;
        return to == null
            ? 'changed the category'
            : 'changed category to $to';
      case 'location_changed':
        final to = p['to'] as String?;
        return to == null || to.isEmpty
            ? 'cleared the location'
            : 'set location to "$to"';
      case 'assigned_project':
        return 'assigned to a project';
      case 'assigned_user':
        return 'assigned to a team member';
      case 'unassigned':
        return 'unassigned this equipment';
      case 'photo_added':
        final n = (p['count'] as num?)?.toInt() ?? 1;
        return n == 1 ? 'added a photo' : 'added $n photos';
      case 'photo_removed':
        final n = (p['count'] as num?)?.toInt() ?? 1;
        return n == 1 ? 'removed a photo' : 'removed $n photos';
      case 'tag_added':
        final tag = p['tag'] as String?;
        return tag == null ? 'added a tag' : 'added tag "$tag"';
      case 'tag_removed':
        final tag = p['tag'] as String?;
        return tag == null ? 'removed a tag' : 'removed tag "$tag"';
      case 'retired':
        return 'marked this equipment retired';
      case 'restored':
        final to = p['status'] as String?;
        return to == null ? 'restored this equipment' : 'restored it to $to';
      case 'deleted':
        return 'deleted this equipment';
      case 'updated':
        return 'updated the equipment';
      default:
        return event.action.replaceAll('_', ' ');
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'created':
        return Icons.add_circle_outline;
      case 'renamed':
        return Icons.drive_file_rename_outline;
      case 'status_changed':
        return Icons.flag_outlined;
      case 'category_changed':
        return Icons.category_outlined;
      case 'location_changed':
        return Icons.place_outlined;
      case 'assigned_project':
      case 'assigned_user':
        return Icons.assignment_ind_outlined;
      case 'unassigned':
        return Icons.link_off;
      case 'photo_added':
        return Icons.photo_camera_outlined;
      case 'photo_removed':
        return Icons.no_photography_outlined;
      case 'tag_added':
        return Icons.label_outline;
      case 'tag_removed':
        return Icons.label_off_outlined;
      case 'retired':
        return Icons.archive_outlined;
      case 'restored':
        return Icons.unarchive_outlined;
      case 'deleted':
        return Icons.delete_outline;
      default:
        return Icons.edit_outlined;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'created':
        return AppColors.success;
      case 'retired':
      case 'deleted':
      case 'photo_removed':
      case 'tag_removed':
        return AppColors.error;
      case 'status_changed':
      case 'restored':
        return AppColors.warning;
      case 'assigned_project':
      case 'assigned_user':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatRelative(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, y').format(when);
  }
}
