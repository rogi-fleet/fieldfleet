import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../services/service_locator.dart';

class VendorRelatedProjectScope {
  final List<GeneratedDocument> purchaseOrders;
  final List<GeneratedDocument> bills;
  final List<GeneratedDocument> bidRequests;
  final Map<String, Project> projectsById;

  const VendorRelatedProjectScope({
    required this.purchaseOrders,
    required this.bills,
    required this.bidRequests,
    required this.projectsById,
  });

  List<Project> get projects {
    final items = projectsById.values.toList();
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  bool get hasRelatedProjects => projectsById.isNotEmpty;
}

Future<VendorRelatedProjectScope> loadVendorRelatedProjectScope(
  Vendor vendor,
) async {
  final dynamic documentService = ServiceLocator.documentService;
  final dynamic projectService = ServiceLocator.projectService;

  final results = await Future.wait<dynamic>([
    documentService.getDocuments(
      vendor.workspaceId,
      documentType: DocumentType.purchaseOrder,
    ).first,
    documentService.getDocuments(
      vendor.workspaceId,
      documentType: DocumentType.bill,
    ).first,
    documentService.getDocuments(
      vendor.workspaceId,
      documentType: DocumentType.requestForBid,
    ).first,
    projectService.getProjectsOnce(vendor.workspaceId),
  ]);

  final purchaseOrders = (results[0] as List<GeneratedDocument>)
      .where((d) => d.vendorId == vendor.id)
      .toList();
  final bills = (results[1] as List<GeneratedDocument>)
      .where((d) => d.vendorId == vendor.id)
      .toList();
  final bidRequests = (results[2] as List<GeneratedDocument>)
      .where((d) => d.vendorId == vendor.id)
      .toList();
  final projects = results[3] as List<Project>;

  final projectIds = <String>{
    ...purchaseOrders.where((d) => d.projectId != null).map((d) => d.projectId!),
    ...bills.where((d) => d.projectId != null).map((d) => d.projectId!),
    ...bidRequests.where((d) => d.projectId != null).map((d) => d.projectId!),
  };

  final projectsById = <String, Project>{
    for (final project in projects)
      if (projectIds.contains(project.id)) project.id: project,
  };

  return VendorRelatedProjectScope(
    purchaseOrders: purchaseOrders,
    bills: bills,
    bidRequests: bidRequests,
    projectsById: projectsById,
  );
}
