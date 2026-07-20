import 'package:flutter/material.dart';

/// Material [Tab] used by sub-section selectors inside the project (job)
/// detail view. Lays out the icon + label inline so the surrounding
/// [TabBar] keeps a compact single-row height that matches the main
/// project tab bar (rather than the default 2-row icon-above-text Tab).
///
/// Use anywhere a job-scoped TabBar exists (Overview, Tasks, Financials,
/// Inventory) so every nested-tabs surface stays visually consistent.
Tab projectSubTab({required IconData icon, required String label}) {
  return Tab(
    height: 40,
    iconMargin: EdgeInsets.zero,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}
