import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/catalog_item.dart';
import '../../services/supabase/catalog_service.dart';
import '../../theme/theme.dart';
import 'catalog_item_form.dart';

/// Full-page (own-window) version of the catalog item form.
///
/// Used when the user clicks "+ Add Item" in the catalog list — the screen is
/// opened in a new browser tab via `launchUrl(..., webOnlyWindowName: '_blank')`
/// so users can keep the catalog list visible while creating an item.
class CatalogItemFormScreen extends StatefulWidget {
  final String? itemId;
  final String? initialParentId;
  final int? initialHierarchyLevel;
  final bool initialIsGroup;

  const CatalogItemFormScreen({
    super.key,
    this.itemId,
    this.initialParentId,
    this.initialHierarchyLevel,
    this.initialIsGroup = false,
  });

  @override
  State<CatalogItemFormScreen> createState() => _CatalogItemFormScreenState();
}

class _CatalogItemFormScreenState extends State<CatalogItemFormScreen> {
  final SupabaseCatalogService _service = SupabaseCatalogService();
  CatalogItem? _loaded;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.itemId != null && widget.itemId!.isNotEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final item = await _service.getCatalogItem(widget.itemId!);
      if (!mounted) return;
      setState(() {
        _loaded = item;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.itemId != null && widget.itemId!.isNotEmpty;
    final title = isEditing
        ? 'Edit Catalog Item'
        : (widget.initialIsGroup ? 'New Catalog Group' : 'New Catalog Item');

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              children: [
                Icon(
                  isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Saved items appear automatically in the catalog list.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.65),
                                ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close window',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.go('/catalog');
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(isEditing)),
        ],
      ),
    );
  }

  Widget _buildBody(bool isEditing) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: SelectableText('Failed to load: $_error'));
    }
    if (isEditing && _loaded == null) {
      return const Center(child: Text('Item not found.'));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: CatalogItemForm(
          item: _loaded,
          initialParentId: widget.initialParentId,
          initialHierarchyLevel: widget.initialHierarchyLevel,
          initialIsGroup: widget.initialIsGroup,
          onSaved: () {
            if (!Navigator.of(context).canPop()) {
              context.go('/catalog');
            }
          },
        ),
      ),
    );
  }
}
