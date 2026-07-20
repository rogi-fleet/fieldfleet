import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/customer_contact.dart';
import '../../theme/theme.dart';

class ContactCard extends StatelessWidget {
  final CustomerContact contact;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showPrimaryBadge;

  const ContactCard({
    super.key,
    required this.contact,
    this.onTap,
    this.onDelete,
    this.showPrimaryBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Contact info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            contact.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (contact.isPrimary && showPrimaryBadge) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(AppRadius.r12),
                            ),
                            child: Text(
                              'PRIMARY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (contact.title != null && contact.title!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contact.title!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (contact.phone != null && contact.phone!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            contact.phone!,
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ],
                    if (contact.mobilePhone != null &&
                        contact.mobilePhone!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_android,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            contact.mobilePhone!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (contact.email != null && contact.email!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.email, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              contact.email!,
                              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (contact.phone != null && contact.phone!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone, size: 20),
                      onPressed: () => _launchPhone(contact.phone!),
                      tooltip: 'Call',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  if (contact.mobilePhone != null &&
                      contact.mobilePhone!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone_android, size: 20),
                      onPressed: () => _launchPhone(contact.mobilePhone!),
                      tooltip: 'Call cell',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  if (contact.email != null && contact.email!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.email, size: 20),
                      onPressed: () => _launchEmail(contact.email!),
                      tooltip: 'Email',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  if (onDelete != null && !contact.isPrimary)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: onDelete,
                      tooltip: 'Delete',
                      color: Colors.red,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
