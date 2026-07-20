import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../models/holdback_release.dart';
import '../../../models/project.dart';
import '../../../services/holdback_pdf_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/supabase/holdback_service.dart';
import '../../../utils/numeric_input.dart';
import '../../../theme/theme.dart';

/// Editor for a holdback release. `releaseId == 'new'` creates a fresh draft
/// pre-loaded with every outstanding retainage line for the project; the user
/// can drop lines they don't want released and tweak the released amount per
/// line.
class HoldbackReleaseEditorScreen extends StatefulWidget {
  final String projectId;
  final String releaseId; // 'new' for create

  const HoldbackReleaseEditorScreen({
    super.key,
    required this.projectId,
    required this.releaseId,
  });

  @override
  State<HoldbackReleaseEditorScreen> createState() =>
      _HoldbackReleaseEditorScreenState();
}

class _HoldbackReleaseEditorScreenState
    extends State<HoldbackReleaseEditorScreen> {
  final _svc = HoldbackService();
  final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

  bool _loading = true;
  bool _saving = false;
  String? _error;

  Project? _project;
  HoldbackRelease? _release;
  final List<_LineDraft> _drafts = [];
  late TextEditingController _notesCtl;
  DateTime _releaseDate = DateTime.now();

  bool get _isNew => widget.releaseId == 'new';
  bool get _isDraft =>
      _release == null || _release!.status == HoldbackReleaseStatus.draft;

  @override
  void initState() {
    super.initState();
    _notesCtl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
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
      _project = project;

      if (_isNew) {
        final summary = await _svc.getProjectSummary(widget.projectId);
        final nextNum = await _svc.getNextReleaseNumber(widget.projectId);
        final release = HoldbackRelease(
          id: '',
          workspaceId: project.workspaceId,
          projectId: widget.projectId,
          releaseNumber: nextNum,
          releaseDate: DateTime.now(),
          status: HoldbackReleaseStatus.draft,
          totalAmount: 0,
          notes: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          lines: [],
        );
        _drafts.addAll(summary.outstandingInvoices.map(
          (o) => _LineDraft.fromOutstanding(o, project.workspaceId),
        ));
        _release = release;
        _releaseDate = release.releaseDate;
      } else {
        final loaded = await _svc.getById(widget.releaseId);
        if (loaded == null) {
          setState(() {
            _loading = false;
            _error = 'Holdback release not found.';
          });
          return;
        }
        _release = loaded;
        _releaseDate = loaded.releaseDate;
        _notesCtl.text = loaded.notes ?? '';
        _drafts.addAll(loaded.lines.map(_LineDraft.fromLine));
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  double get _total => _drafts.fold<double>(
      0, (sum, d) => sum + (d.includeInRelease ? d.amountReleased : 0));

  HoldbackRelease _buildHeader({HoldbackReleaseStatus? status}) {
    final lines = <HoldbackReleaseLine>[];
    int sort = 0;
    for (final d in _drafts) {
      if (!d.includeInRelease) continue;
      lines.add(HoldbackReleaseLine(
        id: d.existingId,
        workspaceId: d.workspaceId,
        sourceInvoiceId: d.sourceInvoiceId,
        sourceBudgetItemId: d.sourceBudgetItemId,
        description: d.descriptionCtl.text,
        amountHeld: d.amountHeld,
        amountReleased: d.amountReleased,
        sortOrder: sort++,
      ));
    }
    return (_release ??
            HoldbackRelease(
              id: '',
              workspaceId: _project!.workspaceId,
              projectId: widget.projectId,
              releaseNumber: 1,
              releaseDate: _releaseDate,
              status: HoldbackReleaseStatus.draft,
              totalAmount: 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ))
        .copyWith(
      releaseDate: _releaseDate,
      status: status ?? _release?.status ?? HoldbackReleaseStatus.draft,
      totalAmount: _total,
      notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
      lines: lines,
    );
  }

  Future<void> _save() async {
    if (!_isDraft) return;
    final header = _buildHeader();
    if (header.lines.isEmpty) {
      _toast('Select at least one line to release.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isNew || _release!.id.isEmpty) {
        final id = await _svc.create(header);
        if (!mounted) return;
        context.go(
            '/projects/${widget.projectId}/holdback-releases/$id');
      } else {
        await _svc.update(header);
        if (!mounted) return;
        setState(() {
          _saving = false;
          _release = header;
        });
        _toast('Saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Save failed: $e');
      }
    }
  }

  Future<void> _issue() async {
    if (_release == null || _release!.id.isEmpty || !_isDraft) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue release?'),
        content: Text(
            'This will mark the holdback as released on all included invoices. Total: ${_money.format(_total)}.\n\nThis cannot be undone from the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Issue')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      // Persist any pending edits first.
      await _svc.update(_buildHeader());
      await _svc.issue(_release!.id);
      final updated = await _svc.getById(_release!.id);
      if (mounted) {
        setState(() {
          _release = updated;
          _saving = false;
        });
        _toast('Release issued.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Issue failed: $e');
      }
    }
  }

  Future<void> _markPaid() async {
    if (_release == null || _release!.status != HoldbackReleaseStatus.issued) {
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.markPaid(_release!.id);
      final updated = await _svc.getById(_release!.id);
      if (mounted) {
        setState(() {
          _release = updated;
          _saving = false;
        });
        _toast('Marked paid.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Failed: $e');
      }
    }
  }

  Future<void> _printPdf() async {
    final header = _buildHeader();
    final bytes = await HoldbackPdfService.buildRelease(
      projectName: _project?.name ?? 'Project',
      customerName: _project?.customerName,
      release: header,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: SelectableText(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Holdback Release')),
        body: Center(child: SelectableText(_error!)),
      );
    }
    final release = _release!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew
            ? 'New Holdback Release'
            : 'Release #${release.releaseNumber}'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Print PDF',
              onPressed: _printPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (_isDraft)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.sm),
              child: OutlinedButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ),
          if (_isDraft && !_isNew)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.sm),
              child: FilledButton(
                onPressed: _saving ? null : _issue,
                child: const Text('Issue'),
              ),
            ),
          if (release.status == HoldbackReleaseStatus.issued)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.sm),
              child: FilledButton(
                onPressed: _saving ? null : _markPaid,
                child: const Text('Mark Paid'),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _headerCard(release),
          const SizedBox(height: 16),
          _linesCard(),
          const SizedBox(height: 16),
          _notesCard(),
        ],
      ),
    );
  }

  Widget _headerCard(HoldbackRelease release) {
    final df = DateFormat.yMMMd();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _kv('Status', release.status.displayLabel),
            _kv('Release #', '${release.releaseNumber}'),
            _kv('Project', _project?.name ?? '—'),
            InkWell(
              onTap: _isDraft
                  ? () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _releaseDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _releaseDate = picked);
                      }
                    }
                  : null,
              child: _kv('Release date', df.format(_releaseDate)),
            ),
            _kv('Total releasing', _money.format(_total)),
          ],
        ),
      ),
    );
  }

  Widget _linesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: const [
                Text('Lines',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (_drafts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'No outstanding retainage to release. Issue invoices with holdback first.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._drafts.map((d) => _lineRow(d)),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(_LineDraft d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: d.includeInRelease,
            onChanged: !_isDraft
                ? null
                : (v) => setState(() => d.includeInRelease = v ?? true),
          ),
          Expanded(
            flex: 4,
            child: TextField(
              controller: d.descriptionCtl,
              enabled: _isDraft,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Description',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              enabled: false,
              controller: TextEditingController(
                  text: _money.format(d.amountHeld)),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Held',
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: d.releasedCtl,
              enabled: _isDraft,
              keyboardType: NumericInput.keyboard,
              inputFormatters: NumericInput.currency,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Released',
                prefixText: r'$',
              ),
              textAlign: TextAlign.right,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: TextField(
          controller: _notesCtl,
          enabled: _isDraft,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notes',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(v,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}

class _LineDraft {
  final String? existingId;
  final String workspaceId;
  final String? sourceInvoiceId;
  final String? sourceBudgetItemId;
  final double amountHeld;
  bool includeInRelease;
  final TextEditingController descriptionCtl;
  final TextEditingController releasedCtl;

  _LineDraft({
    this.existingId,
    required this.workspaceId,
    this.sourceInvoiceId,
    this.sourceBudgetItemId,
    required this.amountHeld,
    required this.includeInRelease,
    required String description,
    required double released,
  })  : descriptionCtl = TextEditingController(text: description),
        releasedCtl = TextEditingController(text: released.toStringAsFixed(2));

  factory _LineDraft.fromOutstanding(
      OutstandingRetainage o, String workspaceId) {
    final df = DateFormat.yMd();
    final desc = [
      if (o.documentNumber != null) 'Invoice ${o.documentNumber}',
      df.format(o.createdAt),
    ].join(' · ');
    return _LineDraft(
      workspaceId: workspaceId,
      sourceInvoiceId: o.invoiceId,
      amountHeld: o.retainageAmount,
      includeInRelease: true,
      description: desc,
      released: o.retainageAmount,
    );
  }

  factory _LineDraft.fromLine(HoldbackReleaseLine l) {
    return _LineDraft(
      existingId: l.id,
      workspaceId: l.workspaceId,
      sourceInvoiceId: l.sourceInvoiceId,
      sourceBudgetItemId: l.sourceBudgetItemId,
      amountHeld: l.amountHeld,
      includeInRelease: true,
      description: l.description,
      released: l.amountReleased,
    );
  }

  double get amountReleased =>
      double.tryParse(releasedCtl.text.trim()) ?? 0;

  void dispose() {
    descriptionCtl.dispose();
    releasedCtl.dispose();
  }
}
