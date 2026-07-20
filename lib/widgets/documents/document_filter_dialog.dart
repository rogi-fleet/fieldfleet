import 'package:flutter/material.dart';
import '../../models/document_type.dart';
import '../../models/document_status.dart';
import '../../theme/theme.dart';
import '../common/searchable_filter_chips.dart';

class DocumentFilterDialog extends StatefulWidget {
  final DocumentType? selectedType;
  final DocumentStatus? selectedStatus;
  final List<({String id, String name})> savedViews;
  final String? activeSavedViewId;
  final void Function(DocumentType? type, DocumentStatus? status) onApply;
  final void Function(DocumentType? type, DocumentStatus? status) onSaveView;
  final ValueChanged<String> onApplySavedView;
  final ValueChanged<String> onDeleteSavedView;

  const DocumentFilterDialog({
    super.key,
    required this.selectedType,
    required this.selectedStatus,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.onApply,
    required this.onSaveView,
    required this.onApplySavedView,
    required this.onDeleteSavedView,
  });

  @override
  State<DocumentFilterDialog> createState() => _DocumentFilterDialogState();
}

class _DocumentFilterDialogState extends State<DocumentFilterDialog> {
  late DocumentType? _type;
  late DocumentStatus? _status;

  bool get _hasAnyFilter => _type != null || _status != null;

  @override
  void initState() {
    super.initState();
    _type = widget.selectedType;
    _status = widget.selectedStatus;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_hasAnyFilter)
                    TextButton(
                      onPressed: () => setState(() {
                        _type = null;
                        _status = null;
                      }),
                      child: const Text('Clear all'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                shrinkWrap: true,
                children: [
                  _buildSection(
                    icon: Icons.description_outlined,
                    title: 'Document Type',
                    subtitle: _type?.displayName ?? 'Any',
                    isActive: _type != null,
                    child: SearchableFilterChips(
                      items: DocumentType.values
                          .map((t) => (id: t.name, label: t.displayName))
                          .toList(),
                      selectedId: _type?.name,
                      allLabel: 'Any',
                      onAllSelected: () => setState(() => _type = null),
                      onItemSelected: (id) => setState(
                        () => _type = DocumentType.values.firstWhere(
                          (t) => t.name == id,
                        ),
                      ),
                      searchHint: 'Search types...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    icon: Icons.check_circle_outline,
                    title: 'Status',
                    subtitle: _status?.displayName ?? 'Any',
                    isActive: _status != null,
                    child: SearchableFilterChips(
                      items: DocumentStatus.values
                          .map((s) => (id: s.name, label: s.displayName))
                          .toList(),
                      selectedId: _status?.name,
                      allLabel: 'Any',
                      onAllSelected: () => setState(() => _status = null),
                      onItemSelected: (id) => setState(
                        () => _status = DocumentStatus.values.firstWhere(
                          (s) => s.name == id,
                        ),
                      ),
                      searchHint: 'Search statuses...',
                    ),
                  ),
                  if (widget.savedViews.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.bookmark_border,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Saved Views',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...widget.savedViews.map((view) {
                      final isActive = view.id == widget.activeSavedViewId;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isActive ? Icons.bookmark : Icons.bookmark_border,
                          size: 18,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                        title: Text(
                          view.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isActive ? AppColors.primary : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () => widget.onDeleteSavedView(view.id),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: AppColors.textTertiary,
                        ),
                        onTap: () => widget.onApplySavedView(view.id),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => widget.onSaveView(_type, _status),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save View'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onApply(_type, _status),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(
            icon,
            size: 20,
            color: isActive ? AppColors.primary : AppColors.textSecondary,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
