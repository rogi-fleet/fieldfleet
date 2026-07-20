import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import '../../models/time_entry.dart';
import 'widgets/time_entry_quick_form.dart';

/// Shows the create/edit time-entry form inside the app's canonical popup
/// chrome. The form itself ([TimeEntryQuickForm]) renders its own primary
/// save action, so no footer is needed here — the popup header's close button
/// is the cancel affordance. Resolves to `true` once an entry is saved.
Future<bool?> showTimeEntryFormDialog(
  BuildContext context, {
  required DateTime selectedDate,
  TimeEntry? existingEntry,
  String? initialProjectId,
  String? initialTaskId,
}) {
  return showFormPopup<bool>(
    context,
    icon: Icons.schedule,
    title: existingEntry != null ? 'Edit Time Entry' : 'Create New Time Entry',
    width: 480,
    builder: (ctx, scrollController) => _TimeEntryFormContent(
      selectedDate: selectedDate,
      existingEntry: existingEntry,
      initialProjectId: initialProjectId,
      initialTaskId: initialTaskId,
      scrollController: scrollController,
    ),
  );
}

class _TimeEntryFormContent extends StatelessWidget {
  final DateTime selectedDate;
  final TimeEntry? existingEntry;
  final String? initialProjectId;
  final String? initialTaskId;
  final ScrollController? scrollController;

  const _TimeEntryFormContent({
    required this.selectedDate,
    this.existingEntry,
    this.initialProjectId,
    this.initialTaskId,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: TimeEntryQuickForm(
              selectedDate: selectedDate,
              existingEntry: existingEntry,
              initialProjectId: initialProjectId,
              initialTaskId: initialTaskId,
              showTemplates: existingEntry == null,
              showHeader: false,
              onEntrySaved: () => Navigator.pop(context, true),
            ),
          ),
        ),
      ],
    );
  }
}
