/// Spec book detail: sections tree + items + lifecycle actions.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/spec_book.dart';
import '../../../models/spec_section.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/user_facing_error.dart';

class SpecBookDetailScreen extends StatefulWidget {
  final String bookId;
  const SpecBookDetailScreen({super.key, required this.bookId});

  @override
  State<SpecBookDetailScreen> createState() => _SpecBookDetailScreenState();
}

class _SpecBookDetailScreenState extends State<SpecBookDetailScreen> {
  SpecBook? _book;
  List<SpecSection> _sections = [];
  List<SpecItem> _items = [];
  List<SpecSignoff> _signoffs = [];
  bool _loading = true;
  String? _error;
  String? _selectedSectionId;
  final _dateFmt = DateFormat.yMMMd();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ServiceLocator.specificationService;
      final book = await svc.getBook(widget.bookId);
      if (book == null) throw Exception('Spec book not found');
      final sections = await svc.listSections(book.id);
      final items = await svc.listItems(book.id);
      final signoffs = await svc.listSignoffs(book.id);
      if (!mounted) return;
      setState(() {
        _book = book;
        _sections = sections;
        _items = items;
        _signoffs = signoffs;
        _selectedSectionId ??=
            sections.isNotEmpty ? sections.first.id : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.uiMessage(e, action: 'load spec book');
        _loading = false;
      });
    }
  }

  bool get _locked => _book?.status.isLocked ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_book == null
            ? 'Spec book'
            : '${_book!.title} • v${_book!.version}'),
        actions: _book == null ? null : _buildActions(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildBody(),
    );
  }

  List<Widget> _buildActions() {
    final book = _book!;
    final actions = <Widget>[];
    if (book.status == SpecBookStatus.draft) {
      actions.add(TextButton.icon(
        onPressed: _issueBook,
        icon: const Icon(Icons.outbox_outlined),
        label: const Text('Issue'),
      ));
    }
    if (book.status == SpecBookStatus.draft ||
        book.status == SpecBookStatus.issued) {
      actions.add(FilledButton.icon(
        onPressed: _signOff,
        icon: const Icon(Icons.draw_outlined),
        label: const Text('Sign off'),
      ));
    }
    if (book.status == SpecBookStatus.issued ||
        book.status == SpecBookStatus.signed) {
      actions.add(TextButton.icon(
        onPressed: _newVersion,
        icon: const Icon(Icons.history_edu),
        label: const Text('New version'),
      ));
    }
    actions.add(const SizedBox(width: 8));
    return actions;
  }

  Widget _buildBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _buildSectionTree()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildSectionDetail()),
      ],
    );
  }

  // ---------------- Section tree ----------------

  Widget _buildSectionTree() {
    final roots = _sections.where((s) => s.parentId == null).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Expanded(
                child: Text('Sections',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (!_locked)
                IconButton(
                  tooltip: 'Add section',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addSection(parent: null),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_signoffs.isNotEmpty) ...[
          _buildSignoffStrip(),
          const Divider(height: 1),
        ],
        Expanded(
          child: roots.isEmpty
              ? const Center(
                  child: Text('No sections yet',
                      style: TextStyle(color: Colors.black54)))
              : ListView(
                  children: [
                    for (final r in roots) ..._buildTreeNode(r, 0),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSignoffStrip() {
    final s = _signoffs.first;
    return Container(
      color: Colors.green.shade50,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.verified_outlined,
              size: 18, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Signed by ${s.signerName} on ${_dateFmt.format(s.signedAt)} (v${s.versionAtSign})',
              style:
                  TextStyle(fontSize: 12, color: Colors.green.shade900),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTreeNode(SpecSection s, int depth) {
    final children = _sections.where((x) => x.parentId == s.id).toList();
    final selected = _selectedSectionId == s.id;
    final w = <Widget>[
      InkWell(
        onTap: () => setState(() => _selectedSectionId = s.id),
        child: Container(
          color: selected ? Colors.blue.shade50 : null,
          padding: EdgeInsets.only(
              left: 12.0 + depth * 16, right: 8, top: 8, bottom: 8),
          child: Row(
            children: [
              if (s.code != null && s.code!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(s.code!,
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.black54)),
                ),
              Expanded(
                child: Text(s.title,
                    style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500)),
              ),
              if (!_locked)
                PopupMenuButton<String>(
                  iconSize: 16,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'sub', child: Text('Add subsection')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  onSelected: (v) {
                    switch (v) {
                      case 'sub':
                        _addSection(parent: s);
                      case 'edit':
                        _editSection(s);
                      case 'delete':
                        _deleteSection(s);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    ];
    for (final c in children) {
      w.addAll(_buildTreeNode(c, depth + 1));
    }
    return w;
  }

  // ---------------- Section detail (items) ----------------

  Widget _buildSectionDetail() {
    final id = _selectedSectionId;
    if (id == null) {
      return const Center(
          child: Text('Select a section to view its items',
              style: TextStyle(color: Colors.black54)));
    }
    final section = _sections.firstWhere((s) => s.id == id,
        orElse: () => _sections.first);
    final items =
        _items.where((i) => i.sectionId == id).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${section.code != null && section.code!.isNotEmpty ? "${section.code}  " : ""}${section.title}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!_locked)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                      onPressed: () => _addItem(section),
                    ),
                ],
              ),
              if (section.body?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(section.body!,
                    style: const TextStyle(color: Colors.black87)),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('No items in this section',
                      style: TextStyle(color: Colors.black54)))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _itemRow(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _itemRow(SpecItem item) {
    final subtitle = [
      if (item.manufacturer?.isNotEmpty == true) item.manufacturer!,
      if (item.model?.isNotEmpty == true) item.model!,
      if (item.qty != null) '${item.qty}${item.unit != null ? " ${item.unit}" : ""}',
    ].join(' • ');
    return ListTile(
      dense: true,
      leading: item.itemNo == null || item.itemNo!.isEmpty
          ? const Icon(Icons.circle, size: 6, color: Colors.black38)
          : SizedBox(
              width: 36,
              child: Text(item.itemNo!,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.black54)),
            ),
      title: Text(item.description),
      subtitle: subtitle.isEmpty
          ? (item.notes?.isNotEmpty == true ? Text(item.notes!) : null)
          : Text(subtitle),
      trailing: _locked
          ? null
          : PopupMenuButton<String>(
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _editItem(item);
                  case 'delete':
                    _deleteItem(item);
                }
              },
            ),
    );
  }

  // ---------------- Section actions ----------------

  Future<void> _addSection({SpecSection? parent}) async {
    final res = await showDialog<_SectionFormResult>(
      context: context,
      builder: (_) => const _SectionFormDialog(),
    );
    if (res == null) return;
    try {
      final sortOrder = _sections
              .where((s) => s.parentId == parent?.id)
              .fold<int>(0, (m, s) => s.sortOrder > m ? s.sortOrder : m) +
          10;
      await ServiceLocator.specificationService.createSection(
        bookId: _book!.id,
        parentId: parent?.id,
        code: res.code,
        title: res.title,
        body: res.body,
        sortOrder: sortOrder,
      );
      await _load();
    } catch (e) {
      _showError(e, 'add section');
    }
  }

  Future<void> _editSection(SpecSection s) async {
    final res = await showDialog<_SectionFormResult>(
      context: context,
      builder: (_) => _SectionFormDialog(initial: s),
    );
    if (res == null) return;
    try {
      await ServiceLocator.specificationService.updateSection(s.id, {
        'code': res.code,
        'title': res.title,
        'body': res.body,
      });
      await _load();
    } catch (e) {
      _showError(e, 'update section');
    }
  }

  Future<void> _deleteSection(SpecSection s) async {
    final ok = await _confirm('Delete section "${s.title}" and everything '
        'beneath it?');
    if (!ok) return;
    try {
      await ServiceLocator.specificationService.deleteSection(s.id);
      if (_selectedSectionId == s.id) _selectedSectionId = null;
      await _load();
    } catch (e) {
      _showError(e, 'delete section');
    }
  }

  // ---------------- Item actions ----------------

  Future<void> _addItem(SpecSection section) async {
    final res = await showDialog<_ItemFormResult>(
      context: context,
      builder: (_) => const _ItemFormDialog(),
    );
    if (res == null) return;
    try {
      final sortOrder = _items
              .where((i) => i.sectionId == section.id)
              .fold<int>(0, (m, i) => i.sortOrder > m ? i.sortOrder : m) +
          10;
      await ServiceLocator.specificationService.createItem(
        bookId: _book!.id,
        sectionId: section.id,
        itemNo: res.itemNo,
        description: res.description,
        manufacturer: res.manufacturer,
        model: res.model,
        qty: res.qty,
        unit: res.unit,
        notes: res.notes,
        sortOrder: sortOrder,
      );
      await _load();
    } catch (e) {
      _showError(e, 'add item');
    }
  }

  Future<void> _editItem(SpecItem item) async {
    final res = await showDialog<_ItemFormResult>(
      context: context,
      builder: (_) => _ItemFormDialog(initial: item),
    );
    if (res == null) return;
    try {
      await ServiceLocator.specificationService.updateItem(item.id, {
        'item_no': res.itemNo,
        'description': res.description,
        'manufacturer': res.manufacturer,
        'model': res.model,
        'qty': res.qty,
        'unit': res.unit,
        'notes': res.notes,
      });
      await _load();
    } catch (e) {
      _showError(e, 'update item');
    }
  }

  Future<void> _deleteItem(SpecItem item) async {
    final ok = await _confirm('Delete this item?');
    if (!ok) return;
    try {
      await ServiceLocator.specificationService.deleteItem(item.id);
      await _load();
    } catch (e) {
      _showError(e, 'delete item');
    }
  }

  // ---------------- Lifecycle actions ----------------

  Future<void> _issueBook() async {
    final ok = await _confirm('Issue this spec book for client review?');
    if (!ok) return;
    try {
      await ServiceLocator.specificationService.issueBook(_book!.id);
      await _load();
    } catch (e) {
      _showError(e, 'issue book');
    }
  }

  Future<void> _signOff() async {
    final res = await showDialog<_SignoffResult>(
      context: context,
      builder: (_) => const _SignoffDialog(),
    );
    if (res == null) return;
    try {
      await ServiceLocator.specificationService.signOff(
        bookId: _book!.id,
        signerName: res.name,
        signerEmail: res.email,
        signerRole: res.role,
        signatureText: res.signatureText,
        notes: res.notes,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spec book signed and locked.')),
      );
    } catch (e) {
      _showError(e, 'record sign-off');
    }
  }

  Future<void> _newVersion() async {
    final ok = await _confirm(
        'Create a new draft from this version? The current version will be '
        'marked superseded.');
    if (!ok) return;
    try {
      final newId =
          await ServiceLocator.specificationService.newVersion(_book!.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SpecBookDetailScreen(bookId: newId),
      ));
    } catch (e) {
      _showError(e, 'create new version');
    }
  }

  // ---------------- helpers ----------------

  Future<bool> _confirm(String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    return r ?? false;
  }

  void _showError(Object e, String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(UserFacingError.uiMessage(e, action: action))));
  }
}

// ---------------- Section form ----------------

class _SectionFormResult {
  final String? code;
  final String title;
  final String? body;
  _SectionFormResult({this.code, required this.title, this.body});
}

class _SectionFormDialog extends StatefulWidget {
  final SpecSection? initial;
  const _SectionFormDialog({this.initial});
  @override
  State<_SectionFormDialog> createState() => _SectionFormDialogState();
}

class _SectionFormDialogState extends State<_SectionFormDialog> {
  late final _code = TextEditingController(text: widget.initial?.code ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _body = TextEditingController(text: widget.initial?.body ?? '');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New section' : 'Edit section'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _code,
                    decoration: const InputDecoration(
                        labelText: 'Code', hintText: '09 91 23'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: 'Body', alignLabelWithHint: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(
                context,
                _SectionFormResult(
                  code: _code.text.trim().isEmpty ? null : _code.text.trim(),
                  title: _title.text.trim(),
                  body: _body.text.trim().isEmpty ? null : _body.text.trim(),
                ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------- Item form ----------------

class _ItemFormResult {
  final String? itemNo;
  final String description;
  final String? manufacturer;
  final String? model;
  final num? qty;
  final String? unit;
  final String? notes;
  _ItemFormResult({
    this.itemNo,
    required this.description,
    this.manufacturer,
    this.model,
    this.qty,
    this.unit,
    this.notes,
  });
}

class _ItemFormDialog extends StatefulWidget {
  final SpecItem? initial;
  const _ItemFormDialog({this.initial});
  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  late final _itemNo =
      TextEditingController(text: widget.initial?.itemNo ?? '');
  late final _desc =
      TextEditingController(text: widget.initial?.description ?? '');
  late final _mfg =
      TextEditingController(text: widget.initial?.manufacturer ?? '');
  late final _model =
      TextEditingController(text: widget.initial?.model ?? '');
  late final _qty =
      TextEditingController(text: widget.initial?.qty?.toString() ?? '');
  late final _unit = TextEditingController(text: widget.initial?.unit ?? '');
  late final _notes =
      TextEditingController(text: widget.initial?.notes ?? '');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New item' : 'Edit item'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _itemNo,
                    decoration: const InputDecoration(labelText: 'No.'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _desc,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Description'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mfg,
                    decoration:
                        const InputDecoration(labelText: 'Manufacturer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: 'Model'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _qty,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qty'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_desc.text.trim().isEmpty) return;
            Navigator.pop(
                context,
                _ItemFormResult(
                  itemNo:
                      _itemNo.text.trim().isEmpty ? null : _itemNo.text.trim(),
                  description: _desc.text.trim(),
                  manufacturer:
                      _mfg.text.trim().isEmpty ? null : _mfg.text.trim(),
                  model:
                      _model.text.trim().isEmpty ? null : _model.text.trim(),
                  qty: num.tryParse(_qty.text.trim()),
                  unit:
                      _unit.text.trim().isEmpty ? null : _unit.text.trim(),
                  notes:
                      _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------- Sign-off dialog ----------------

class _SignoffResult {
  final String name;
  final String? email;
  final String? role;
  final String? signatureText;
  final String? notes;
  _SignoffResult({
    required this.name,
    this.email,
    this.role,
    this.signatureText,
    this.notes,
  });
}

class _SignoffDialog extends StatefulWidget {
  const _SignoffDialog();
  @override
  State<_SignoffDialog> createState() => _SignoffDialogState();
}

class _SignoffDialogState extends State<_SignoffDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _role = TextEditingController();
  final _sig = TextEditingController();
  final _notes = TextEditingController();
  bool _agree = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Client sign-off'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Recording sign-off will lock this version. Any future '
                'changes will require a new version.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
                controller: _name,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'Signer name *')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                    controller: _role,
                    decoration: const InputDecoration(
                        labelText: 'Role / Title')),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
                controller: _sig,
                decoration: const InputDecoration(
                    labelText: 'Typed signature (e.g. "/Jane Doe/")')),
            const SizedBox(height: 8),
            TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes')),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              title: const Text(
                  'I confirm the client has approved this spec book.',
                  style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: (!_agree || _name.text.trim().isEmpty)
              ? null
              : () {
                  Navigator.pop(
                      context,
                      _SignoffResult(
                        name: _name.text.trim(),
                        email: _email.text.trim().isEmpty
                            ? null
                            : _email.text.trim(),
                        role: _role.text.trim().isEmpty
                            ? null
                            : _role.text.trim(),
                        signatureText: _sig.text.trim().isEmpty
                            ? null
                            : _sig.text.trim(),
                        notes: _notes.text.trim().isEmpty
                            ? null
                            : _notes.text.trim(),
                      ));
                },
          child: const Text('Record sign-off'),
        ),
      ],
    );
  }
}
