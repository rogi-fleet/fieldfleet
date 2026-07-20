import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../models/document_template.dart';
import '../../models/document_type.dart';
import '../../services/supabase/document_service.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../utils/document_template_renderer.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class TemplateEditorScreen extends StatefulWidget {
  final String? templateId;

  const TemplateEditorScreen({super.key, this.templateId});

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  final _templateService = ServiceLocator.documentTemplateService;
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();

  DocumentType _selectedType = DocumentType.custom;
  bool _isDefault = false;
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      _loadTemplate();
    } else {
      // Set default content for new template
      _contentController.text = DocumentTemplate.getDefaultTemplate(
        DocumentType.custom,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final template = await _templateService.getTemplate(widget.templateId!);
      if (!mounted) return;

      if (template == null) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That template no longer exists.'),
          ),
        );
        context.go('/documents/templates');
        return;
      }

      setState(() {
        _nameController.text = template.name;
        _contentController.text = template.markdownContent;
        _selectedType = template.type;
        _isDefault = template.isDefault;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading template'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveTemplate() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a template name')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
      final userId = authProvider.appUser?.id ?? '';

      if (widget.templateId != null) {
        await _templateService.updateTemplate(
          templateId: widget.templateId!,
          name: _nameController.text.trim(),
          markdownContent: _contentController.text,
          isDefault: _isDefault,
        );
      } else {
        await _templateService.createTemplate(
          workspaceId: workspaceId,
          name: _nameController.text.trim(),
          type: _selectedType,
          markdownContent: _contentController.text,
          isDefault: _isDefault,
          createdBy: userId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Template saved')));
        context.go('/documents/templates');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving template'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _insertPlaceholder(String placeholder) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '{{$placeholder}}',
    );
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + placeholder.length + 4,
      ),
    );
    setState(() {}); // Update preview
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.templateId != null ? 'Edit Template' : 'Create Template',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/documents/templates'),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveTemplate,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Row(
        children: [
          // Left Panel - Settings & Placeholders
          _buildSettingsPanel(),
          const VerticalDivider(width: 1),
          // Center Panel - Markdown Editor
          Expanded(flex: 3, child: _buildEditorPanel()),
          const VerticalDivider(width: 1),
          // Right Panel - Preview
          Expanded(flex: 3, child: _buildPreviewPanel()),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      width: 280,
      color: AppColors.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Template Settings
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StackedField(
                  label: 'Template Name',
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.templateId == null) ...[
                  StackedField(
                    label: 'Document Type',
                    child: DropdownButtonFormField<DocumentType>(
                      borderRadius: AppRadius.cardRadius,
                      value: _selectedType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      items: DocumentType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (type) {
                        if (type != null) {
                          setState(() {
                            _selectedType = type;
                            // Load default template for this type if content is empty or default
                            if (_contentController.text.isEmpty ||
                                _contentController.text ==
                                    DocumentTemplate.getDefaultTemplate(
                                      _selectedType,
                                    )) {
                              _contentController.text =
                                  DocumentTemplate.getDefaultTemplate(type);
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SwitchListTile(
                  title: const Text(
                    'Set as Default',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'Use this template by default for ${_selectedType.displayName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _isDefault,
                  onChanged: (value) {
                    setState(() {
                      _isDefault = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Placeholders
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Text(
              'PLACEHOLDERS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              children: SupabaseDocumentService.getAvailablePlaceholders().entries.map((
                entry,
              ) {
                return _buildPlaceholderGroup(entry.key, entry.value);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderGroup(String category, List<String> placeholders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            category.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: placeholders.map((placeholder) {
            return ActionChip(
              label: Text(
                '$category.$placeholder',
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () => _insertPlaceholder('$category.$placeholder'),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildEditorPanel() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            children: [
              Text(
                'MARKDOWN EDITOR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.format_bold, size: 20),
                tooltip: 'Bold',
                onPressed: () => _insertMarkdown('**', '**'),
              ),
              IconButton(
                icon: const Icon(Icons.format_italic, size: 20),
                tooltip: 'Italic',
                onPressed: () => _insertMarkdown('*', '*'),
              ),
              IconButton(
                icon: const Icon(Icons.format_list_bulleted, size: 20),
                tooltip: 'List',
                onPressed: () => _insertMarkdown('\n- ', ''),
              ),
              IconButton(
                icon: const Icon(Icons.table_chart, size: 20),
                tooltip: 'Table',
                onPressed: () => _insertTable(),
              ),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            controller: _contentController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(AppSpacing.base),
            ),
            onChanged: (value) {
              setState(() {}); // Update preview
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPanel() {
    // Create sample context data for preview
    final sampleContext = {
      'workspace': {
        'name': 'Sample Company',
        'address': '123 Main Street, City, ST 12345',
        'phone': '(555) 123-4567',
        'email': 'info@samplecompany.com',
      },
      'customer': {
        'name': 'John Doe',
        'email': 'john@example.com',
        'phone': '(555) 987-6543',
        'address': '456 Oak Avenue, Town, ST 67890',
        'company': 'Customer Corp',
      },
      'project': {
        'name': 'Sample Project',
        'description': 'This is a sample project description.',
        'status': 'In Progress',
        'purchaseOrderNumber': 'PO-230930',
      },
      'invoice': {
        'number': 'INV-2024-001',
        'dueDate': '01/15/2024',
        'subtotal': '1,000.00',
        'taxPercent': '8',
        'taxAmount': '80.00',
        'total': '1,080.00',
      },
      'date': {
        'today': DateTime.now().toString().split(' ')[0],
        'day': DateTime.now().day.toString(),
        'month': DateTime.now().month.toString(),
        'year': DateTime.now().year.toString(),
      },
      'user': {
        'name': 'Current User',
        'email': 'user@example.com',
        'phone': '(555) 555-5555',
      },
      'lineItems': [
        {
          'description': 'Item 1',
          'quantity': '2',
          'rate': '100.00',
          'amount': '200.00',
        },
        {
          'description': 'Item 2',
          'quantity': '1',
          'rate': '500.00',
          'amount': '500.00',
        },
        {
          'description': 'Item 3',
          'quantity': '3',
          'rate': '100.00',
          'amount': '300.00',
        },
      ],
    };

    final renderedContent = DocumentTemplateRenderer.render(
      _contentController.text,
      sampleContext,
    );

    return Container(
      color: AppColors.surfaceAlt,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
            ),
            child: Row(
              children: [
                Text(
                  'PREVIEW',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  'Sample data',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: MarkdownBody(data: renderedContent, selectable: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _insertMarkdown(String before, String after) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final selectedText = text.substring(selection.start, selection.end);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$before$selectedText$after',
    );
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset:
            selection.start +
            before.length +
            selectedText.length +
            after.length,
      ),
    );
    setState(() {});
  }

  void _insertTable() {
    const table = '''
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
''';
    final text = _contentController.text;
    final selection = _contentController.selection;
    final newText = text.replaceRange(selection.start, selection.end, table);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + table.length,
      ),
    );
    setState(() {});
  }
}
