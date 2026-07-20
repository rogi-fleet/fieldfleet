import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../models/customer_tag.dart';

import '../../theme/theme.dart';
import 'customer_tag_chip.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class TagInputWidget extends StatefulWidget {
  final String workspaceId;
  final List<String> selectedTagIds;
  final Function(List<String>) onTagsChanged;

  const TagInputWidget({
    super.key,
    required this.workspaceId,
    required this.selectedTagIds,
    required this.onTagsChanged,
  });

  @override
  State<TagInputWidget> createState() => _TagInputWidgetState();
}

class _TagInputWidgetState extends State<TagInputWidget> {
  final dynamic _tagService = ServiceLocator.customerTagService;
  final TextEditingController _textController = TextEditingController();
  StreamSubscription<List<CustomerTag>>? _tagSubscription;
  List<CustomerTag> _allTags = [];
  List<CustomerTag> _selectedTags = [];
  List<CustomerTag> _filteredTags = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _tagSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    await _tagSubscription?.cancel();
    _tagSubscription = _tagService.getTags(widget.workspaceId).listen((tags) {
      if (!mounted) return;
      setState(() {
        _allTags = tags;
        _updateSelectedTags();
        _filterTags();
      });
    });
  }

  @override
  void didUpdateWidget(covariant TagInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.workspaceId != widget.workspaceId) {
      _loadTags();
      return;
    }

    if (!_sameIds(oldWidget.selectedTagIds, widget.selectedTagIds)) {
      setState(() {
        _updateSelectedTags();
        _filterTags();
      });
    }
  }

  void _updateSelectedTags() {
    _selectedTags = _allTags
        .where((tag) => widget.selectedTagIds.contains(tag.id))
        .toList();
  }

  void _onTextChanged() {
    setState(() {
      _filterTags();
      _showSuggestions = _textController.text.isNotEmpty;
    });
  }

  void _filterTags() {
    final query = _textController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredTags = [];
      return;
    }

    _filteredTags = _allTags
        .where(
          (tag) =>
              tag.name.toLowerCase().contains(query) &&
              !widget.selectedTagIds.contains(tag.id),
        )
        .toList();
  }

  bool _sameIds(List<String> first, List<String> second) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;
    for (int index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  void _addTag(CustomerTag tag) {
    final updatedIds = List<String>.from(widget.selectedTagIds)..add(tag.id);
    widget.onTagsChanged(updatedIds);
    _textController.clear();
    setState(() {
      _showSuggestions = false;
    });
  }

  void _removeTag(String tagId) {
    final updatedIds = List<String>.from(widget.selectedTagIds)..remove(tagId);
    widget.onTagsChanged(updatedIds);
  }

  Future<void> _createNewTag() async {
    final name = _textController.text.trim();
    if (name.isEmpty) return;

    // Show simple color picker dialog
    final color = await _showColorPicker();
    if (color == null) return;

    try {
      final tagId = await _tagService.createTag(
        workspaceId: widget.workspaceId,
        name: name,
        color:
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      );

      final updatedIds = List<String>.from(widget.selectedTagIds)..add(tagId);
      widget.onTagsChanged(updatedIds);
      _textController.clear();
      setState(() {
        _showSuggestions = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create tag: $e')));
      }
    }
  }

  Future<Color?> _showColorPicker() async {
    const colors = AppColors.categoryPalette;

    return showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return InkWell(
              onTap: () => Navigator.of(context).pop(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardBorder, width: 1),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected tags
        if (_selectedTags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedTags.map((tag) {
              return CustomerTagChip(
                tag: tag,
                onDeleted: () => _removeTag(tag.id),
              );
            }).toList(),
          ),
        if (_selectedTags.isNotEmpty) const SizedBox(height: 8),

        // Input field
        StackedField(
          label: 'Add tags',
          child: TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: 'Type to search or create new tag',
              suffixIcon: _textController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: _createNewTag,
                      tooltip: 'Create new tag',
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),

        // Suggestions dropdown
        if (_showSuggestions && _filteredTags.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              color: Theme.of(context).cardColor,
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredTags.length,
              itemBuilder: (context, index) {
                final tag = _filteredTags[index];
                return ListTile(
                  dense: true,
                  leading: CustomerTagChip(tag: tag, small: true),
                  title: Text(tag.name),
                  onTap: () => _addTag(tag),
                );
              },
            ),
          ),

        // Create new tag hint
        if (_showSuggestions && _textController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Press + to create "${_textController.text}" as a new tag',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}
