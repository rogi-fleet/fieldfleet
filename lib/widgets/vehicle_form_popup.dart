import 'package:flutter/material.dart';
import '../screens/vehicles/vehicle_form_screen.dart';
import 'common/form_popup_header.dart';
import 'common/unsaved_changes_guard.dart';
import '../theme/theme.dart';

/// Shows the vehicle form as a popup overlay
void showVehicleFormPopup(BuildContext context, {String? vehicleId}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VehicleFormBottomSheet(vehicleId: vehicleId),
    );
  } else {
    showDialog(
      context: context,
      builder: (context) => _VehicleFormDialog(vehicleId: vehicleId),
    );
  }
}

/// Bottom sheet wrapper for mobile
class _VehicleFormBottomSheet extends StatefulWidget {
  final String? vehicleId;

  const _VehicleFormBottomSheet({this.vehicleId});

  @override
  State<_VehicleFormBottomSheet> createState() =>
      _VehicleFormBottomSheetState();
}

class _VehicleFormBottomSheetState extends State<_VehicleFormBottomSheet> {
  final _dirty = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await maybeCloseForm(context, isDirty: _dirty.value);
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: widget.vehicleId == null
                      ? Icons.directions_car
                      : Icons.edit,
                  title: widget.vehicleId == null
                      ? 'Create New Vehicle'
                      : 'Edit Vehicle',
                  onClose: () =>
                      maybeCloseForm(context, isDirty: _dirty.value),
                ),
                Expanded(
                  child: VehicleFormContent(
                    vehicleId: widget.vehicleId,
                    isPopup: true,
                    dirtyNotifier: _dirty,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Dialog wrapper for desktop
class _VehicleFormDialog extends StatefulWidget {
  final String? vehicleId;

  const _VehicleFormDialog({this.vehicleId});

  @override
  State<_VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends State<_VehicleFormDialog> {
  final _dirty = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await maybeCloseForm(context, isDirty: _dirty.value);
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 700,
          height: MediaQuery.of(context).size.height * 0.9,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            children: [
              FormPopupHeader(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                icon: widget.vehicleId == null
                    ? Icons.directions_car
                    : Icons.edit,
                title: widget.vehicleId == null
                    ? 'Create New Vehicle'
                    : 'Edit Vehicle',
                onClose: () =>
                    maybeCloseForm(context, isDirty: _dirty.value),
              ),
              Expanded(
                child: VehicleFormContent(
                  vehicleId: widget.vehicleId,
                  isPopup: true,
                  dirtyNotifier: _dirty,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
