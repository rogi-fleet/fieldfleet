import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// A reusable widget that renders a list of selectable chips with an optional
/// search field. The search field appears automatically when there are more
/// items than [searchThreshold] (default 5). The currently selected item is
/// pinned at the start of the list even when filtered out by search.
class SearchableFilterChips extends StatefulWidget {
  final List<({String id, String label})> items;
  final String? selectedId;
  final VoidCallback onAllSelected;
  final ValueChanged<String> onItemSelected;
  final String searchHint;
  final int searchThreshold;
  final String allLabel;

  const SearchableFilterChips({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onAllSelected,
    required this.onItemSelected,
    this.searchHint = 'Search...',
    this.searchThreshold = 5,
    this.allLabel = 'All',
  });

  @override
  State<SearchableFilterChips> createState() => _SearchableFilterChipsState();
}

class _SearchableFilterChipsState extends State<SearchableFilterChips> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? widget.items
        : widget.items
            .where((item) => item.label.toLowerCase().contains(query))
            .toList();

    // Pin the selected item if it's been filtered out by search
    final selectedItem = widget.selectedId != null
        ? widget.items
            .where((item) => item.id == widget.selectedId)
            .firstOrNull
        : null;
    final showSelectedPinned = selectedItem != null &&
        query.isNotEmpty &&
        !filtered.any((item) => item.id == widget.selectedId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.items.length > widget.searchThreshold)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: Text(widget.allLabel),
              selected: widget.selectedId == null,
              onSelected: (_) => widget.onAllSelected(),
            ),
            if (showSelectedPinned)
              ChoiceChip(
                label: Text(_truncateLabel(selectedItem.label)),
                selected: true,
                onSelected: (_) => widget.onItemSelected(selectedItem.id),
              ),
            ...filtered.map((item) {
              return ChoiceChip(
                label: Text(_truncateLabel(item.label)),
                selected: widget.selectedId == item.id,
                onSelected: (_) => widget.onItemSelected(item.id),
              );
            }),
          ],
        ),
        if (query.isNotEmpty && filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No matches',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }

  static String _truncateLabel(String label, [int maxLength = 25]) {
    return label.length > maxLength
        ? '${label.substring(0, maxLength)}...'
        : label;
  }
}
