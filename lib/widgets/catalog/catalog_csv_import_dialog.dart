import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/catalog_item.dart';
import '../../services/supabase/catalog_service.dart';
import '../../theme/theme.dart';
import '../../utils/budget_export_io.dart'
    if (dart.library.html) '../../utils/budget_export_web.dart'
    as platform_export;
import '../../utils/user_facing_error.dart';

Future<bool?> showCatalogCsvImportDialog(
  BuildContext context, {
  required String workspaceId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => CatalogCsvImportDialog(workspaceId: workspaceId),
  );
}

class CatalogCsvImportDialog extends StatefulWidget {
  final String workspaceId;

  const CatalogCsvImportDialog({super.key, required this.workspaceId});

  @override
  State<CatalogCsvImportDialog> createState() => _CatalogCsvImportDialogState();
}

class _CatalogCsvImportDialogState extends State<CatalogCsvImportDialog> {
  final SupabaseCatalogService _catalogService = SupabaseCatalogService();

  String? _fileName;
  String? _csvContent;
  CatalogCsvImportPreview? _preview;
  CatalogCsvImportMode _importMode = CatalogCsvImportMode.createAndUpdate;
  bool _allowHierarchyChanges = false;
  bool _skipHierarchyConflicts = false;
  bool _isLoadingPreview = false;
  bool _isImporting = false;
  String? _errorMessage;

  String get _modeLabel => switch (_importMode) {
        CatalogCsvImportMode.createAndUpdate => 'Create + Update',
        CatalogCsvImportMode.createOnly => 'Create Only',
        CatalogCsvImportMode.updateOnly => 'Update Only',
      };

  bool _hasRowIssue(CatalogCsvReportRow row) => row.warnings.isNotEmpty;

  Future<void> _pickCsvFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final csvContent = await _readPlatformFile(file);
      setState(() {
        _fileName = file.name;
        _csvContent = csvContent;
        _errorMessage = null;
      });
      await _loadPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = UserFacingError.uiMessage(e, action: 'reading CSV');
      });
    }
  }

  Future<String> _readPlatformFile(PlatformFile file) async {
    if (file.bytes != null) {
      return utf8.decode(file.bytes!, allowMalformed: true);
    }
    throw Exception('The selected file could not be read as CSV bytes.');
  }

  Future<void> _loadPreview() async {
    final csvContent = _csvContent;
    if (csvContent == null || csvContent.isEmpty) return;

    setState(() {
      _isLoadingPreview = true;
      _preview = null;
      _errorMessage = null;
    });

    try {
      final preview = await _catalogService.previewCatalogCsvImport(
        workspaceId: widget.workspaceId,
        csvContent: csvContent,
        mode: _importMode,
        allowHierarchyChanges: _allowHierarchyChanges,
        skipHierarchyConflicts: _skipHierarchyConflicts,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = UserFacingError.uiMessage(e, action: 'previewing CSV');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPreview = false);
      }
    }
  }

  Future<void> _importCsv() async {
    final csvContent = _csvContent;
    if (csvContent == null || csvContent.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      final result = await _catalogService.importCatalogCsv(
        workspaceId: widget.workspaceId,
        csvContent: csvContent,
        mode: _importMode,
        allowHierarchyChanges: _allowHierarchyChanges,
        skipHierarchyConflicts: _skipHierarchyConflicts,
      );
      String? reportExportError;
      final shouldExportReport = result.reportRows.any(_hasRowIssue);
      if (shouldExportReport) {
        try {
          await _exportReportCsv(
            reportType: 'result',
            rows: result.reportRows,
            totalRows: result.processedCount + result.skippedCount,
            processedRows: result.processedCount,
            createdRows: result.createdCount,
            updatedRows: result.updatedCount,
            skippedRows: result.skippedCount,
            unresolvedParentRows: result.unresolvedParentCount,
            issuesOnly: true,
          );
        } catch (e) {
          reportExportError = '$e';
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.processedCount} catalog row${result.processedCount == 1 ? '' : 's'} (${result.createdCount} created, ${result.updatedCount} updated)${reportExportError != null ? '. Report export failed.' : shouldExportReport ? '. Issues report download started.' : ''}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _errorMessage = UserFacingError.uiMessage(e, action: 'importing CSV');
      });
    }
  }

  Future<void> _exportPreviewReport() async {
    final preview = _preview;
    if (preview == null || preview.reportRows.isEmpty) return;
    try {
      await _exportReportCsv(
        reportType: 'preview',
        rows: preview.reportRows,
        totalRows: preview.totalRows,
        processedRows: preview.createCount + preview.updateCount,
        createdRows: preview.createCount,
        updatedRows: preview.updateCount,
        skippedRows: preview.skippedCount,
        unresolvedParentRows: preview.unresolvedParentCount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog import preview report started')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export preview report: $e')),
      );
    }
  }

  Future<void> _exportPreviewIssuesReport() async {
    final preview = _preview;
    if (preview == null) return;
    final issueRows = preview.reportRows.where(_hasRowIssue).toList();
    if (issueRows.isEmpty) return;
    try {
      await _exportReportCsv(
        reportType: 'preview',
        rows: preview.reportRows,
        totalRows: preview.totalRows,
        processedRows: preview.createCount + preview.updateCount,
        createdRows: preview.createCount,
        updatedRows: preview.updateCount,
        skippedRows: preview.skippedCount,
        unresolvedParentRows: preview.unresolvedParentCount,
        issuesOnly: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Catalog import issues-only report started'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export issues report: $e')),
      );
    }
  }

  Future<void> _exportReportCsv({
    required String reportType,
    required List<CatalogCsvReportRow> rows,
    required int totalRows,
    required int processedRows,
    required int createdRows,
    required int updatedRows,
    required int skippedRows,
    required int unresolvedParentRows,
    bool issuesOnly = false,
  }) async {
    final filteredRows =
        issuesOnly ? rows.where(_hasRowIssue).toList(growable: false) : rows;
    if (filteredRows.isEmpty) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final csv = const ListToCsvConverter().convert([
      [
        'report_type',
        'source_file',
        'import_mode',
        'allow_hierarchy_changes',
        'skip_hierarchy_conflicts',
        'total_rows',
        'processed_rows',
        'created_rows',
        'updated_rows',
        'skipped_rows',
        'unresolved_parent_rows',
        'row_number',
        'source_id',
        'name',
        'item_type',
        'action',
        'parent_source_id',
        'parent_label',
        'warnings',
      ],
      ...filteredRows.map(
        (row) => [
          issuesOnly ? '${reportType}_issues' : reportType,
          _fileName ?? '',
          _modeLabel,
          _allowHierarchyChanges,
          _skipHierarchyConflicts,
          totalRows,
          processedRows,
          createdRows,
          updatedRows,
          skippedRows,
          unresolvedParentRows,
          row.rowNumber,
          row.sourceId ?? '',
          row.name,
          row.itemType.name,
          row.actionLabel,
          row.parentSourceId ?? '',
          row.parentLabel,
          row.warnings.join(' | '),
        ],
      ),
    ]);

    await platform_export.exportCsv(
      csv,
      'catalog_import_$reportType${issuesOnly ? '_issues' : ''}_$timestamp.csv',
      'FieldFleet Catalog Import ${reportType == 'preview' ? 'Preview' : 'Result'}${issuesOnly ? ' Issues' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Dialog(
      child: Container(
        width: 720,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildPickerCard(context),
            const SizedBox(height: 12),
            _buildImportModeSelector(),
            if (_importMode != CatalogCsvImportMode.createOnly)
              CheckboxListTile(
                value: _allowHierarchyChanges,
                onChanged: _isLoadingPreview || _isImporting
                    ? null
                    : (value) {
                        setState(() => _allowHierarchyChanges = value ?? false);
                        _loadPreview();
                      },
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow hierarchy changes for existing items'),
                subtitle: const Text(
                  'Required if a matching CSV row would move to a different parent or change between item and group.',
                ),
              ),
            if (_importMode != CatalogCsvImportMode.createOnly &&
                !_allowHierarchyChanges)
              CheckboxListTile(
                value: _skipHierarchyConflicts,
                onChanged: _isLoadingPreview || _isImporting
                    ? null
                    : (value) {
                        setState(
                          () => _skipHierarchyConflicts = value ?? false,
                        );
                        _loadPreview();
                      },
                contentPadding: EdgeInsets.zero,
                title: const Text('Skip hierarchy conflicts'),
                subtitle: const Text(
                  'Conflicting update rows will be skipped instead of blocking the import.',
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoadingPreview
                  ? const Center(child: CircularProgressIndicator())
                  : _buildPreviewArea(preview),
            ),
            const SizedBox(height: 16),
            _buildFooter(preview),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import Catalog CSV',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Upload a catalog CSV to create or update company catalog items.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _buildPickerCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_outlined, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fileName ?? 'No CSV selected',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _fileName == null
                      ? 'Use the catalog export or template format for best results.'
                      : 'Preview is generated from the selected file before import.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _isLoadingPreview || _isImporting ? null : _pickCsvFile,
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(_fileName == null ? 'Choose CSV' : 'Replace CSV'),
          ),
        ],
      ),
    );
  }

  Widget _buildImportModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Import mode',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<CatalogCsvImportMode>(
          segments: const [
            ButtonSegment<CatalogCsvImportMode>(
              value: CatalogCsvImportMode.createAndUpdate,
              label: Text('Create + Update'),
              icon: Icon(Icons.sync_alt, size: 16),
            ),
            ButtonSegment<CatalogCsvImportMode>(
              value: CatalogCsvImportMode.createOnly,
              label: Text('Create Only'),
              icon: Icon(Icons.add_box_outlined, size: 16),
            ),
            ButtonSegment<CatalogCsvImportMode>(
              value: CatalogCsvImportMode.updateOnly,
              label: Text('Update Only'),
              icon: Icon(Icons.system_update_alt, size: 16),
            ),
          ],
          selected: {_importMode},
          onSelectionChanged: _isLoadingPreview || _isImporting
              ? null
              : (selection) {
                  final nextMode = selection.first;
                  setState(() {
                    _importMode = nextMode;
                    if (_importMode == CatalogCsvImportMode.createOnly) {
                      _allowHierarchyChanges = false;
                      _skipHierarchyConflicts = false;
                    }
                  });
                  _loadPreview();
                },
        ),
        const SizedBox(height: 6),
        Text(
            switch (_importMode) {
              CatalogCsvImportMode.createAndUpdate =>
                'Create new rows and update matching existing IDs.',
              CatalogCsvImportMode.createOnly =>
                'Only create rows that do not already exist. Matching IDs are skipped.',
              CatalogCsvImportMode.updateOnly =>
                'Only update rows with matching existing IDs. New rows are skipped.',
            },
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildPreviewArea(CatalogCsvImportPreview? preview) {
    if (_errorMessage != null) {
      return Center(
        child: SelectableText(
          _errorMessage!,
          style: const TextStyle(color: AppColors.error),
        ),
      );
    }

    if (_csvContent == null) {
      return Center(
        child: Text(
          'Choose a CSV file to preview the import.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (preview == null) {
      return const SizedBox.shrink();
    }

    final issueCount = preview.reportRows.where(_hasRowIssue).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildStatCard('Rows', '${preview.totalRows}'),
              _buildStatCard('Create', '${preview.createCount}'),
              _buildStatCard('Update', '${preview.updateCount}'),
              _buildStatCard('Groups', '${preview.groupCount}'),
              _buildStatCard('Items', '${preview.itemCount}'),
              _buildStatCard(
                'Unresolved Parents',
                '${preview.unresolvedParentCount}',
              ),
              _buildStatCard(
                'Hierarchy Conflicts',
                '${preview.hierarchyConflictCount}',
              ),
              _buildStatCard('Skipped', '${preview.skippedCount}'),
              _buildStatCard('Flagged', '$issueCount'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Detected columns',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: preview.fileHeaders
                .map((header) => Chip(label: Text(header)))
                .toList(growable: false),
          ),
          if (preview.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Warnings',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final warning in preview.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: AppColors.warningDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(warning)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            'Row preview',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: preview.reportRows.isEmpty || _isImporting
                      ? null
                      : _exportPreviewReport,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Export Full Report'),
                ),
                OutlinedButton.icon(
                  onPressed: issueCount == 0 || _isImporting
                      ? null
                      : _exportPreviewIssuesReport,
                  icon: const Icon(Icons.report_problem_outlined, size: 18),
                  label: const Text('Export Issues Only'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Column(
              children: [
                for (final row in preview.previewRows)
                  _buildPreviewRowTile(row),
                if (preview.additionalRowCount > 0)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      '${preview.additionalRowCount} more row${preview.additionalRowCount == 1 ? '' : 's'} not shown in preview',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRowTile(CatalogCsvReportRow row) {
    final isGroup = row.itemType == CatalogItemType.group;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isGroup ? Icons.folder_open_outlined : Icons.inventory_2_outlined,
            size: 18,
            color: isGroup ? AppColors.infoDark : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: switch (row.actionLabel) {
                          'Update' => AppColors.info.withValues(alpha: 0.12),
                          'Skip' => AppColors.warning.withValues(alpha: 0.14),
                          'Conflict' => AppColors.error.withValues(alpha: 0.10),
                          _ => AppColors.success.withValues(alpha: 0.12),
                        },
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        row.actionLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: switch (row.actionLabel) {
                            'Update' => AppColors.infoDark,
                            'Skip' => AppColors.warningDark,
                            'Conflict' => AppColors.errorDark,
                            _ => AppColors.success,
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Row ${row.rowNumber} • ${isGroup ? 'Group' : 'Item'} • ${row.parentLabel}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (row.warnings.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final warning in row.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        warning,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.warningDark,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(CatalogCsvImportPreview? preview) {
    final canImport = preview != null &&
        preview.totalRows > 0 &&
        (preview.hierarchyConflictCount == 0 ||
            _allowHierarchyChanges ||
            _skipHierarchyConflicts) &&
        (preview.createCount + preview.updateCount > 0) &&
        !_isLoadingPreview &&
        !_isImporting;

    return Row(
      children: [
        if (preview != null)
          Expanded(
            child: Text(
              preview.createCount + preview.updateCount == 0
                  ? 'No rows will be imported with the current mode.'
                  : preview.hierarchyConflictCount > 0 &&
                          !_allowHierarchyChanges &&
                          !_skipHierarchyConflicts
                      ? 'Enable hierarchy changes or skip conflicts to import ${preview.hierarchyConflictCount} conflicting row${preview.hierarchyConflictCount == 1 ? '' : 's'}.'
                      : _skipHierarchyConflicts &&
                              preview.hierarchyConflictCount > 0 &&
                              !_allowHierarchyChanges
                          ? 'Conflicting hierarchy updates will be skipped.'
                          : 'This import will process ${preview.createCount + preview.updateCount} row${preview.createCount + preview.updateCount == 1 ? '' : 's'}.',
              style: TextStyle(
                color: (preview.createCount + preview.updateCount == 0) ||
                        (preview.hierarchyConflictCount > 0 &&
                            !_allowHierarchyChanges &&
                            !_skipHierarchyConflicts)
                    ? AppColors.warningDark
                    : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        if (preview == null) const Spacer(),
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: canImport ? _importCsv : null,
          icon: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined, size: 18),
          label: Text(_isImporting ? 'Importing...' : 'Import CSV'),
        ),
      ],
    );
  }
}
