import '../models/customer.dart';
import '../models/project.dart';

String normalizeProjectCustomerName(String? customerName) {
  final trimmed = customerName?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return '';
  }

  final match = RegExp(r'^(.*)\s+\([^()]+\)$').firstMatch(trimmed);
  if (match != null) {
    return match.group(1)!.trim();
  }

  return trimmed;
}

bool projectCustomerNeedsRefresh(Project project) {
  final customerId = project.clientId;
  if (customerId == null || customerId.isEmpty) {
    return false;
  }

  final normalized = normalizeProjectCustomerName(project.customerName);
  return normalized.isEmpty ||
      normalized != (project.customerName?.trim() ?? '');
}

String projectBusinessName(Project project, {Customer? customer}) {
  final businessName = customer?.businessDisplayName.trim();
  if (businessName != null && businessName.isNotEmpty) {
    return businessName;
  }

  return normalizeProjectCustomerName(project.customerName);
}
