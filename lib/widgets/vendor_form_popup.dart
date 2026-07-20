import 'package:flutter/material.dart';
import '../screens/vendors/vendor_onboarding_wizard.dart';
import 'common/form_popup_header.dart';
import 'nav_breadcrumb_bar.dart';
import '../theme/theme.dart';

/// Shows the vendor form as a popup overlay
/// For new vendors: Shows the step-by-step onboarding wizard
/// For editing vendors: Shows the traditional form
Future<String?> showVendorFormPopup(
  BuildContext context, {
  String? vendorId,
  bool navigateToDetailOnCreate = true,
}) async {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;
  final isNewVendor = vendorId == null;

  if (isMobile) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VendorFormBottomSheet(
        vendorId: vendorId,
        isNewVendor: isNewVendor,
        navigateToDetailOnCreate: navigateToDetailOnCreate,
      ),
    );
  } else {
    return showDialog<String>(
      context: context,
      builder: (context) => _VendorWizardDialog(
        vendorId: vendorId,
        navigateToDetailOnCreate: navigateToDetailOnCreate,
      ),
    );
  }
}

/// Wizard dialog for new and edit vendors (desktop)
class _VendorWizardDialog extends StatefulWidget {
  final String? vendorId;
  final bool navigateToDetailOnCreate;

  const _VendorWizardDialog({
    this.vendorId,
    required this.navigateToDetailOnCreate,
  });

  @override
  State<_VendorWizardDialog> createState() => _VendorWizardDialogState();
}

class _VendorWizardDialogState extends State<_VendorWizardDialog> {
  String? _navLocationOnOpen;

  bool get _isEditMode => widget.vendorId != null;

  @override
  void initState() {
    super.initState();
    _navLocationOnOpen = NavHistoryController.instance.current;
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
                icon: _isEditMode ? Icons.edit : Icons.store_mall_directory,
                title: _isEditMode ? 'Edit Vendor' : 'Create New Vendor',
                onClose: () => Navigator.of(context).pop(),
              ),
              // Wizard content
              Expanded(
                child: VendorOnboardingWizard(
                  vendorId: widget.vendorId,
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
class _VendorFormBottomSheet extends StatelessWidget {
  final String? vendorId;
  final bool isNewVendor;
  final bool navigateToDetailOnCreate;

  const _VendorFormBottomSheet({
    this.vendorId,
    required this.isNewVendor,
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
              if (isNewVendor) ...[
                // Header for new vendors on mobile
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: Icons.store_mall_directory,
                  title: 'Create New Vendor',
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: VendorOnboardingWizard(
                    navigateToDetailOnCreate: navigateToDetailOnCreate,
                  ),
                ),
              ] else ...[
                // Header for editing vendor on mobile
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: Icons.edit,
                  title: 'Edit Vendor',
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: VendorOnboardingWizard(
                    vendorId: vendorId,
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
