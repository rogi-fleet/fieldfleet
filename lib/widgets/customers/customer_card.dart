import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/customer.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/currency_utils.dart';
import '../../utils/project_terminology.dart';
import '../common/card_placeholder_background.dart';
import '../common/entity_archived_badge.dart';
import '../common/entity_card_actions_menu.dart';
import '../common/hover_card.dart';
import 'customer_type_badge.dart';

class CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onViewDetails;
  final VoidCallback? onToggleArchive;
  final int projectCount;
  final int openJobs;
  final int closedJobs;
  final double collectedRevenue;
  final DateTime? lastActivityDate;
  final EdgeInsetsGeometry margin;
  final double minHeight;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.onTap,
    this.onEdit,
    this.onViewDetails,
    this.onToggleArchive,
    this.projectCount = 0,
    this.openJobs = 0,
    this.closedJobs = 0,
    this.collectedRevenue = 0,
    this.lastActivityDate,
    this.margin = const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
    this.minHeight = 250,
  });

  @override
  Widget build(BuildContext context) {
    final displayTitle = customer.companyName?.trim().isNotEmpty == true
        ? customer.companyName!
        : customer.name;
    final pluralTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;

    return HoverCard(
      margin: margin,
      onTap: onTap,
      child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 300;

            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                children: [
                  SizedBox(
                    height: compact ? 110 : 124,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Positioned.fill(child: _buildHeaderBackground()),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: CustomerTypeBadge(
                            customerType: customer.customerType,
                            small: true,
                          ),
                        ),
                        if (_menuItems().isNotEmpty)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: EntityCardActionsMenu(
                              items: _menuItems(),
                              compact: true,
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    onEdit?.call();
                                    break;
                                  case 'details':
                                    (onViewDetails ?? onTap).call();
                                    break;
                                  case 'archive':
                                    onToggleArchive?.call();
                                    break;
                                }
                              },
                            ),
                          ),
                        if (!customer.isActive)
                          Positioned(
                            top: 10,
                            right: _menuItems().isNotEmpty ? 52 : 10,
                            child: const EntityArchivedBadge(),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0),
                                  Colors.black.withValues(alpha: 0.75),
                                ],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (customer.businessPhone != null)
                                  Row(
                                    children: [
                                      Icon(Icons.phone, size: 12, color: Colors.white.withValues(alpha: 0.85)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          customer.businessPhone!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (customer.businessEmail != null)
                                  Row(
                                    children: [
                                      Icon(Icons.email, size: 12, color: Colors.white.withValues(alpha: 0.85)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          customer.businessEmail!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(compact ? 12 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPrimaryContactRow(compact),
                        if (!compact && _addressLine() != null) ...[
                          const SizedBox(height: 8),
                          _buildInfoItem(
                            icon: Icons.location_on_outlined,
                            text: _addressLine()!,
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (_needsAttention()) ...[
                          _buildAttentionBanner(compact),
                          const SizedBox(height: 10),
                        ],
                        const Divider(height: 1, color: AppColors.cardBorder),
                        const SizedBox(height: 10),
                        _buildStatsStrip(context, compact),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoItem(
                                icon: Icons.work_outline,
                                text:
                                    '$projectCount ${projectTerminologyForCount(projectCount, pluralTerminology).toLowerCase()}',
                                muted: false,
                              ),
                            ),
                            if (lastActivityDate != null && !compact)
                              Flexible(
                                child: Text(
                                  'Updated ${timeago.format(lastActivityDate!)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
      ),
    );
  }

  List<EntityCardActionItem> _menuItems() {
    final items = <EntityCardActionItem>[];
    if (onEdit != null) {
      items.add(
        const EntityCardActionItem(
          value: 'edit',
          label: 'Edit',
          icon: Icons.edit,
        ),
      );
    }
    items.add(
      const EntityCardActionItem(
        value: 'details',
        label: 'View details',
        icon: Icons.open_in_new,
      ),
    );
    if (onToggleArchive != null) {
      items.add(
        EntityCardActionItem(
          value: 'archive',
          label: customer.isActive ? 'Archive' : 'Restore',
          icon: customer.isActive ? Icons.archive_outlined : Icons.unarchive,
          isDestructive: customer.isActive,
        ),
      );
    }
    return items;
  }

  Widget _buildHeaderBackground() {
    if (customer.logoUrl != null && customer.logoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: customer.logoUrl!,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => _buildFallbackBackground(),
      );
    }

    return _buildFallbackBackground();
  }

  Widget _buildFallbackBackground() {
    return const CardPlaceholderBackground();
  }

  Widget _buildPrimaryContactRow(bool compact) {
    final primary = customer.getPrimaryContact();
    if (primary == null) {
      return const Text(
        'No primary contact',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }

    final contactParts = [
      primary.name,
      if ((primary.phone ?? '').isNotEmpty) primary.phone!,
      if (!compact && (primary.email ?? '').isNotEmpty) primary.email!,
    ];

    return _buildWrappedInfoItem(
      icon: Icons.person_outline,
      parts: contactParts,
    );
  }

  String? _addressLine() {
    if (customer.fullAddress != null && customer.fullAddress!.isNotEmpty) {
      return AddressFormatter.condense(customer.fullAddress!);
    }

    final cityState = [
      if ((customer.city ?? '').isNotEmpty) customer.city!,
      if ((customer.state ?? '').isNotEmpty) customer.state!,
    ];

    if (cityState.isNotEmpty) {
      return cityState.join(', ');
    }

    return null;
  }

  bool _needsAttention() {
    return customer.getPrimaryContact() == null || _addressLine() == null;
  }

  Widget _buildAttentionBanner(bool compact) {
    final messages = <String>[];
    if (customer.getPrimaryContact() == null) {
      messages.add('add primary contact');
    }
    if (_addressLine() == null) {
      messages.add('add address');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: AppColors.warningDark,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              compact
                  ? 'Needs attention'
                  : 'Needs attention: ${messages.join(' and ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.warningDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String text,
    bool muted = true,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: muted ? AppColors.textSecondary : AppColors.textPrimary,
              fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsStrip(BuildContext context, bool compact) {
    final currencyCode = context.watch<WorkspaceProvider>().currencyCode;
    final collectedText = compact
        ? CurrencyUtils.formatCurrencyCompact(collectedRevenue, currencyCode)
        : CurrencyUtils.formatCurrency(collectedRevenue, currencyCode);
    return Row(
      children: [
        Expanded(
          child: _buildStatTile(
            label: 'Open',
            value: '$openJobs',
            color: AppColors.primary,
          ),
        ),
        Expanded(
          child: _buildStatTile(
            label: 'Closed',
            value: '$closedJobs',
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          flex: 2,
          child: _buildStatTile(
            label: 'Collected',
            value: collectedText,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildWrappedInfoItem({
    required IconData icon,
    required List<String> parts,
    bool muted = true,
  }) {
    final color = muted ? AppColors.textSecondary : AppColors.textPrimary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: AppColors.textTertiary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0)
                    TextSpan(
                      text: ' • ',
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  TextSpan(
                    text: parts[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            softWrap: true,
          ),
        ),
      ],
    );
  }
}
