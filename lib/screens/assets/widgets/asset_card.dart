import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/asset.dart';
import '../../../models/asset_category.dart';
import '../../../models/asset_category_config.dart';
import '../../../models/maintenance_log.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../services/supabase/maintenance_service.dart';
import '../../../services/supabase/user_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/currency_utils.dart';
import '../../../utils/project_terminology.dart';
import '../../../widgets/asset_form_popup.dart';
import '../../../widgets/common/card_placeholder_background.dart';
import '../../../widgets/common/entity_card_actions_menu.dart';
import '../../../widgets/common/status_chip.dart';

class AssetCard extends StatefulWidget {
  final Asset asset;
  final AssetCategoryConfig? categoryConfig;
  final VoidCallback? onRetire;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onSelectionChanged;

  const AssetCard({
    super.key,
    required this.asset,
    this.categoryConfig,
    this.onRetire,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectionChanged,
  });

  @override
  State<AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends State<AssetCard> {
  Future<MaintenanceLog?>? _latestLogFuture;
  Future<String?>? _assigneeNameFuture;

  @override
  void initState() {
    super.initState();
    _latestLogFuture = _fetchLatestLog();
    _assigneeNameFuture = _fetchAssigneeName();
  }

  @override
  void didUpdateWidget(AssetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _latestLogFuture = _fetchLatestLog();
    }
    if (oldWidget.asset.assignedToProjectId != widget.asset.assignedToProjectId ||
        oldWidget.asset.assignedToUserId != widget.asset.assignedToUserId) {
      _assigneeNameFuture = _fetchAssigneeName();
    }
  }

  Future<MaintenanceLog?> _fetchLatestLog() async {
    final logs =
        await SupabaseMaintenanceService().getLogsOnce(widget.asset.id);
    return logs.isEmpty ? null : logs.first;
  }

  Future<String?> _fetchAssigneeName() async {
    final projectId = widget.asset.assignedToProjectId;
    if (projectId != null && projectId.isNotEmpty) {
      final project = await ServiceLocator.projectService.getProject(projectId);
      return project?.name;
    }
    final userId = widget.asset.assignedToUserId;
    if (userId != null && userId.isNotEmpty) {
      final user = await SupabaseUserService().getUserById(userId);
      if (user == null) return null;
      final name = user.displayName;
      if (name != null && name.isNotEmpty) return name;
      return user.email.isEmpty ? null : user.email;
    }
    return null;
  }

  Asset get asset => widget.asset;
  VoidCallback? get onRetire => widget.onRetire;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final selectionMode = widget.selectionMode;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.cardBorder,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (selectionMode) {
            widget.onSelectionChanged?.call(!isSelected);
          } else {
            context.push('/equipment/${asset.id}');
          }
        },
        onLongPress: widget.onLongPress,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 300;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(context, compact: compact),
                Padding(
                  padding: EdgeInsets.all(compact ? 12 : AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetaRow(compact: compact),
                      const SizedBox(height: AppSpacing.sm),
                      if (!compact) ...[
                        FutureBuilder<String?>(
                          future: _assigneeNameFuture,
                          builder: (context, snapshot) {
                            return _buildInfoRow(
                              icon: Icons.link_outlined,
                              text: _assignmentSummary(
                                context,
                                resolvedName: snapshot.data,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                      ],
                      _buildInfoRow(
                        icon: Icons.receipt_long_outlined,
                        text: _purchaseSummary(context),
                      ),
                      if (_categorySummary() != null) ...[
                        const SizedBox(height: 6),
                        _buildCategoryRow(),
                      ],
                      if (asset.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildTagStrip(),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        asset.description?.isNotEmpty == true
                            ? asset.description!
                            : 'No description',
                        style: const TextStyle(color: AppColors.textSecondary),
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      FutureBuilder<MaintenanceLog?>(
                        future: _latestLogFuture,
                        builder: (context, snapshot) {
                          final overdue = _isOverdue(snapshot.data);
                          if (!_needsAttention(overdue: overdue)) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _buildAttentionBanner(
                              compact,
                              overdue: overdue,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, {required bool compact}) {
    final heroPhoto = asset.photoUrls.isNotEmpty ? asset.photoUrls.first : null;
    final categoryIcon = widget.categoryConfig?.icon ??
        AssetCategory.fromName(asset.category).icon;
    return SizedBox(
      height: compact ? 130 : 160,
      child: Stack(
        children: [
          Positioned.fill(
            child: heroPhoto != null
                ? CachedNetworkImage(
                    imageUrl: heroPhoto,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const CardPlaceholderBackground(),
                    errorWidget: (_, __, ___) => CardPlaceholderBackground(
                      centerOverlay: const Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: Colors.white70,
                      ),
                    ),
                  )
                : CardPlaceholderBackground(
                    centerOverlay: Icon(
                      categoryIcon,
                      size: 64,
                      color: Colors.white70,
                    ),
                  ),
          ),
          if (widget.selectionMode)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: widget.isSelected
                      ? AppColors.primary.withValues(alpha: 0.20)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: widget.selectionMode
                ? _SelectionBadge(selected: widget.isSelected)
                : _StatusChip(status: asset.status),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              children: [
                _buildQrBadge(compact: compact),
                const SizedBox(width: 8),
                EntityCardActionsMenu(
                  compact: true,
                  items: _menuItems(),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        showAssetFormPopup(context, assetId: asset.id);
                        break;
                      case 'details':
                        context.push('/equipment/${asset.id}');
                        break;
                      case 'retire':
                        onRetire?.call();
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Text(
                asset.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<EntityCardActionItem> _menuItems() {
    final items = <EntityCardActionItem>[
      const EntityCardActionItem(
        value: 'edit',
        label: 'Edit',
        icon: Icons.edit,
      ),
      const EntityCardActionItem(
        value: 'details',
        label: 'View details',
        icon: Icons.open_in_new,
      ),
    ];

    if (asset.status != 'retired' && onRetire != null) {
      items.add(
        const EntityCardActionItem(
          value: 'retire',
          label: 'Mark retired',
          icon: Icons.archive_outlined,
          isDestructive: true,
        ),
      );
    }

    return items;
  }

  Widget _buildMetaRow({required bool compact}) {
    return _MetaPill(
      icon: Icons.tag,
      label: asset.serialNumber?.isNotEmpty == true
          ? asset.serialNumber!
          : 'No serial',
    );
  }

  Widget _buildQrBadge({required bool compact}) {
    if (asset.qrCode == null || asset.qrCode!.isEmpty) {
      return Container(
        padding: EdgeInsets.all(compact ? 8 : 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: AppRadius.badgeRadius,
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(
          Icons.qr_code_2_outlined,
          size: compact ? 18 : 24,
          color: AppColors.textSecondary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: QrImageView(
        data: asset.qrCode!,
        size: compact ? 34 : 56,
        gapless: false,
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _assignmentSummary(BuildContext context, {String? resolvedName}) {
    if ((asset.assignedToProjectId ?? '').isNotEmpty) {
      if (resolvedName != null && resolvedName.isNotEmpty) {
        return resolvedName;
      }
      final projectTerminology =
          context.read<WorkspaceProvider>().projectTerminology;
      final singular = singularProjectTerminology(projectTerminology);
      return 'Assigned to ${singular.toLowerCase()}';
    }
    if ((asset.assignedToUserId ?? '').isNotEmpty) {
      return resolvedName != null && resolvedName.isNotEmpty
          ? resolvedName
          : 'Assigned to team member';
    }
    return 'Unassigned';
  }

  String? _categorySummary() {
    final categoryName = asset.category;
    final hasLocation = (asset.location ?? '').isNotEmpty;
    final hasCategory = categoryName.isNotEmpty &&
        categoryName.toLowerCase() != 'other';
    if (!hasCategory && !hasLocation) return null;
    if (hasCategory && hasLocation) {
      return '$categoryName • ${asset.location}';
    }
    return hasCategory ? categoryName : asset.location;
  }

  Widget _buildTagStrip() {
    const maxVisible = 3;
    final tags = asset.tags;
    final visible = tags.take(maxVisible).toList();
    final overflow = tags.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in visible) _TagPill(label: tag),
        if (overflow > 0) _TagPill(label: '+$overflow', muted: true),
      ],
    );
  }

  Widget _buildCategoryRow() {
    final hasLocation = (asset.location ?? '').isNotEmpty;
    final summary = _categorySummary();
    if (summary == null) return const SizedBox.shrink();
    final config = widget.categoryConfig;
    final fallback = AssetCategory.fromName(asset.category);
    final isGenericCategory = config == null && fallback == AssetCategory.other;
    return _buildInfoRow(
      icon: hasLocation && isGenericCategory
          ? Icons.place_outlined
          : (config?.icon ?? fallback.icon),
      text: summary,
    );
  }

  String _purchaseSummary(BuildContext context) {
    final parts = <String>[];
    if (asset.purchaseDate != null) {
      parts.add(_formatDate(asset.purchaseDate!));
    }
    if (asset.purchasePrice != null) {
      final currencyCode = context.read<WorkspaceProvider>().currencyCode;
      parts.add(
        CurrencyUtils.formatCurrency(asset.purchasePrice!, currencyCode),
      );
    }
    if (parts.isEmpty) {
      return 'No purchase details';
    }
    return parts.join(' • ');
  }

  bool _isOverdue(MaintenanceLog? latest) {
    final next = latest?.nextMaintenanceDate;
    return next != null && next.isBefore(DateTime.now());
  }

  bool _needsAttention({required bool overdue}) {
    return overdue ||
        asset.status == 'maintenance' ||
        (asset.serialNumber ?? '').isEmpty;
  }

  Widget _buildAttentionBanner(bool compact, {required bool overdue}) {
    final isOverdue = overdue;
    final isInMaintenance = asset.status == 'maintenance';

    final (message, foreground, background, border) = isOverdue
        ? (
            'Service overdue',
            AppColors.error,
            AppColors.error.withValues(alpha: 0.10),
            AppColors.error.withValues(alpha: 0.35),
          )
        : isInMaintenance
            ? (
                'In maintenance',
                AppColors.warningDark,
                AppColors.warningLight,
                AppColors.warning.withValues(alpha: 0.35),
              )
            : (
                'Add serial number',
                AppColors.warningDark,
                AppColors.warningLight,
                AppColors.warning.withValues(alpha: 0.35),
              );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            isOverdue ? Icons.event_busy : Icons.warning_amber_rounded,
            size: 14,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              compact ? message : 'Needs attention: $message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _SelectionBadge extends StatelessWidget {
  final bool selected;

  const _SelectionBadge({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.white,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.cardBorder,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 18, color: Colors.white)
          : null,
    );
  }
}

class _TagPill extends StatelessWidget {
  final String label;
  final bool muted;

  const _TagPill({required this.label, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: muted
            ? AppColors.surfaceAlt
            : AppColors.primary.withValues(alpha: 0.10),
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(
          color: muted
              ? AppColors.cardBorder
              : AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted ? AppColors.textSecondary : AppColors.primary,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status.isEmpty
        ? 'Unknown'
        : status[0].toUpperCase() + status.substring(1);
    return StatusChip(label: label, color: _statusColor(status));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'available':
        return AppColors.info;
      case 'assigned':
        return AppColors.primary;
      case 'maintenance':
        return AppColors.warning;
      case 'retired':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }
}
