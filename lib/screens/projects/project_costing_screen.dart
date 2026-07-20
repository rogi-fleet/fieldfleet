import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../models/project.dart';
import '../../models/cost_item.dart';
import '../../models/cost_category.dart';


import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/cost_summary_widget.dart';
import '../../widgets/cost_item_form.dart';

class ProjectCostingScreen extends StatefulWidget {
  final String projectId;

  const ProjectCostingScreen({super.key, required this.projectId});

  @override
  State<ProjectCostingScreen> createState() => _ProjectCostingScreenState();
}

class _ProjectCostingScreenState extends State<ProjectCostingScreen> {
  final _costService = ServiceLocator.costService;
  final _categoryService = ServiceLocator.costCategoryService;
  dynamic get _projectService => ServiceLocator.projectService;

  CostItemType? _filterByType;
  String? _filterByCategory;

  Future<void> _showCostItemForm({CostItem? costItem}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            CostItemForm(projectId: widget.projectId, costItem: costItem),
      ),
    );
  }

  Future<void> _deleteCostItem(CostItem costItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Cost Item'),
        content: Text(
          'Are you sure you want to delete "${costItem.description}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _costService.deleteCostItem(costItem.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Cost item deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting cost item'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: No workspace found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$singular Costs'),
        actions: [
          // Filter menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                if (value == 'all') {
                  _filterByType = null;
                } else if (value == 'material') {
                  _filterByType = CostItemType.material;
                } else if (value == 'labor') {
                  _filterByType = CostItemType.labor;
                }
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Types')),
              const PopupMenuItem(
                value: 'material',
                child: Text('Materials Only'),
              ),
              const PopupMenuItem(value: 'labor', child: Text('Labor Only')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<Project?>(
        future: _projectService.getProject(widget.projectId),
        builder: (context, projectSnapshot) {
          if (projectSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (projectSnapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(
                  projectSnapshot.error,
                  action: 'load this project',
                ),
              ),
            );
          }

          final project = projectSnapshot.data;
          if (project == null) {
            return Center(child: Text('$singular not found'));
          }

          return StreamBuilder<List<CostItem>>(
            stream: _costService.getCostItems(
              widget.projectId,
              workspaceId: workspaceId,
            ),
            builder: (context, costItemsSnapshot) {
              if (costItemsSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (costItemsSnapshot.hasError) {
                return Center(
                  child: SelectableText(
                    UserFacingError.uiMessage(
                      costItemsSnapshot.error,
                      action: 'load cost items',
                    ),
                  ),
                );
              }

              var costItems = costItemsSnapshot.data ?? [];

              // Apply filters
              if (_filterByType != null) {
                costItems = costItems
                    .where((item) => item.type == _filterByType)
                    .toList();
              }
              if (_filterByCategory != null) {
                costItems = costItems
                    .where((item) => item.categoryId == _filterByCategory)
                    .toList();
              }

              return Column(
                children: [
                  // Cost summary
                  CostSummaryWidget(
                    project: project,
                    costItems: costItemsSnapshot.data ?? [],
                  ),

                  // Cost items list
                  Expanded(
                    child: costItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  size: 64,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No cost items yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  kIsWeb ? 'Click the + button to add your first cost' : 'Tap the + button to add your first cost',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : StreamBuilder<List<CostCategory>>(
                            stream: _categoryService.getCategories(workspaceId),
                            builder: (context, categoriesSnapshot) {
                              final categories = categoriesSnapshot.data ?? [];
                              final categoryMap = {
                                for (var cat in categories) cat.id: cat,
                              };

                              return ListView.builder(
                                itemCount: costItems.length,
                                itemBuilder: (context, index) {
                                  final item = costItems[index];
                                  final category = categoryMap[item.categoryId];

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.base,
                                      vertical: AppSpacing.xs,
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: category != null
                                            ? Color(
                                                int.parse(
                                                      category.color.substring(
                                                        1,
                                                      ),
                                                      radix: 16,
                                                    ) +
                                                    0xFF000000,
                                              )
                                            : AppColors.textTertiary,
                                        child: Icon(
                                          item.type == CostItemType.material
                                              ? Icons.construction
                                              : Icons.person,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(item.description),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${category?.name ?? "Unknown"} • ${item.type.displayName}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${item.formattedQuantity} × ${item.formattedUnitPrice}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            item.formattedTotalCost,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            '${item.date.month}/${item.date.day}/${item.date.year}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () =>
                                          _showCostItemForm(costItem: item),
                                      onLongPress: () => _deleteCostItem(item),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCostItemForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
