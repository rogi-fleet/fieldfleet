import 'generated_document.dart';

/// Portal invoice list row with optional project context.
class PortalInvoiceSummary {
  final GeneratedDocument invoice;
  final String? projectName;

  const PortalInvoiceSummary({required this.invoice, this.projectName});
}
