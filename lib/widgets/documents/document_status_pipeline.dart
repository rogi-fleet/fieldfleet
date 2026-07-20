import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/template_category.dart';
import '../../theme/theme.dart';

/// A single stage in the document lifecycle pipeline.
class _PipelineStage {
  final String label;
  final _StageState state;
  final String? tooltip;

  const _PipelineStage({required this.label, required this.state, this.tooltip});
}

enum _StageState { completed, current, partial, future }

/// Displays a horizontal lifecycle pipeline for a document.
///
/// Stages vary by document type category:
/// - Customer Invoice: Draft → Sent → Viewed → Approved → Paid
/// - Customer Order:   Draft → Sent → Viewed → Approved → Signed
/// - Vendor Order:     Draft → Sent → Viewed → Approved
/// - Vendor Bill:      Draft → Approved → Paid
class DocumentStatusPipeline extends StatelessWidget {
  final GeneratedDocument document;

  const DocumentStatusPipeline({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final stages = _buildStages();

    return Row(
      children: [
        for (int i = 0; i < stages.length; i++) ...[
          _StageChip(stage: stages[i]),
          if (i < stages.length - 1) const SizedBox(width: 2),
        ],
      ],
    );
  }

  List<_PipelineStage> _buildStages() {
    final category = document.documentType.category;

    // Define the pipeline labels per category.
    final List<String> labels;
    switch (category) {
      case TemplateCategory.customerInvoice:
        // AIA contracts sit in the invoice category but are agreements that end
        // at signature, not payable bills, so they get the order pipeline.
        labels = document.documentType == DocumentType.aiaContract
            ? ['Draft', 'Sent', 'Viewed', 'Approved', 'Signed']
            : ['Draft', 'Sent', 'Viewed', 'Approved', 'Paid'];
      case TemplateCategory.customerOrder:
        labels = ['Draft', 'Sent', 'Viewed', 'Approved', 'Signed'];
      case TemplateCategory.vendorOrder:
        labels = ['Draft', 'Sent', 'Viewed', 'Approved'];
      case TemplateCategory.vendorBill:
        labels = ['Draft', 'Approved', 'Paid'];
    }

    // Map each label to a completion state based on the document fields.
    final completedSet = _completedStageLabels();
    final currentLabel = _currentStageLabel();

    bool foundCurrent = false;
    return labels.map((label) {
      // A partially paid invoice is neither "Paid" nor indistinguishable from
      // unpaid: surface the in-between state with the running amounts.
      if (label == 'Paid' &&
          document.paidDate == null &&
          document.amountPaid > 0) {
        final fmt = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
        return _PipelineStage(
          label: 'Partially Paid',
          state: _StageState.partial,
          tooltip:
              'Paid ${fmt.format(document.amountPaid)} of ${fmt.format(document.totalAmount)}',
        );
      }
      if (completedSet.contains(label)) {
        return _PipelineStage(label: label, state: _StageState.completed);
      }
      if (!foundCurrent && label == currentLabel) {
        foundCurrent = true;
        return _PipelineStage(label: label, state: _StageState.current);
      }
      return _PipelineStage(label: label, state: _StageState.future);
    }).toList();
  }

  /// Returns the set of stage labels that are already completed.
  Set<String> _completedStageLabels() {
    final completed = <String>{};
    final s = document.status;

    // Draft is completed once the document moves past draft.
    if (s != DocumentStatus.draft) {
      completed.add('Draft');
    }

    // Sent is completed if sentAt is set.
    if (document.sentAt != null) {
      completed.add('Sent');
    }

    // Viewed is completed if status has progressed past viewed,
    // or status is currently viewed (then it's the current stage, not completed).
    // We mark viewed as completed if the status is beyond viewed.
    const viewedOrBeyond = {
      DocumentStatus.signed,
      DocumentStatus.approved,
    };
    if (viewedOrBeyond.contains(s) ||
        (s == DocumentStatus.viewed && document.approvedAt != null)) {
      completed.add('Viewed');
    }

    // Approved is completed if approvedAt is set.
    if (document.approvedAt != null) {
      completed.add('Approved');
    }

    // Signed is completed if signedAt is set.
    if (document.signedAt != null) {
      completed.add('Signed');
    }

    // Paid is completed if paidDate is set.
    if (document.paidDate != null) {
      completed.add('Paid');
    }

    return completed;
  }

  /// Returns the label of the current (active) stage.
  String _currentStageLabel() {
    // If paid → pipeline is fully complete, no "current" stage.
    if (document.paidDate != null) return '';
    if (document.signedAt != null) return '';

    switch (document.status) {
      case DocumentStatus.draft:
        return 'Draft';
      case DocumentStatus.sent:
        return 'Sent';
      case DocumentStatus.viewed:
        return 'Viewed';
      case DocumentStatus.approved:
        // Approved but not yet paid/signed → Approved is current if it's the
        // terminal stage, otherwise the next stage (Paid/Signed) is current.
        final category = document.documentType.category;
        if (category == TemplateCategory.vendorOrder) return '';
        return category == TemplateCategory.customerInvoice ? 'Paid' : 'Signed';
      case DocumentStatus.signed:
        return 'Signed';
      case DocumentStatus.pending:
        return 'Approved';
      case DocumentStatus.denied:
      case DocumentStatus.changesRequested:
        // For denied/changes requested, highlight the last reached stage.
        if (document.approvedAt != null) return 'Approved';
        if (document.sentAt != null) return 'Sent';
        return 'Draft';
      case DocumentStatus.responded:
        return 'Bid Received';
      case DocumentStatus.applied:
        return 'Applied';
      case DocumentStatus.notSelected:
        return 'Not Selected';
      case DocumentStatus.withdrawn:
        return 'Withdrawn';
    }
  }
}

/// A single chip in the pipeline row.
class _StageChip extends StatelessWidget {
  final _PipelineStage stage;

  const _StageChip({required this.stage});

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color fgColor;
    final Widget leading;

    switch (stage.state) {
      case _StageState.completed:
        bgColor = AppColors.successLight;
        fgColor = AppColors.successDark;
        leading = Icon(Icons.check_circle, size: 14, color: fgColor);
      case _StageState.current:
        bgColor = AppColors.infoLight;
        fgColor = AppColors.infoDark;
        leading = Icon(Icons.circle, size: 10, color: fgColor);
      case _StageState.partial:
        bgColor = AppColors.warningLight;
        fgColor = AppColors.warningDark;
        leading = Icon(Icons.timelapse, size: 14, color: fgColor);
      case _StageState.future:
        bgColor = Colors.transparent;
        fgColor = AppColors.textTertiary;
        leading = Icon(Icons.horizontal_rule, size: 14, color: fgColor);
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: switch (stage.state) {
          _StageState.current =>
              Border.all(color: AppColors.info.withValues(alpha: 0.4)),
          _StageState.partial =>
              Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
          _ => null,
        },
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 4),
          Text(
            stage.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
    if (stage.tooltip != null) {
      return Tooltip(message: stage.tooltip!, child: chip);
    }
    return chip;
  }
}
