import 'package:flutter/material.dart';
import '../screens/projects/budget_view_screen.dart';

/// Visual status of a workflow node.
enum WorkflowNodeStatus { notStarted, draft, active, overdue, complete }

/// A single step in a workflow band chain.
class WorkflowNode {
  final String id;
  final String label;
  final String? statusText;
  final WorkflowNodeStatus status;
  final IconData icon;
  final String? documentId;
  final double? amount;
  final int? count;
  final String? transitionLabel; // label on the arrow *after* this node

  /// When non-null, tapping the node should surface this message instead of
  /// navigating — the prerequisite step for this node has not yet been met.
  final String? blockedReason;

  const WorkflowNode({
    required this.id,
    required this.label,
    this.statusText,
    required this.status,
    required this.icon,
    this.documentId,
    this.amount,
    this.count,
    this.transitionLabel,
    this.blockedReason,
  });
}

/// A horizontal band in the workflow canvas (e.g. Estimating, Billing).
class WorkflowBand {
  final String label;
  final String subtitle;
  final IconData icon;

  /// The [BudgetViewMode] this band navigates to when tapped.
  final BudgetViewMode? viewMode;

  /// Each inner list is one chain of nodes rendered left-to-right.
  /// Bands 1-2 have one chain; bands 3-4 have two (left + right columns).
  final List<List<WorkflowNode>> chains;

  const WorkflowBand({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.viewMode,
    required this.chains,
  });
}

/// Computed financial workflow state for a project.
class FinancialWorkflowState {
  final double approvedEstimate;
  final double invoicedToDate;
  final double collected;
  final double outstanding;
  final List<WorkflowBand> bands;

  const FinancialWorkflowState({
    required this.approvedEstimate,
    required this.invoicedToDate,
    required this.collected,
    required this.outstanding,
    required this.bands,
  });
}
