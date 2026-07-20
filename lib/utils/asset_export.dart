import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/project.dart';
import '../models/user.dart';
import '../utils/currency_utils.dart';

import 'budget_export_io.dart'
    if (dart.library.html) 'budget_export_web.dart' as platform_export;

/// Serialize a (typically filtered + sorted) list of assets to CSV and
/// hand it to the platform's share/download flow. Mirrors
/// [TaskExport] so the asset list screen doesn't need to know about
/// share_plus or dart:html.
class AssetExport {
  static final _dateFormat = DateFormat('yyyy-MM-dd');

  Future<void> exportAssetsToCsv({
    required List<Asset> assets,
    required Map<String, Project> projectMap,
    required Map<String, AppUser> usersMap,
    required String currencyCode,
    String fileLabel = 'assets',
  }) async {
    if (assets.isEmpty) {
      throw Exception('No assets to export');
    }

    final rows = <List<dynamic>>[
      [
        'Name',
        'Serial',
        'Status',
        'Category',
        'Location',
        'Tags',
        'Assigned to',
        'Assignment type',
        'Purchase date',
        'Purchase price',
        'Description',
        'Notes',
      ],
    ];

    for (final asset in assets) {
      final (assignee, assignmentType) = _resolveAssignment(
        asset,
        projectMap,
        usersMap,
      );

      rows.add([
        asset.name,
        asset.serialNumber ?? '',
        asset.status,
        asset.category,
        asset.location ?? '',
        asset.tags.join(', '),
        assignee,
        assignmentType,
        asset.purchaseDate != null
            ? _dateFormat.format(asset.purchaseDate!)
            : '',
        asset.purchasePrice != null
            ? CurrencyUtils.formatCurrency(asset.purchasePrice!, currencyCode)
            : '',
        asset.description ?? '',
        asset.notes ?? '',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final safeLabel =
        fileLabel.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w]'), '');
    final fileName =
        '${safeLabel}_${DateTime.now().millisecondsSinceEpoch}.csv';

    await platform_export.exportCsv(csv, fileName, 'Asset Export – $fileLabel');
  }

  (String assignee, String type) _resolveAssignment(
    Asset asset,
    Map<String, Project> projectMap,
    Map<String, AppUser> usersMap,
  ) {
    final projectId = asset.assignedToProjectId;
    if (projectId != null && projectId.isNotEmpty) {
      return (projectMap[projectId]?.name ?? projectId, 'project');
    }
    final userId = asset.assignedToUserId;
    if (userId != null && userId.isNotEmpty) {
      final user = usersMap[userId];
      final name = user?.displayName?.isNotEmpty == true
          ? user!.displayName!
          : user?.email ?? userId;
      return (name, 'user');
    }
    return ('', '');
  }
}
