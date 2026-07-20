import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/vendor.dart';
import '../../theme/theme.dart';

class VendorProductsServicesTab extends StatelessWidget {
  final Vendor vendor;

  const VendorProductsServicesTab({super.key, required this.vendor});

  @override
  Widget build(BuildContext context) {
    final activeContacts = vendor.getActiveContacts();
    final primaryContact = vendor.getPrimaryContact();
    final activeLicenses = vendor.licenses
        .where((license) => license.isActive)
        .toList();
    final expiredLicenses = activeLicenses
        .where((license) => license.isExpired)
        .length;
    final expiringLicenses = activeLicenses
        .where((license) => !license.isExpired && license.isExpiringSoon)
        .length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Service Profile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.category_outlined,
                  label: 'Category',
                  value: vendor.category,
                ),
                _InfoRow(
                  icon: Icons.construction_outlined,
                  label: 'Vendor Type',
                  value: vendor.vendorType,
                ),
                if (vendor.paymentTerms != null)
                  _InfoRow(
                    icon: Icons.schedule_outlined,
                    label: 'Payment Terms',
                    value: vendor.paymentTerms!.displayName,
                  ),
                if (vendor.discountRate != null)
                  _InfoRow(
                    icon: Icons.percent_outlined,
                    label: 'Discount Rate',
                    value:
                        '${(vendor.discountRate! * 100).toStringAsFixed(1)}%',
                  ),
                if (vendor.accountNumber?.trim().isNotEmpty == true)
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Account Number',
                    value: vendor.accountNumber!,
                  ),
                if (vendor.taxId?.trim().isNotEmpty == true)
                  _InfoRow(
                    icon: Icons.numbers_outlined,
                    label: 'Tax ID',
                    value: vendor.taxId!,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Capabilities',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(vendor.category),
                      avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                    ),
                    Chip(
                      label: Text(vendor.vendorType),
                      avatar: const Icon(Icons.sell_outlined, size: 18),
                    ),
                    ...vendor.tags.map(
                      (tag) => Chip(
                        label: Text(tag),
                        avatar: const Icon(Icons.label_outline, size: 18),
                      ),
                    ),
                  ],
                ),
                if (vendor.tags.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No additional product or service tags have been added for this vendor yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Relationship Snapshot',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricChip(
                      label: vendor.isPreferred
                          ? 'Preferred Vendor'
                          : 'Standard Vendor',
                      color: vendor.isPreferred
                          ? AppColors.success
                          : AppColors.textTertiary,
                      icon: vendor.isPreferred
                          ? Icons.star_outline
                          : Icons.store_outlined,
                    ),
                    _MetricChip(
                      label:
                          '${activeContacts.length} active contact${activeContacts.length == 1 ? '' : 's'}',
                      color: AppColors.info,
                      icon: Icons.people_outline,
                    ),
                    _MetricChip(
                      label: vendor.hasValidInsurance
                          ? 'Insurance on file'
                          : 'Insurance missing/expired',
                      color: vendor.hasValidInsurance
                          ? AppColors.success
                          : AppColors.warning,
                      icon: Icons.verified_user_outlined,
                    ),
                    _MetricChip(
                      label: expiredLicenses > 0
                          ? '$expiredLicenses expired license${expiredLicenses == 1 ? '' : 's'}'
                          : '${activeLicenses.length} active license${activeLicenses.length == 1 ? '' : 's'}',
                      color: expiredLicenses > 0
                          ? AppColors.error
                          : AppColors.info,
                      icon: Icons.workspace_premium_outlined,
                    ),
                    if (expiringLicenses > 0)
                      _MetricChip(
                        label: '$expiringLicenses expiring soon',
                        color: AppColors.warning,
                        icon: Icons.schedule_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (primaryContact != null ||
            vendor.website?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Primary Contact',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (primaryContact != null) ...[
                    Text(
                      primaryContact.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (primaryContact.title?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        primaryContact.title!,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (primaryContact.email?.trim().isNotEmpty == true)
                      _ActionRow(
                        icon: Icons.email_outlined,
                        label: primaryContact.email!,
                        onTap: () => _launch('mailto:${primaryContact.email!}'),
                      ),
                    if (primaryContact.phone?.trim().isNotEmpty == true)
                      _ActionRow(
                        icon: Icons.phone_outlined,
                        label: primaryContact.phone!,
                        onTap: () => _launch('tel:${primaryContact.phone!}'),
                      ),
                    if (primaryContact.mobilePhone?.trim().isNotEmpty == true)
                      _ActionRow(
                        icon: Icons.smartphone_outlined,
                        label: primaryContact.mobilePhone!,
                        onTap: () =>
                            _launch('tel:${primaryContact.mobilePhone!}'),
                      ),
                  ],
                  if (vendor.website?.trim().isNotEmpty == true) ...[
                    if (primaryContact != null) const SizedBox(height: 8),
                    _ActionRow(
                      icon: Icons.language_outlined,
                      label: vendor.website!,
                      onTap: () => _launch(vendor.website!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _launch(String raw) async {
    final normalized =
        raw.startsWith('http') ||
            raw.startsWith('mailto:') ||
            raw.startsWith('tel:')
        ? raw
        : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _MetricChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.info),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.info,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
