/// Append-only audit log entry for an asset. One row per meaningful
/// mutation (created, status changed, assigned, photos added, retired,
/// etc.). Rendered as the Activity timeline on the asset detail screen.
class AssetEvent {
  final String id;
  final String workspaceId;
  final String assetId;
  final String? actorId;
  final String action;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const AssetEvent({
    required this.id,
    required this.workspaceId,
    required this.assetId,
    required this.actorId,
    required this.action,
    required this.payload,
    required this.createdAt,
  });
}
