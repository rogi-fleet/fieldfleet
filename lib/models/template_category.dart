import 'package:flutter/material.dart';

/// Template categories for organizing document templates.
/// Each category groups related template types together.
enum TemplateCategory {
  customerOrder,
  customerInvoice,
  vendorOrder,
  vendorBill,
}

extension TemplateCategoryExtension on TemplateCategory {
  /// Display name for the category
  String get displayName {
    switch (this) {
      case TemplateCategory.customerOrder:
        return 'Customer Order';
      case TemplateCategory.customerInvoice:
        return 'Customer Invoice';
      case TemplateCategory.vendorOrder:
        return 'Vendor Order';
      case TemplateCategory.vendorBill:
        return 'Vendor Bill';
    }
  }

  /// Description explaining the purpose of this category
  String get description {
    switch (this) {
      case TemplateCategory.customerOrder:
        return 'Establish a contract between you and the customer with a scope of work and price.';
      case TemplateCategory.customerInvoice:
        return 'Collect payment from the customer.';
      case TemplateCategory.vendorOrder:
        return 'Create a commitment to a cost.';
      case TemplateCategory.vendorBill:
        return 'Record a bill from a vendor.';
    }
  }

  /// Color associated with this category
  Color get color {
    switch (this) {
      case TemplateCategory.customerOrder:
        return const Color(0xFFE67E22); // Orange
      case TemplateCategory.customerInvoice:
        return const Color(0xFF3498DB); // Blue
      case TemplateCategory.vendorOrder:
        return const Color(0xFF27AE60); // Green
      case TemplateCategory.vendorBill:
        return const Color(0xFF9B59B6); // Purple
    }
  }

  /// Icon for the category
  IconData get icon {
    switch (this) {
      case TemplateCategory.customerOrder:
        return Icons.assignment;
      case TemplateCategory.customerInvoice:
        return Icons.receipt_long;
      case TemplateCategory.vendorOrder:
        return Icons.shopping_cart;
      case TemplateCategory.vendorBill:
        return Icons.receipt;
    }
  }
}
