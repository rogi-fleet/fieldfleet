import 'package:flutter/material.dart';
import '../../screens/catalog/catalog_item_form.dart';
import '../../models/catalog_item.dart';
import '../common/form_popup_scaffold.dart';

void showCatalogItemFormPopup(
  BuildContext context, {
  CatalogItem? item,
  bool createAsNew = false,
}) {
  final isEdit = item != null && !createAsNew;
  showFormPopup<void>(
    context,
    icon: createAsNew
        ? Icons.travel_explore
        : (isEdit ? Icons.edit : Icons.add_circle_outline),
    title: createAsNew
        ? 'Review Imported Item'
        : (isEdit ? 'Edit Catalog Item' : 'Create New Catalog Item'),
    width: 600,
    fitContent: false,
    heightFactor: 0.8,
    builder: (ctx, scrollController) =>
        CatalogItemForm(item: item, isPopup: true, createAsNew: createAsNew),
  );
}
