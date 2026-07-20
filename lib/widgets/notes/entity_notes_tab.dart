import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/project_note.dart';
import '../../models/workspace.dart';
import '../../providers/auth_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Reusable notes tab for projects, customers, and vendors.
class EntityNotesTab extends StatefulWidget {
  final String workspaceId;
  final String entityType;
  final String entityId;

  /// Optional project_id for notes that belong to a project context.
  final String? projectId;

  /// Optional human-readable title for the parent record (e.g. project name)
  /// shown in the PDF export header.
  final String? entityTitle;
  final String? permanentNoteTitle;
  final String? permanentNoteHintText;
  final String? permanentNoteValue;
  final Future<String?> Function(String? value)? onSavePermanentNote;

  const EntityNotesTab({
    super.key,
    required this.workspaceId,
    required this.entityType,
    required this.entityId,
    this.projectId,
    this.entityTitle,
    this.permanentNoteTitle,
    this.permanentNoteHintText,
    this.permanentNoteValue,
    this.onSavePermanentNote,
  });

  @override
  State<EntityNotesTab> createState() => _EntityNotesTabState();
}

class _EntityNotesTabState extends State<EntityNotesTab> {
  final _noteService = ServiceLocator.projectNoteService;
  final _workspaceService = ServiceLocator.workspaceService;
  final _pdfService = PDFService();
  final _contentController = TextEditingController();
  String? _selectedTag;
  String? _filterTag;
  String? _permanentNoteValue;
  bool _submitting = false;
  bool _savingPermanentNote = false;
  bool _exportingPdf = false;
  List<ProjectNote> _latestNotes = const [];

  bool get _hasPermanentNoteSection =>
      widget.permanentNoteTitle != null || widget.onSavePermanentNote != null;

  @override
  void initState() {
    super.initState();
    _permanentNoteValue = _normalizeText(widget.permanentNoteValue);
  }

  @override
  void didUpdateWidget(covariant EntityNotesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.permanentNoteValue != widget.permanentNoteValue) {
      _permanentNoteValue = _normalizeText(widget.permanentNoteValue);
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submitNote() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id ?? '';
    final userName = auth.appUser?.displayName ?? '';

    setState(() => _submitting = true);
    try {
      await _noteService.createNote(
        ProjectNote(
          id: '',
          workspaceId: widget.workspaceId,
          projectId: widget.projectId ?? '',
          entityType: widget.entityType,
          entityId: widget.entityId,
          content: content,
          tag: _selectedTag,
          authorId: userId,
          authorName: userName,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      _contentController.clear();
      setState(() => _selectedTag = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save note: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editNote(ProjectNote note) async {
    final draft = await _showNoteEditor(
      title: 'Edit note',
      initialContent: note.content,
      initialTag: note.tag,
    );
    if (draft == null) return;

    try {
      await _noteService.updateNote(
        noteId: note.id,
        content: draft.content,
        tag: draft.tag,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update note: $e')),
        );
      }
    }
  }

  Future<void> _deleteNote(ProjectNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          note.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _noteService.deleteNote(note.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete note: $e')),
        );
      }
    }
  }

  Future<void> _editPermanentNote() async {
    final callback = widget.onSavePermanentNote;
    if (callback == null) return;

    final result = await _showTextEditor(
      title: widget.permanentNoteTitle ?? 'Overview note',
      hintText:
          widget.permanentNoteHintText ??
          'Add a persistent note for this record.',
      initialValue: _permanentNoteValue,
    );
    if (result == null) return;

    setState(() => _savingPermanentNote = true);
    try {
      final savedValue = await callback(result.value);
      if (!mounted) return;
      setState(() => _permanentNoteValue = _normalizeText(savedValue));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save overview note: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingPermanentNote = false);
    }
  }

  Future<void> _exportToPdf() async {
    final notesToExport = _filterTag == null
        ? _latestNotes
        : _latestNotes.where((n) => n.tag == _filterTag).toList();

    setState(() => _exportingPdf = true);
    try {
      final wsData =
          await _workspaceService.getWorkspace(widget.workspaceId).first;
      if (wsData == null) {
        throw Exception('Workspace not found');
      }
      final workspace = Workspace.fromJson(wsData, widget.workspaceId);

      Uint8List? logoBytes;
      if (workspace.avatarUrl != null && workspace.avatarUrl!.isNotEmpty) {
        logoBytes = await PDFService.fetchImageBytes(workspace.avatarUrl!);
      }

      final pdfBytes = await _pdfService.generateNotesPDF(
        notes: notesToExport,
        workspace: workspace,
        entityType: widget.entityType,
        entityTitle: widget.entityTitle,
        filterTag: _filterTag,
        logoBytes: logoBytes,
      );

      final safeTitle = (widget.entityTitle ?? widget.entityType)
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final datePart = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final filename = '${safeTitle}_notes_$datePart.pdf';
      await _pdfService.sharePDF(pdfBytes, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export notes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<_NoteDraft?> _showNoteEditor({
    required String title,
    required String initialContent,
    String? initialTag,
  }) async {
    final contentController = TextEditingController(text: initialContent);
    String? selectedTag = initialTag;

    final result = await showDialog<_NoteDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: contentController,
                    maxLines: 6,
                    minLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Add a note…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('No tag'),
                        selected: selectedTag == null,
                        onSelected: (_) => setDialogState(() => selectedTag = null),
                      ),
                      ...ProjectNote.availableTags.map((tag) {
                        return ChoiceChip(
                          label: Text(tag),
                          selected: selectedTag == tag,
                          onSelected: (_) =>
                              setDialogState(() => selectedTag = tag),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final content = contentController.text.trim();
                if (content.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _NoteDraft(content: content, tag: selectedTag),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    contentController.dispose();
    return result;
  }

  Future<_TextEditResult?> _showTextEditor({
    required String title,
    required String hintText,
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue ?? '');

    final result = await showDialog<_TextEditResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 8,
            minLines: 4,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hintText,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                _TextEditResult(value: _normalizeText(controller.text)),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  String? _normalizeText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().appUser?.id ?? '';

    // Light content surface — this tab uses light-mode content colors
    // throughout, so without it the empty state and note cards render
    // dark-on-dark when the host screen has the dark chrome background.
    return ColoredBox(
      color: AppColors.background,
      child: Column(
      children: [
        if (_hasPermanentNoteSection) _buildPermanentNoteSection(),
        if (_hasPermanentNoteSection) const Divider(height: 1),
        _buildComposeBox(context),
        const Divider(height: 1),
        _buildFilterBar(),
        Expanded(
          child: StreamBuilder<List<ProjectNote>>(
            stream: _noteService.getNotesByEntity(
              widget.entityType,
              widget.entityId,
              workspaceId: widget.workspaceId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final allNotes = snapshot.data ?? const <ProjectNote>[];
              if (!identical(_latestNotes, allNotes)) {
                _latestNotes = allNotes;
              }
              var notes = allNotes;
              if (_filterTag != null) {
                notes = notes.where((n) => n.tag == _filterTag).toList();
              }
              if (notes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notes_outlined,
                        size: 64,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _filterTag != null
                            ? 'No "$_filterTag" notes'
                            : 'No notes yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add observations, instructions, or updates above.',
                        style: TextStyle(color: AppColors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: notes.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  thickness: 2,
                  color: AppColors.cardBorder,
                ),
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return _NoteCard(
                    note: note,
                    canManage: note.authorId == currentUserId,
                    onEdit: _editNote,
                    onDelete: _deleteNote,
                  );
                },
              );
            },
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildPermanentNoteSection() {
    final title = widget.permanentNoteTitle ?? 'Overview note';
    final hintText =
        widget.permanentNoteHintText ?? 'Add a persistent note for this record.';
    final canEdit = widget.onSavePermanentNote != null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.push_pin_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: _savingPermanentNote ? null : _editPermanentNote,
                    icon: _savingPermanentNote
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_outlined, size: 16),
                    label: Text(_permanentNoteValue == null ? 'Add' : 'Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _permanentNoteValue ??
                  'No overview note yet. Use this for standing context that should stay visible.',
              style: TextStyle(
                fontSize: 14,
                color: _permanentNoteValue == null
                    ? AppColors.textTertiary
                    : AppColors.textPrimary,
                height: 1.45,
              ),
            ),
            if (_permanentNoteValue == null) ...[
              const SizedBox(height: 8),
              Text(
                hintText,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComposeBox(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _contentController,
            maxLines: 8,
            minLines: 2,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: 'Add a note…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: ProjectNote.availableTags.map((tag) {
                    final selected = _selectedTag == tag;
                    return FilterChip(
                      label: Text(tag),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _selectedTag = selected ? null : tag),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submitting ? null : _submitNote,
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final hasFilter = _filterTag != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: Row(
        children: [
          PopupMenuButton<String?>(
            tooltip: 'Filter notes',
            icon: Icon(
              hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: hasFilter
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.textSecondary,
            ),
            onSelected: (tag) => setState(() => _filterTag = tag),
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String?>(
                value: null,
                checked: _filterTag == null,
                child: const Text('All'),
              ),
              ...ProjectNote.availableTags.map((tag) {
                return CheckedPopupMenuItem<String?>(
                  value: tag,
                  checked: _filterTag == tag,
                  child: Text(tag),
                );
              }),
            ],
          ),
          if (hasFilter)
            InputChip(
              label: Text(_filterTag!),
              onDeleted: () => setState(() => _filterTag = null),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Export notes to PDF',
            onPressed: (_exportingPdf || _latestNotes.isEmpty)
                ? null
                : _exportToPdf,
            icon: _exportingPdf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final ProjectNote note;
  final bool canManage;
  final Future<void> Function(ProjectNote) onEdit;
  final Future<void> Function(ProjectNote) onDelete;

  const _NoteCard({
    required this.note,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tagColor = _tagColor(note.tag);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      DateFormat('MMM d, y · h:mm a').format(note.createdAt),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (note.tag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          note.tag!,
                          style: TextStyle(
                            fontSize: 11,
                            color: tagColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<_NoteAction>(
                  tooltip: 'Note actions',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (action) {
                    switch (action) {
                      case _NoteAction.edit:
                        onEdit(note);
                      case _NoteAction.delete:
                        onDelete(note);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _NoteAction.edit,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined, size: 18),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _NoteAction.delete,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline, size: 18),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note.content),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                note.authorName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              if (note.isEdited)
                const Text(
                  'Edited',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _tagColor(String? tag) {
    switch (tag) {
      case 'issue':
        return AppColors.error;
      case 'resolution':
        return AppColors.success;
      case 'instruction':
        return AppColors.warning;
      case 'update':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _NoteDraft {
  final String content;
  final String? tag;

  const _NoteDraft({required this.content, required this.tag});
}

class _TextEditResult {
  final String? value;

  const _TextEditResult({required this.value});
}

enum _NoteAction { edit, delete }
