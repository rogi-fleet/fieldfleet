import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// A widget for inputting and displaying file tags as chips.
class FileTagInput extends StatefulWidget {
  final List<String> initialTags;
  final Function(List<String>) onTagsChanged;
  final List<String>? suggestedTags;

  const FileTagInput({
    super.key,
    this.initialTags = const [],
    required this.onTagsChanged,
    this.suggestedTags,
  });

  @override
  State<FileTagInput> createState() => _FileTagInputState();
}

class _FileTagInputState extends State<FileTagInput> {
  late List<String> _tags;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    final trimmedTag = tag.trim().toLowerCase();
    if (trimmedTag.isNotEmpty && !_tags.contains(trimmedTag)) {
      setState(() {
        _tags.add(trimmedTag);
      });
      widget.onTagsChanged(_tags);
    }
    _controller.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    widget.onTagsChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tags',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        // Tags display
        if (_tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) {
              return Chip(
                label: Text(tag),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => _removeTag(tag),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        // Tag input field
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Add a tag...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                onSubmitted: _addTag,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  _addTag(_controller.text);
                }
              },
              icon: const Icon(Icons.add),
              tooltip: 'Add tag',
            ),
          ],
        ),
        // Suggested tags
        if (widget.suggestedTags != null && widget.suggestedTags!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Suggested:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: widget.suggestedTags!
                .where((tag) => !_tags.contains(tag))
                .take(5)
                .map((tag) {
              return ActionChip(
                label: Text(tag),
                onPressed: () => _addTag(tag),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
