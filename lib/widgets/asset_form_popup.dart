import 'package:flutter/material.dart';
import '../screens/assets/asset_form_screen.dart';
import 'common/form_popup_header.dart';
import 'common/unsaved_changes_guard.dart';
import '../theme/theme.dart';

/// Shows the asset form as a popup overlay
void showAssetFormPopup(BuildContext context, {String? assetId}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AssetFormBottomSheet(assetId: assetId),
    );
  } else {
    showDialog(
      context: context,
      builder: (context) => _AssetFormDialog(assetId: assetId),
    );
  }
}

/// Bottom sheet wrapper for mobile
class _AssetFormBottomSheet extends StatefulWidget {
  final String? assetId;

  const _AssetFormBottomSheet({this.assetId});

  @override
  State<_AssetFormBottomSheet> createState() => _AssetFormBottomSheetState();
}

class _AssetFormBottomSheetState extends State<_AssetFormBottomSheet> {
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
                  icon: widget.assetId == null ? Icons.inventory_2 : Icons.edit,
                  title: widget.assetId == null
                      ? 'Create New Equipment'
                      : 'Edit Equipment',
                  onClose: () =>
                      maybeCloseForm(context, isDirty: _dirty.value),
                ),
                Expanded(
                  child: AssetFormContent(
                    assetId: widget.assetId,
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
class _AssetFormDialog extends StatefulWidget {
  final String? assetId;

  const _AssetFormDialog({this.assetId});

  @override
  State<_AssetFormDialog> createState() => _AssetFormDialogState();
}

class _AssetFormDialogState extends State<_AssetFormDialog> {
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
          width: 600,
          height: MediaQuery.of(context).size.height * 0.85,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            children: [
              FormPopupHeader(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                icon: widget.assetId == null ? Icons.inventory_2 : Icons.edit,
                title: widget.assetId == null
                    ? 'Create New Equipment'
                    : 'Edit Equipment',
                onClose: () =>
                    maybeCloseForm(context, isDirty: _dirty.value),
              ),
              Expanded(
                child: AssetFormContent(
                  assetId: widget.assetId,
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
