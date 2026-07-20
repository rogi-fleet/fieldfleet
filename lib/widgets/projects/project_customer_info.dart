import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/customer.dart';
import '../../services/service_locator.dart';
import '../customers/customer_type_badge.dart';
import '../../theme/theme.dart';

class ProjectCustomerInfo extends StatelessWidget {
  final String? customerId;

  const ProjectCustomerInfo({
    super.key,
    this.customerId,
  });

  @override
  Widget build(BuildContext context) {
    if (customerId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Customer?>(
      future: ServiceLocator.customerService.getCustomer(customerId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              'Customer not found',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }

        final customer = snapshot.data!;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              // Customer icon
              Icon(
                Icons.business,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),

              // Customer name (tappable)
              Expanded(
                child: InkWell(
                  onTap: () => context.push('/customers/$customerId'),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          customer.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new,
                        size: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Customer type badge
              CustomerTypeBadge(customerType: customer.customerType, small: true),

              const SizedBox(width: 8),

              // Contact actions
              if (customer.phone != null && customer.phone!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.phone, size: 18),
                  onPressed: () => _launchPhone(customer.phone!),
                  tooltip: 'Call ${customer.phone}',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),

              if (customer.email != null && customer.email!.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.email, size: 18),
                  onPressed: () => _launchEmail(customer.email!, customer.displayName),
                  tooltip: 'Email ${customer.email}',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchEmail(String email, String customerName) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent('Regarding your project')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
