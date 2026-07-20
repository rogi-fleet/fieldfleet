import 'package:flutter/material.dart';
import '../../models/vendor.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../common/card_placeholder_background.dart';
import '../common/entity_archived_badge.dart';
import '../common/entity_card_actions_menu.dart';
import '../common/hover_card.dart';

class VendorCard extends StatelessWidget {
  final Vendor vendor;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onViewDetails;
  final VoidCallback? onToggleArchive;
  final EdgeInsetsGeometry margin;
  final double minHeight;

  const VendorCard({
    super.key,
    required this.vendor,
    required this.onTap,
    this.onEdit,
    this.onViewDetails,
    this.onToggleArchive,
    this.margin = const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
    this.minHeight = 250,
  });

  @override
  Widget build(BuildContext context) {
    final primaryContact = vendor.getPrimaryContact();
    final hasWarnings =
        vendor.hasExpiredLicenses || vendor.hasExpiringSoonInsuranceOrLicenses;

    return HoverCard(
      margin: margin,
      onTap: onTap,
      child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 300;
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: compact ? 110 : 124,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: const CardPlaceholderBackground(),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              vendor.category,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (hasWarnings)
                          Positioned(
                            top: 10,
                            right: !vendor.isActive
                                ? (_menuItems().isNotEmpty ? 104 : 62)
                                : (_menuItems().isNotEmpty ? 52 : 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.errorLight,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 12,
                                    color: AppColors.errorDark,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Alert',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.errorDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (!vendor.isActive)
                          Positioned(
                            top: 10,
                            right: _menuItems().isNotEmpty ? 52 : 10,
                            child: const EntityArchivedBadge(),
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
                                  vendor.companyName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (vendor.dba != null &&
                                    vendor.dba!.isNotEmpty)
                                  Text(
                                    'DBA: ${vendor.dba}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                if (vendor.businessPhone != null ||
                                    vendor.businessEmail != null)
                                  Row(
                                    children: [
                                      if (vendor.businessPhone != null) ...[
                                        Icon(Icons.phone, size: 12, color: Colors.white.withValues(alpha: 0.85)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            vendor.businessPhone!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.85),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (vendor.businessPhone != null && vendor.businessEmail != null)
                                        const SizedBox(width: 12),
                                      if (vendor.businessEmail != null) ...[
                                        Icon(Icons.email, size: 12, color: Colors.white.withValues(alpha: 0.85)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            vendor.businessEmail!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.85),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
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
                        _buildInfoItem(
                          icon: Icons.business_outlined,
                          text: vendor.vendorType,
                        ),
                        if (primaryContact != null) ...[
                          const SizedBox(height: 6),
                          _buildWrappedInfoItem(
                            icon: Icons.person_outline,
                            parts: [
                              primaryContact.name,
                              if ((primaryContact.phone ?? '').isNotEmpty)
                                primaryContact.phone!,
                              if ((primaryContact.email ?? '').isNotEmpty)
                                primaryContact.email!,
                            ],
                          ),
                        ],
                        if (!compact && _addressLine() != null) ...[
                          const SizedBox(height: 6),
                          _buildInfoItem(
                            icon: Icons.location_on_outlined,
                            text: _addressLine()!,
                          ),
                        ],
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: AppColors.cardBorder),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoItem(
                                icon: Icons.category_outlined,
                                text: vendor.category,
                                muted: false,
                              ),
                            ),
                            if (vendor.isPreferred)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warningLight,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.full,
                                  ),
                                ),
                                child: const Text(
                                  'Preferred',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.warningDark,
                                    fontWeight: FontWeight.w700,
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

  String? _addressLine() {
    if (vendor.fullAddress == null || vendor.fullAddress!.isEmpty) {
      return null;
    }
    return AddressFormatter.condense(vendor.fullAddress!);
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
          label: vendor.isActive ? 'Archive' : 'Restore',
          icon: vendor.isActive ? Icons.archive_outlined : Icons.unarchive,
          isDestructive: vendor.isActive,
        ),
      );
    }

    return items;
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String text,
    bool muted = true,
  }) {
    return Row(
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
