import 'package:flutter/material.dart';
import '../services/service_locator.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../models/document_template.dart';
import '../models/document_type.dart';
import '../models/template_category.dart';

import '../providers/auth_provider.dart';
import '../theme/theme.dart';

/// A dialog that shows available document templates grouped by category.
/// Returns the selected template, or null if canceled.
class TemplatePickerDialog extends StatefulWidget {
  /// Optional category to filter templates
  final TemplateCategory? filterCategory;

  const TemplatePickerDialog({super.key, this.filterCategory});

  /// Shows the template picker dialog and returns the selected template.
  static Future<DocumentTemplate?> show(
    BuildContext context, {
    TemplateCategory? filterCategory,
  }) {
    return showDialog<DocumentTemplate>(
      context: context,
      builder: (context) =>
          TemplatePickerDialog(filterCategory: filterCategory),
    );
  }

  @override
  State<TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<TemplatePickerDialog> {
  final _templateService = ServiceLocator.documentTemplateService;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<TemplateCategory> _expandedCategories = {};
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Expand the filtered category by default, or all categories if no filter
    if (widget.filterCategory != null) {
      _expandedCategories.add(widget.filterCategory!);
    } else {
      _expandedCategories.addAll(TemplateCategory.values);
    }
    // Best-effort: seed any missing core default templates (idempotent —
    // existing templates are skipped). This ensures newly-added document
    // types like AIA Pay Application appear for workspaces created before
    // the type was introduced.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      final userId = authProvider.appUser?.id;
      if (workspaceId == null || userId == null) return;
      _templateService
          .initializeDefaultTemplates(workspaceId, userId)
          .catchError((_) {}); // silent: stream will still show what exists
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  IconData _getIconForType(DocumentType type) {
    switch (type) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
        return Icons.receipt_long;
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
        return Icons.assignment;
      case DocumentType.quotation:
        return Icons.request_quote;
      case DocumentType.expense:
        return Icons.money_off;
      case DocumentType.bill:
        return Icons.receipt;
      case DocumentType.purchaseOrder:
        return Icons.shopping_cart;
      case DocumentType.custom:
        return Icons.description;
      default:
        return type.category.icon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return AlertDialog(
        title: const Text('Error'),
        content: const Text('No workspace found'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.article_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Select a Template',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search templates...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ],
              ),
            ),

            // Template list
            Flexible(
              child:
                  StreamBuilder<Map<TemplateCategory, List<DocumentTemplate>>>(
                    stream: _templateService.getTemplatesByCategory(
                      workspaceId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Text(
                              UserFacingError.uiMessage(
                                snapshot.error,
                                action: 'load data',
                              ),
                            ),
                          ),
                        );
                      }

                      final groupedTemplates = snapshot.data ?? {};

                      // Filter by category if specified
                      final categoriesToShow = widget.filterCategory != null
                          ? [widget.filterCategory!]
                          : TemplateCategory.values;

                      // Check if any templates exist
                      final hasTemplates = categoriesToShow.any(
                        (cat) => (groupedTemplates[cat] ?? []).isNotEmpty,
                      );

                      if (!hasTemplates) {
                        return _buildEmptyState();
                      }

                      return SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.base),
                        child: Column(
                          children: categoriesToShow.map((category) {
                            final templates = groupedTemplates[category] ?? [];

                            // Filter by search query
                            final filteredTemplates = _searchQuery.isEmpty
                                ? templates
                                : templates
                                      .where(
                                        (t) =>
                                            t.name.toLowerCase().contains(
                                              _searchQuery,
                                            ) ||
                                            t.type.displayName
                                                .toLowerCase()
                                                .contains(_searchQuery),
                                      )
                                      .toList();

                            if (filteredTemplates.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return _buildCategorySection(
                              category,
                              filteredTemplates,
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    TemplateCategory category,
    List<DocumentTemplate> templates,
  ) {
    final isExpanded = _expandedCategories.contains(category);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Category header
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(category);
                } else {
                  _expandedCategories.add(category);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceAlt),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: category.color.withAlpha(30),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(category.icon, color: category.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              category.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cardBorder,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: Text(
                                '${templates.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          category.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Templates list
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: templates
                  .map((template) => _buildTemplateItem(template, category))
                  .toList(),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateItem(
    DocumentTemplate template,
    TemplateCategory category,
  ) {
    return InkWell(
      onTap: () => Navigator.pop(context, template),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: Row(
          children: [
            Icon(
              _getIconForType(template.type),
              size: 20,
              color: category.color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template.type.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (template.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.successDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No templates available',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a template to get started',
              style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
