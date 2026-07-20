import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../../models/catalog/catalog_kind.dart';
import '../../models/catalog_item.dart';
import '../../services/supabase/catalog_service.dart';
import '../../theme/theme.dart';
import 'catalog_item_form_popup.dart';

/// "Web clipper" entry point: paste a supplier product-page URL, the
/// catalog-web-import edge function extracts the product (JSON-LD/meta tags
/// first, self-hosted AI fallback), and the catalog item form opens
/// pre-filled for review.
Future<void> showCatalogWebImportDialog(
  BuildContext context, {
  required String workspaceId,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _CatalogWebImportDialog(workspaceId: workspaceId),
  );
}

class _CatalogWebImportDialog extends StatefulWidget {
  final String workspaceId;

  const _CatalogWebImportDialog({required this.workspaceId});

  @override
  State<_CatalogWebImportDialog> createState() =>
      _CatalogWebImportDialogState();
}

class _CatalogWebImportDialogState extends State<_CatalogWebImportDialog> {
  final _urlController = TextEditingController();
  final _catalogService = SupabaseCatalogService();

  bool _importing = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      setState(() => _error = 'Paste a full product page URL (https://…).');
      return;
    }

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final extracted = await _catalogService.importFromWeb(
        workspaceId: widget.workspaceId,
        url: url,
      );

      final now = DateTime.now();
      final price = (extracted['price'] as num?)?.toDouble() ?? 0;
      final descriptionParts = [
        if ((extracted['description'] as String?)?.trim().isNotEmpty == true)
          (extracted['description'] as String).trim(),
        'Imported from ${extracted['source_url']}',
      ];
      final draft = CatalogItem(
        id: '',
        workspaceId: widget.workspaceId,
        name: (extracted['name'] as String?)?.trim() ?? '',
        description: descriptionParts.join('\n\n'),
        unit: (extracted['unit'] as String?)?.trim(),
        // Supplier page price is what WE pay — it's the cost basis. The
        // estimator sets the customer price/markup on review.
        unitCost: price,
        unitPrice: price,
        markup: 0,
        margin: 0,
        sku: (extracted['sku'] as String?)?.trim(),
        imageUrl: (extracted['image_url'] as String?)?.trim(),
        kind: CatalogKind.product,
        createdAt: now,
        updatedAt: now,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      showCatalogItemFormPopup(context, item: draft, createAsNew: true);
    } catch (e) {
      var message = e.toString();
      if (e is FunctionException) {
        final details = e.details;
        if (details is Map && details['error'] is String) {
          message = details['error'] as String;
        } else {
          message = 'Import failed (HTTP ${e.status}).';
        }
      }
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = message.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.travel_explore, size: 22),
          SizedBox(width: 8),
          Text('Import from Web'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a supplier product page URL (Home Depot, Lowe\'s, '
              'Ferguson, …). The product name, price, SKU, and image are '
              'extracted automatically for you to review.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              autofocus: true,
              enabled: !_importing,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://www.homedepot.com/p/…',
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _importing ? null : _import(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            if (_importing) ...[
              const SizedBox(height: 14),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Fetching and extracting product…'),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _importing ? null : _import,
          icon: const Icon(Icons.travel_explore, size: 18),
          label: const Text('Import'),
        ),
      ],
    );
  }
}
