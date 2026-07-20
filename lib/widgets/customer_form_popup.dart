import 'package:flutter/material.dart';
import '../screens/customers/customer_onboarding_wizard.dart';
import 'common/form_popup_header.dart';
import 'nav_breadcrumb_bar.dart';
import '../theme/theme.dart';

/// Shows the customer form as a popup overlay
/// For new customers: Shows the step-by-step onboarding wizard
/// For editing customers: Shows the traditional form
Future<String?> showCustomerFormPopup(
  BuildContext context, {
  String? customerId,
  int? initialStep,
  bool navigateToDetailOnCreate = true,
}) async {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;
  final isNewCustomer = customerId == null;

  if (isMobile) {
    // Show as bottom sheet on mobile
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CustomerFormBottomSheet(
        customerId: customerId,
        isNewCustomer: isNewCustomer,
        initialStep: initialStep,
        navigateToDetailOnCreate: navigateToDetailOnCreate,
      ),
    );
  } else {
    // Show as dialog on desktop
    return showDialog<String>(
      context: context,
      builder: (context) => _CustomerWizardDialog(
        customerId: customerId,
        initialStep: initialStep,
        navigateToDetailOnCreate: navigateToDetailOnCreate,
      ),
    );
  }
}

/// Wizard dialog for new and edit customers (desktop)
class _CustomerWizardDialog extends StatefulWidget {
  final String? customerId;
  final int? initialStep;
  final bool navigateToDetailOnCreate;

  const _CustomerWizardDialog({
    this.customerId,
    this.initialStep,
    required this.navigateToDetailOnCreate,
  });

  @override
  State<_CustomerWizardDialog> createState() => _CustomerWizardDialogState();
}

class _CustomerWizardDialogState extends State<_CustomerWizardDialog> {
  String? _navLocationOnOpen;

  bool get _isEditMode => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    _navLocationOnOpen = NavHistoryController.instance.current;
    // Pop the dialog if the user navigates via GoRouter — otherwise the
    // wizard floats over whatever page they go to next, intercepting
    // clicks and keystrokes.
    NavHistoryController.instance.addListener(_onLocationChanged);
  }

  void _onLocationChanged() {
    if (!mounted) return;
    if (NavHistoryController.instance.current != _navLocationOnOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  @override
  void dispose() {
    NavHistoryController.instance.removeListener(_onLocationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 700,
        height: MediaQuery.of(context).size.height * 0.85,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.r16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r16),
          child: Column(
            children: [
              // Header with title and close button
              FormPopupHeader(
                icon: _isEditMode ? Icons.edit : Icons.person_add,
                title: _isEditMode ? 'Edit Customer' : 'Create New Customer',
                onClose: () => Navigator.of(context).pop(),
              ),
              // Wizard content
              Expanded(
                child: CustomerOnboardingWizard(
                  customerId: widget.customerId,
                  initialStep: widget.initialStep,
                  navigateToDetailOnCreate: widget.navigateToDetailOnCreate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet wrapper for mobile
class _CustomerFormBottomSheet extends StatelessWidget {
  final String? customerId;
  final bool isNewCustomer;
  final int? initialStep;
  final bool navigateToDetailOnCreate;

  const _CustomerFormBottomSheet({
    this.customerId,
    required this.isNewCustomer,
    this.initialStep,
    required this.navigateToDetailOnCreate,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              if (isNewCustomer) ...[
                // Header for new customers on mobile
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: Icons.person_add,
                  title: 'Create New Customer',
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: CustomerOnboardingWizard(
                    initialStep: initialStep,
                    navigateToDetailOnCreate: navigateToDetailOnCreate,
                  ),
                ),
              ] else ...[
                // Header for editing customer on mobile
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: Icons.edit,
                  title: 'Edit Customer',
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: CustomerOnboardingWizard(
                    customerId: customerId,
                    initialStep: initialStep,
                    navigateToDetailOnCreate: navigateToDetailOnCreate,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
