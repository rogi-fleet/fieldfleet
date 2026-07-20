import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../models/budget_item.dart';
import '../../../models/pay_app_line.dart';
import '../../../models/pay_application.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/pay_application_pdf_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/supabase/pay_application_service.dart';
import '../../../utils/confirm_dialog.dart';
import '../../../utils/project_terminology.dart';
import '../../../utils/numeric_input.dart';
import '../../../theme/theme.dart';

/// AIA G702/G703 Payment Application editor.
///
/// One screen drives both create (`payAppId == 'new'`) and edit. On create
/// it pulls budget items + rolls over the prior pay app via
/// [PayApplicationService.buildDraftFromBudget].
class PayApplicationEditorScreen extends StatefulWidget {
  final String projectId;
  final String payAppId; // 'new' for create

  const PayApplicationEditorScreen({
    super.key,
    required this.projectId,
    required this.payAppId,
  });

  @override
  State<PayApplicationEditorScreen> createState() =>
      _PayApplicationEditorScreenState();
}

class _PayApplicationEditorScreenState
    extends State<PayApplicationEditorScreen> {
  final _svc = PayApplicationService();
  final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  final _pct = NumberFormat.decimalPercentPattern(decimalDigits: 1);

  bool _loading = true;
  bool _saving = false;
  String? _error;

  PayApplication? _app;

  // Editable per-row state. We keep a working list of lines and rebuild
  // PayApplication for totals on every change.
  final List<_LineDraft> _drafts = [];

  // Header controllers
  final _contractorNameCtl = TextEditingController();
  final _contractorAddressCtl = TextEditingController();
  final _ownerNameCtl = TextEditingController();
  final _ownerAddressCtl = TextEditingController();
  final _architectNameCtl = TextEditingController();
  final _architectProjectNoCtl = TextEditingController();
  final _contractForCtl = TextEditingController();
  final _originalSumCtl = TextEditingController();
  final _coTotalCtl = TextEditingController();
  final _retCompletedCtl = TextEditingController();
  final _retStoredCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  DateTime? _periodFrom;
  DateTime? _periodTo;
  DateTime? _dateIssued;
  DateTime? _contractDate;

  bool get _isNew => widget.payAppId == 'new';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contractorNameCtl.dispose();
    _contractorAddressCtl.dispose();
    _ownerNameCtl.dispose();
    _ownerAddressCtl.dispose();
    _architectNameCtl.dispose();
    _architectProjectNoCtl.dispose();
    _contractForCtl.dispose();
    _originalSumCtl.dispose();
    _coTotalCtl.dispose();
    _retCompletedCtl.dispose();
    _retStoredCtl.dispose();
    _notesCtl.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final project =
          await ServiceLocator.projectService.getProject(widget.projectId);
      if (project == null) {
        setState(() {
          _loading = false;
          _error = 'Project not found.';
        });
        return;
      }

      PayApplication app;
      if (_isNew) {
        final items = await ServiceLocator.budgetService
            .getBudgetItems(widget.projectId)
            .first;
        app = await _svc.buildDraftFromBudget(
          workspaceId: project.workspaceId,
          projectId: widget.projectId,
          budgetItems: items as List<BudgetItem>,
          contractorName: null,
          ownerName: project.customerName,
        );
      } else {
        final loaded = await _svc.getById(widget.payAppId);
        if (loaded == null) {
          setState(() {
            _loading = false;
            _error = 'Pay application not found.';
          });
          return;
        }
        app = loaded;
      }

      _bindHeader(app);
      _bindLines(app.lines);
      setState(() {
        _app = app;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  void _bindHeader(PayApplication app) {
    _contractorNameCtl.text = app.contractorName ?? '';
    _contractorAddressCtl.text = app.contractorAddress ?? '';
    _ownerNameCtl.text = app.ownerName ?? '';
    _ownerAddressCtl.text = app.ownerAddress ?? '';
    _architectNameCtl.text = app.architectName ?? '';
    _architectProjectNoCtl.text = app.architectProjectNo ?? '';
    _contractForCtl.text = app.contractFor ?? '';
    _originalSumCtl.text = app.originalContractSum.toStringAsFixed(2);
    _coTotalCtl.text = app.netChangeByChangeOrders.toStringAsFixed(2);
    _retCompletedCtl.text = app.retainagePctCompleted.toStringAsFixed(2);
    _retStoredCtl.text = app.retainagePctStored.toStringAsFixed(2);
    _notesCtl.text = app.notes ?? '';
    _periodFrom = app.periodFrom;
    _periodTo = app.periodTo;
    _dateIssued = app.dateIssued;
    _contractDate = app.contractDate;
  }

  void _bindLines(List<PayAppLine> lines) {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts
      ..clear()
      ..addAll(lines.map(_LineDraft.fromLine));
  }

  // ── Computed snapshot for totals ─────────────────────────────────
  PayApplication _snapshot() {
    final base = _app!;
    final lines = <PayAppLine>[];
    for (var i = 0; i < _drafts.length; i++) {
      final d = _drafts[i];
      final overrideText = d.retainageOverride.text.trim();
      lines.add(PayAppLine(
        id: d.id,
        payApplicationId: base.id,
        workspaceId: base.workspaceId,
        budgetItemId: d.budgetItemId,
        itemNo: d.itemNo.text.isEmpty ? (i + 1).toString() : d.itemNo.text,
        description: d.description.text,
        scheduledValue: _parseNum(d.scheduledValue.text),
        workCompletedPrevious: _parseNum(d.previous.text),
        workCompletedThisPeriod: _parseNum(d.thisPeriod.text),
        materialsStored: _parseNum(d.stored.text),
        retainageOverride:
            overrideText.isEmpty ? null : double.tryParse(overrideText),
        sortOrder: i,
      ));
    }
    return base.copyWith(
      contractorName: _contractorNameCtl.text,
      contractorAddress: _contractorAddressCtl.text.trim().isEmpty
          ? null
          : _contractorAddressCtl.text.trim(),
      ownerName: _ownerNameCtl.text,
      ownerAddress: _ownerAddressCtl.text.trim().isEmpty
          ? null
          : _ownerAddressCtl.text.trim(),
      architectName: _architectNameCtl.text,
      architectProjectNo: _architectProjectNoCtl.text.trim().isEmpty
          ? null
          : _architectProjectNoCtl.text.trim(),
      contractFor: _contractForCtl.text,
      originalContractSum: _parseNum(_originalSumCtl.text),
      netChangeByChangeOrders: _parseNum(_coTotalCtl.text),
      retainagePctCompleted: _parseNum(_retCompletedCtl.text),
      retainagePctStored: _parseNum(_retStoredCtl.text),
      notes: _notesCtl.text,
      periodFrom: _periodFrom,
      periodTo: _periodTo,
      dateIssued: _dateIssued,
      contractDate: _contractDate,
      lines: lines,
    );
  }

  double _parseNum(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0.0;

  Future<void> _save({bool submit = false}) async {
    if (_app == null) return;
    setState(() => _saving = true);
    try {
      var app = _snapshot();
      if (submit) {
        app = app.copyWith(status: PayApplicationStatus.submitted);
      }
      // Persist header-level snapshots so list views and downstream rollovers
      // don't depend on line rows being re-fetched.
      app = app.copyWith(
        currentPaymentDueSnapshot: app.currentPaymentDue,
        totalCompletedStoredSnapshot: app.totalCompletedAndStored,
        totalRetainageSnapshot: app.totalRetainage,
      );

      String id = app.id;
      final wasNew = _isNew && id.isEmpty;
      if (wasNew) {
        id = await _svc.createHeader(app);
        app = app.copyWith(id: id);
      } else {
        await _svc.updateHeader(app);
      }

      final stampedLines = app.lines
          .map((l) => PayAppLine(
                id: l.id,
                payApplicationId: id,
                workspaceId: l.workspaceId,
                budgetItemId: l.budgetItemId,
                itemNo: l.itemNo,
                description: l.description,
                scheduledValue: l.scheduledValue,
                workCompletedPrevious: l.workCompletedPrevious,
                workCompletedThisPeriod: l.workCompletedThisPeriod,
                materialsStored: l.materialsStored,
                retainageOverride: l.retainageOverride,
                sortOrder: l.sortOrder,
              ))
          .toList();
      await _svc.replaceLines(id, stampedLines);

      // Refresh in-memory header so status chip / future saves reflect DB.
      _app = app.copyWith(lines: stampedLines);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(submit
                ? 'Pay Application #${app.applicationNumber} submitted.'
                : 'Saved.')),
      );
      // Navigate to canonical edit URL after first save.
      if (wasNew) {
        context.go('/projects/${widget.projectId}/pay-applications/$id');
      } else {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectTerm = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pay Application')),
        body: Center(child: SelectableText(_error!)),
      );
    }

    final snap = _snapshot();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew
            ? 'New Pay Application'
            : 'Pay Application #${snap.applicationNumber}'),
        actions: [
          if (!_isNew)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Center(
                child: Chip(
                  label: Text(snap.status.displayLabel),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (!_isNew)
            IconButton(
              tooltip: 'Print / Download PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _saving ? null : _printPdf,
            ),
          if (!_isNew)
            IconButton(
              tooltip: 'Save PDF to $projectTerm Documents',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: _saving ? null : _saveToDocuments,
            ),
          TextButton.icon(
            onPressed: _saving ? null : () => _save(),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Draft'),
          ),
          if (snap.status == PayApplicationStatus.draft ||
              snap.status == PayApplicationStatus.submitted)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _save(submit: true),
                icon: const Icon(Icons.send),
                label: Text(snap.status == PayApplicationStatus.submitted
                    ? 'Re-submit'
                    : 'Submit'),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _G702HeaderCard(
              theme: theme,
              app: snap,
              contractorNameCtl: _contractorNameCtl,
              contractorAddressCtl: _contractorAddressCtl,
              ownerNameCtl: _ownerNameCtl,
              ownerAddressCtl: _ownerAddressCtl,
              architectNameCtl: _architectNameCtl,
              architectProjectNoCtl: _architectProjectNoCtl,
              contractForCtl: _contractForCtl,
              originalSumCtl: _originalSumCtl,
              coTotalCtl: _coTotalCtl,
              retCompletedCtl: _retCompletedCtl,
              retStoredCtl: _retStoredCtl,
              periodFrom: _periodFrom,
              periodTo: _periodTo,
              dateIssued: _dateIssued,
              contractDate: _contractDate,
              onPickFrom: () async {
                final picked = await _pickDate(_periodFrom);
                if (picked != null) setState(() => _periodFrom = picked);
              },
              onPickTo: () async {
                final picked = await _pickDate(_periodTo);
                if (picked != null) setState(() => _periodTo = picked);
              },
              onPickDateIssued: () async {
                final picked = await _pickDate(_dateIssued);
                if (picked != null) setState(() => _dateIssued = picked);
              },
              onPickContractDate: () async {
                final picked = await _pickDate(_contractDate);
                if (picked != null) setState(() => _contractDate = picked);
              },
              onChanged: () => setState(() {}),
              money: _money,
            ),
            const SizedBox(height: 16),
            _G703Grid(
              theme: theme,
              drafts: _drafts,
              app: snap,
              money: _money,
              pct: _pct,
              onChanged: () => setState(() {}),
              onAddLine: () => setState(() {
                _drafts.add(_LineDraft.blank(snap.workspaceId, _drafts.length));
              }),
              onRemoveLine: (i) => setState(() {
                _drafts.removeAt(i).dispose();
              }),
            ),
            const SizedBox(height: 16),
            if (!_isNew && snap.status != PayApplicationStatus.draft)
              _CertificationCard(
                app: snap,
                money: _money,
                onCertify: _certify,
                onMarkPaid: _markPaid,
                saving: _saving,
              ),
            const SizedBox(height: 16),
            _NotesCard(controller: _notesCtl),
          ],
        ),
      ),
    );
  }

  Future<void> _printPdf() async {
    final app = _snapshot().copyWith(id: _app!.id);
    try {
      final bytes = await PayApplicationPdfService.build(app);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name:
            'Pay-App-${app.applicationNumber}-${app.contractorName ?? 'contractor'}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate PDF: $e')),
      );
    }
  }

  Future<void> _saveToDocuments() async {
    if (_app == null || _app!.id.isEmpty) return;
    final projectTermLower = singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();
    setState(() => _saving = true);
    try {
      final app = _snapshot().copyWith(id: _app!.id);
      final bytes = await PayApplicationPdfService.build(app);
      final uploader = ServiceLocator.authService.currentUserId ?? '';
      final periodLabel = _periodTo != null
          ? DateFormat('yyyy-MM-dd').format(_periodTo!)
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      final fileName = 'Pay-App-${app.applicationNumber}-$periodLabel.pdf';
      await ServiceLocator.storageService.uploadFileBytes(
        bytes: bytes,
        fileName: fileName,
        workspaceId: app.workspaceId,
        projectId: widget.projectId,
        uploadedBy: uploader,
        tags: const ['pay-app', 'aia-g702'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "$fileName" to $projectTermLower files.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save to Documents: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _certify(double amount, String by) async {
    if (_app == null || _app!.id.isEmpty) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await _svc.certify(
        id: _app!.id,
        amountCertified: amount,
        certifiedBy: by,
        certifiedAt: now,
      );
      _app = _app!.copyWith(
        status: PayApplicationStatus.certified,
        certifiedAmount: amount,
        certifiedBy: by,
        certifiedAt: now,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Certified.')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Certify failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markPaid() async {
    if (_app == null || _app!.id.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _svc.markPaid(_app!.id);
      _app = _app!.copyWith(status: PayApplicationStatus.paid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked paid.')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mark paid failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<DateTime?> _pickDate(DateTime? current) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Per-row editable state. Holds all column controllers for one line.
// ─────────────────────────────────────────────────────────────────────
class _LineDraft {
  String id;
  String? budgetItemId;
  final TextEditingController itemNo;
  final TextEditingController description;
  final TextEditingController scheduledValue;
  final TextEditingController previous;
  final TextEditingController thisPeriod;
  final TextEditingController stored;
  // Empty string = no override; otherwise a per-line retainage $ amount that
  // replaces the header-percentage calculation for this row.
  final TextEditingController retainageOverride;

  _LineDraft({
    required this.id,
    required this.budgetItemId,
    required this.itemNo,
    required this.description,
    required this.scheduledValue,
    required this.previous,
    required this.thisPeriod,
    required this.stored,
    required this.retainageOverride,
  });

  factory _LineDraft.fromLine(PayAppLine l) => _LineDraft(
        id: l.id,
        budgetItemId: l.budgetItemId,
        itemNo: TextEditingController(text: l.itemNo ?? ''),
        description: TextEditingController(text: l.description),
        scheduledValue:
            TextEditingController(text: l.scheduledValue.toStringAsFixed(2)),
        previous: TextEditingController(
            text: l.workCompletedPrevious.toStringAsFixed(2)),
        thisPeriod: TextEditingController(
            text: l.workCompletedThisPeriod.toStringAsFixed(2)),
        stored:
            TextEditingController(text: l.materialsStored.toStringAsFixed(2)),
        retainageOverride: TextEditingController(
            text: l.retainageOverride?.toStringAsFixed(2) ?? ''),
      );

  factory _LineDraft.blank(String workspaceId, int index) => _LineDraft(
        id: '',
        budgetItemId: null,
        itemNo: TextEditingController(text: (index + 1).toString()),
        description: TextEditingController(),
        scheduledValue: TextEditingController(text: '0.00'),
        previous: TextEditingController(text: '0.00'),
        thisPeriod: TextEditingController(text: '0.00'),
        stored: TextEditingController(text: '0.00'),
        retainageOverride: TextEditingController(),
      );

  void dispose() {
    itemNo.dispose();
    description.dispose();
    scheduledValue.dispose();
    previous.dispose();
    thisPeriod.dispose();
    stored.dispose();
    retainageOverride.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────
// G702 header (Contract Sum, Change Orders, Retainage, Totals)
// ─────────────────────────────────────────────────────────────────────
class _G702HeaderCard extends StatelessWidget {
  final ThemeData theme;
  final PayApplication app;
  final TextEditingController contractorNameCtl;
  final TextEditingController contractorAddressCtl;
  final TextEditingController ownerNameCtl;
  final TextEditingController ownerAddressCtl;
  final TextEditingController architectNameCtl;
  final TextEditingController architectProjectNoCtl;
  final TextEditingController contractForCtl;
  final TextEditingController originalSumCtl;
  final TextEditingController coTotalCtl;
  final TextEditingController retCompletedCtl;
  final TextEditingController retStoredCtl;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final DateTime? dateIssued;
  final DateTime? contractDate;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onPickDateIssued;
  final VoidCallback onPickContractDate;
  final VoidCallback onChanged;
  final NumberFormat money;

  const _G702HeaderCard({
    required this.theme,
    required this.app,
    required this.contractorNameCtl,
    required this.contractorAddressCtl,
    required this.ownerNameCtl,
    required this.ownerAddressCtl,
    required this.architectNameCtl,
    required this.architectProjectNoCtl,
    required this.contractForCtl,
    required this.originalSumCtl,
    required this.coTotalCtl,
    required this.retCompletedCtl,
    required this.retStoredCtl,
    required this.periodFrom,
    required this.periodTo,
    required this.dateIssued,
    required this.contractDate,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onPickDateIssued,
    required this.onPickContractDate,
    required this.onChanged,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('G702 — Application and Certificate for Payment',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _field('To Owner', ownerNameCtl, width: 260),
                _field('Owner Address', ownerAddressCtl, width: 260, lines: 2),
                _field('From Contractor', contractorNameCtl, width: 260),
                _field('Contractor Address', contractorAddressCtl,
                    width: 260, lines: 2),
                _field('Architect', architectNameCtl, width: 220),
                _field('Architect Project No.', architectProjectNoCtl,
                    width: 200),
                _field('Contract For', contractForCtl, width: 260),
                _dateField(
                    'Contract Date', contractDate, df, onPickContractDate),
                _dateField('Date Issued', dateIssued, df, onPickDateIssued),
                _dateField('Period From', periodFrom, df, onPickFrom),
                _dateField('Period To', periodTo, df, onPickTo),
              ],
            ),
            const Divider(height: 32),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _money2('1. Original Contract Sum', originalSumCtl),
                _money2('2. Net change by Change Orders', coTotalCtl),
                _readMoney(
                    '3. Contract Sum To Date (1+2)', app.contractSumToDate),
                _readMoney(
                    '4. Total Completed & Stored', app.totalCompletedAndStored),
                _pctField('Retainage % (Completed)', retCompletedCtl),
                _pctField('Retainage % (Stored)', retStoredCtl),
                _readMoney('5. Total Retainage', app.totalRetainage),
                _readMoney('6. Total Earned Less Retainage (4-5)',
                    app.totalEarnedLessRetainage),
                _readMoney('7. Less Previous Certificates',
                    app.lessPreviousCertificates),
                _readMoney('8. CURRENT PAYMENT DUE', app.currentPaymentDue,
                    highlight: true),
                _readMoney(
                    '9. Balance to Finish + Retainage', app.balanceToFinish),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {double width = 240, int lines = 1}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }

  Widget _money2(String label, TextEditingController c) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: c,
        keyboardType: NumericInput.signedKeyboard,
        inputFormatters: NumericInput.signedCurrency,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          prefixText: r'$ ',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }

  Widget _pctField(String label, TextEditingController c) {
    return SizedBox(
      width: 200,
      child: TextField(
        controller: c,
        keyboardType: NumericInput.keyboard,
        inputFormatters: NumericInput.percent(signed: false),
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          suffixText: '%',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }

  Widget _readMoney(String label, double value, {bool highlight = false}) {
    return SizedBox(
      width: 240,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          filled: highlight,
          fillColor: highlight
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
              : null,
        ),
        child: Text(
          money.format(value),
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _dateField(
      String label, DateTime? date, DateFormat df, VoidCallback onTap) {
    return SizedBox(
      width: 180,
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today, size: 16),
          ),
          child: Text(date == null ? '—' : df.format(date)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// G703 spreadsheet-style grid
// ─────────────────────────────────────────────────────────────────────
class _G703Grid extends StatelessWidget {
  final ThemeData theme;
  final List<_LineDraft> drafts;
  final PayApplication app;
  final NumberFormat money;
  final NumberFormat pct;
  final VoidCallback onChanged;
  final VoidCallback onAddLine;
  final void Function(int index) onRemoveLine;

  const _G703Grid({
    required this.theme,
    required this.drafts,
    required this.app,
    required this.money,
    required this.pct,
    required this.onChanged,
    required this.onAddLine,
    required this.onRemoveLine,
  });

  // Column widths (pixels) — must sum to roughly fit common screen widths.
  static const _colItemNo = 56.0;
  static const _colDesc = 280.0;
  static const _colNum = 120.0;
  static const _colPct = 70.0;
  static const _colActions = 56.0;

  static const _columns = <_Col>[
    _Col('Item', _colItemNo),
    _Col('Description', _colDesc),
    _Col('Scheduled Value', _colNum),
    _Col('Previous', _colNum),
    _Col('This Period', _colNum),
    _Col('Stored', _colNum),
    _Col('Total Completed', _colNum),
    _Col('%', _colPct),
    _Col('Balance', _colNum),
    _Col('Retainage', _colNum),
    _Col('', _colActions),
  ];

  @override
  Widget build(BuildContext context) {
    final tableWidth =
        _columns.fold<double>(0, (s, c) => s + c.width) + _columns.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('G703 — Continuation Sheet',
                      style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: onAddLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Line'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      _header(theme),
                      const Divider(height: 1),
                      ...List.generate(drafts.length, (i) {
                        return _row(theme, i);
                      }),
                      const Divider(height: 1),
                      _totalsRow(theme),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding:
          const EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.xs),
      child: Row(
        children: _columns
            .map((c) => SizedBox(
                  width: c.width,
                  child: Text(
                    c.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _row(ThemeData theme, int i) {
    final d = drafts[i];
    final line = app.lines[i];
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 2, horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          _cellInput(d.itemNo, _colItemNo, center: true),
          _cellInput(d.description, _colDesc),
          _cellMoney(d.scheduledValue, _colNum),
          _cellMoney(d.previous, _colNum),
          _cellMoney(d.thisPeriod, _colNum),
          _cellMoney(d.stored, _colNum),
          _cellRead(money.format(line.totalCompletedAndStored), _colNum),
          _cellRead('${line.percentComplete.toStringAsFixed(1)}%', _colPct,
              center: true),
          _cellRead(money.format(line.balanceToFinish), _colNum),
          _cellRetainage(d.retainageOverride, line, _colNum),
          SizedBox(
            width: _colActions,
            child: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  final label = line.description.trim().isEmpty
                      ? 'this line'
                      : '"${line.description.trim()}"';
                  final ok = await confirmDestructive(
                    ctx,
                    title: 'Remove line?',
                    message: 'Remove $label from this pay application? Any '
                        'completed/stored values entered for it will be lost.',
                    confirmLabel: 'Remove',
                  );
                  if (ok) onRemoveLine(i);
                },
                tooltip: 'Remove line',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalsRow(ThemeData theme) {
    final scheduled = app.lines.fold<double>(0, (s, l) => s + l.scheduledValue);
    final previous =
        app.lines.fold<double>(0, (s, l) => s + l.workCompletedPrevious);
    final thisPeriod =
        app.lines.fold<double>(0, (s, l) => s + l.workCompletedThisPeriod);
    final stored = app.lines.fold<double>(0, (s, l) => s + l.materialsStored);
    final total = app.totalCompletedAndStored;
    final balance = scheduled - total;

    Widget cell(String text, double w, {bool center = false}) => SizedBox(
          width: w,
          child: Text(text,
              textAlign: center ? TextAlign.center : TextAlign.right,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        );

    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
      child: Row(
        children: [
          cell('', _colItemNo),
          cell('TOTALS', _colDesc, center: true),
          cell(money.format(scheduled), _colNum),
          cell(money.format(previous), _colNum),
          cell(money.format(thisPeriod), _colNum),
          cell(money.format(stored), _colNum),
          cell(money.format(total), _colNum),
          cell(
              scheduled > 0
                  ? '${(total / scheduled * 100).toStringAsFixed(1)}%'
                  : '0.0%',
              _colPct,
              center: true),
          cell(money.format(balance), _colNum),
          cell(money.format(app.totalRetainage), _colNum),
          const SizedBox(width: _colActions),
        ],
      ),
    );
  }

  String _lineRetainage(PayAppLine l) {
    if (l.retainageOverride != null) return money.format(l.retainageOverride!);
    final completedRet = (l.workCompletedPrevious + l.workCompletedThisPeriod) *
        (app.retainagePctCompleted / 100.0);
    final storedRet = l.materialsStored * (app.retainagePctStored / 100.0);
    return money.format(completedRet + storedRet);
  }

  Widget _cellInput(TextEditingController c, double w, {bool center = false}) {
    return SizedBox(
      width: w,
      child: TextField(
        controller: c,
        textAlign: center ? TextAlign.center : TextAlign.left,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.sm),
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }

  Widget _cellMoney(TextEditingController c, double w) {
    return SizedBox(
      width: w,
      child: TextField(
        controller: c,
        textAlign: TextAlign.right,
        keyboardType: NumericInput.keyboard,
        inputFormatters: NumericInput.currency,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.sm),
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }

  Widget _cellRead(String text, double w, {bool center = false}) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child:
            Text(text, textAlign: center ? TextAlign.center : TextAlign.right),
      ),
    );
  }

  /// Editable retainage cell. When empty, displays the header-percentage
  /// derived amount as a hint (italic placeholder); typing a value sets a
  /// per-line override on the underlying PayAppLine.
  Widget _cellRetainage(TextEditingController c, PayAppLine line, double w) {
    final calculated = _lineRetainage(line);
    return SizedBox(
      width: w,
      child: TextField(
        controller: c,
        textAlign: TextAlign.right,
        keyboardType: NumericInput.keyboard,
        inputFormatters: NumericInput.currency,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 6, vertical: AppSpacing.sm),
          border: const OutlineInputBorder(),
          hintText: calculated,
          hintStyle: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _Col {
  final String label;
  final double width;
  const _Col(this.label, this.width);
}

class _NotesCard extends StatelessWidget {
  final TextEditingController controller;
  const _NotesCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notes',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Architect certification + payment recording
// ─────────────────────────────────────────────────────────────────────
class _CertificationCard extends StatefulWidget {
  final PayApplication app;
  final NumberFormat money;
  final Future<void> Function(double amount, String by) onCertify;
  final Future<void> Function() onMarkPaid;
  final bool saving;

  const _CertificationCard({
    required this.app,
    required this.money,
    required this.onCertify,
    required this.onMarkPaid,
    required this.saving,
  });

  @override
  State<_CertificationCard> createState() => _CertificationCardState();
}

class _CertificationCardState extends State<_CertificationCard> {
  late final TextEditingController _amountCtl;
  late final TextEditingController _byCtl;

  @override
  void initState() {
    super.initState();
    _amountCtl = TextEditingController(
      text: (widget.app.certifiedAmount ?? widget.app.currentPaymentDue)
          .toStringAsFixed(2),
    );
    _byCtl = TextEditingController(
      text: widget.app.certifiedBy ?? widget.app.architectName ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _CertificationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = oldWidget.app;
    final next = widget.app;
    final wasEditable = prev.status == PayApplicationStatus.submitted;
    final isEditable = next.status == PayApplicationStatus.submitted;
    // Refresh defaults only while inputs are still editable and the
    // underlying values shifted (e.g. re-submit after edits).
    if (isEditable &&
        (!wasEditable || prev.currentPaymentDue != next.currentPaymentDue)) {
      _amountCtl.text =
          (next.certifiedAmount ?? next.currentPaymentDue).toStringAsFixed(2);
    }
    if (isEditable &&
        (!wasEditable || prev.architectName != next.architectName)) {
      final by = next.certifiedBy ?? next.architectName ?? '';
      if (by.isNotEmpty && _byCtl.text.trim().isEmpty) {
        _byCtl.text = by;
      }
    }
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _byCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.app;
    final df = DateFormat.yMMMd();
    final isCertified = app.status == PayApplicationStatus.certified ||
        app.status == PayApplicationStatus.paid;
    final isPaid = app.status == PayApplicationStatus.paid;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text("Architect's Certificate for Payment",
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              Chip(label: Text(app.status.displayLabel)),
            ]),
            const SizedBox(height: 12),
            if (isCertified) ...[
              Wrap(spacing: 24, runSpacing: 8, children: [
                _kv('Amount Certified',
                    widget.money.format(app.certifiedAmount ?? 0)),
                _kv('Certified By', app.certifiedBy ?? '—'),
                _kv(
                    'Certified On',
                    app.certifiedAt == null
                        ? '—'
                        : df.format(app.certifiedAt!)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                if (!isPaid)
                  FilledButton.icon(
                    onPressed: widget.saving ? null : widget.onMarkPaid,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Mark Paid'),
                  ),
                if (isPaid)
                  const Chip(
                    avatar: Icon(Icons.check_circle, size: 18),
                    label: Text('Paid'),
                  ),
              ]),
            ] else ...[
              Text(
                'Submitted for certification. Enter the amount certified and '
                'who certified it, then approve.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _amountCtl,
                    keyboardType: NumericInput.keyboard,
                    inputFormatters: NumericInput.currency,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'Amount Certified',
                      prefixText: r'$ ',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _byCtl,
                    decoration: const InputDecoration(
                      labelText: 'Certified By (architect name)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.saving
                      ? null
                      : () {
                          final amt = double.tryParse(
                                  _amountCtl.text.replaceAll(',', '')) ??
                              0.0;
                          final by = _byCtl.text.trim();
                          if (by.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Certified By is required.')),
                            );
                            return;
                          }
                          widget.onCertify(amt, by);
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('Certify'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k,
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
        const SizedBox(height: 2),
        Text(v,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
