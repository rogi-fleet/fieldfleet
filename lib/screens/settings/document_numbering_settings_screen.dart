import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/document_numbering_config.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase/document_numbering_config_service.dart';
import '../../services/supabase/financial_document_number_service.dart';
import '../../theme/theme.dart';
import '../../widgets/forms/stacked_field.dart';

class DocumentNumberingSettingsScreen extends StatefulWidget {
  const DocumentNumberingSettingsScreen({super.key});

  @override
  State<DocumentNumberingSettingsScreen> createState() =>
      _DocumentNumberingSettingsScreenState();
}

class _DocumentNumberingSettingsScreenState
    extends State<DocumentNumberingSettingsScreen> {
  final _configService = SupabaseDocumentNumberingConfigService();

  bool _isLoading = true;
  Map<String, DocumentNumberingConfig> _configs = {};
  Map<String, int> _counters = {};

  String? get _workspaceId =>
      Provider.of<AuthProvider>(context, listen: false)
          .appUser
          ?.currentWorkspaceId;

  String? _loadedWorkspaceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Trigger the load once appUser/workspace has hydrated. The old
    // postFrame-in-initState approach ran exactly once; on a cold load/refresh
    // appUser is briefly null, so _load() returned early without clearing
    // _isLoading and the screen spun forever with no retry. listen: true here
    // re-fires this when appUser arrives.
    final wid = Provider.of<AuthProvider>(context).appUser?.currentWorkspaceId;
    if (wid != null && wid != _loadedWorkspaceId) {
      _loadedWorkspaceId = wid;
      _load();
    }
  }

  Future<void> _load() async {
    final wid = _workspaceId;
    if (wid == null) return;

    setState(() => _isLoading = true);
    try {
      final configs = await _configService.getConfigs(wid);
      final counters = await _configService.getAllCounters(wid);
      setState(() {
        _configs = {for (final c in configs) c.documentType: c};
        _counters = counters;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Document Numbering')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final types = SupabaseFinancialDocumentNumberService.defaultPrefixes.keys
        .toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Customize the prefix, format, and starting number for each document type. '
            'Changes apply to new documents only.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        ...types.map((type) => _buildTypeCard(type)),
      ],
    );
  }

  Widget _buildTypeCard(String documentType) {
    final labels = SupabaseFinancialDocumentNumberService.documentTypeLabels;
    final defaults = SupabaseFinancialDocumentNumberService.defaultPrefixes;
    final label = labels[documentType] ?? documentType;
    final config = _configs[documentType];
    final counter = _counters[documentType] ?? 0;

    final prefix = config?.prefix ?? defaults[documentType]!;
    final separator = config?.separator ?? '-';
    final padding = config?.paddingWidth ?? 3;
    final nextNumber = counter + 1;
    final preview =
        '$prefix$separator${nextNumber.toString().padLeft(padding, '0')}';
    final isCustom = config != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            if (isCustom)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  'Custom',
                  style: TextStyle(fontSize: 10, color: AppColors.info),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'Next: $preview',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontFamily: 'monospace',
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showEditDialog(documentType),
      ),
    );
  }

  Future<void> _showEditDialog(String documentType) async {
    final labels = SupabaseFinancialDocumentNumberService.documentTypeLabels;
    final defaults = SupabaseFinancialDocumentNumberService.defaultPrefixes;
    final label = labels[documentType] ?? documentType;
    final defaultPrefix = defaults[documentType]!;
    final config = _configs[documentType];
    final counter = _counters[documentType] ?? 0;

    final prefixCtrl =
        TextEditingController(text: config?.prefix ?? defaultPrefix);
    final nextNumberCtrl =
        TextEditingController(text: '${counter + 1}');
    var selectedPadding = config?.paddingWidth ?? 3;
    var selectedSeparator = config?.separator ?? '-';
    var saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String preview() {
            final p = prefixCtrl.text.isNotEmpty ? prefixCtrl.text : defaultPrefix;
            final num = int.tryParse(nextNumberCtrl.text) ?? 1;
            return '$p$selectedSeparator${num.toString().padLeft(selectedPadding, '0')}';
          }

          return AlertDialog(
            title: Text('$label Numbering'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preview
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Preview',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preview(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Prefix
                  StackedField(
                    label: 'Prefix',
                    child: TextField(
                      controller: prefixCtrl,
                      decoration: InputDecoration(
                        hintText: defaultPrefix,
                        border: const OutlineInputBorder(),
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(10),
                      ],
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Separator + Padding in a row
                  Row(
                    children: [
                      Expanded(
                        child: StackedField(
                          label: 'Separator',
                          child: DropdownButtonFormField<String>(
                            borderRadius: AppRadius.cardRadius,
                            initialValue: selectedSeparator,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md, vertical: AppSpacing.md),
                            ),
                            items: const [
                              DropdownMenuItem(value: '-', child: Text('Dash ( - )')),
                              DropdownMenuItem(value: '/', child: Text('Slash ( / )')),
                              DropdownMenuItem(value: '.', child: Text('Dot ( . )')),
                              DropdownMenuItem(value: ' ', child: Text('Space')),
                              DropdownMenuItem(value: '', child: Text('None')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedSeparator = v);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StackedField(
                          label: 'Min Digits',
                          child: DropdownButtonFormField<int>(
                            borderRadius: AppRadius.cardRadius,
                            initialValue: selectedPadding,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md, vertical: AppSpacing.md),
                            ),
                            items: [
                              for (int i = 1; i <= 8; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text('$i (${1.toString().padLeft(i, '0')})'),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedPadding = v);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Next number
                  StackedField(
                    label: 'Next Number',
                    child: TextField(
                      controller: nextNumberCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '1',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ),
                  if (counter > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Current counter is at $counter. Setting this lower may cause duplicate numbers.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              // Reset to default
              if (config != null)
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            await _configService.deleteConfig(
                              workspaceId: _workspaceId!,
                              documentType: documentType,
                            );
                            if (context.mounted) Navigator.pop(context, true);
                          } catch (e) {
                            setDialogState(() => saving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                  child: const Text('Reset to Default'),
                ),
              const Spacer(),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final prefix = prefixCtrl.text.trim();
                        if (prefix.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Prefix cannot be empty')),
                          );
                          return;
                        }
                        final nextNum =
                            int.tryParse(nextNumberCtrl.text) ?? 1;
                        if (nextNum < 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Next number must be at least 1')),
                          );
                          return;
                        }

                        setDialogState(() => saving = true);
                        try {
                          final wid = _workspaceId!;
                          // Check if anything differs from defaults
                          final isCustomFormat = prefix != defaultPrefix ||
                              selectedPadding != 3 ||
                              selectedSeparator != '-';

                          if (isCustomFormat) {
                            await _configService.upsertConfig(
                              workspaceId: wid,
                              documentType: documentType,
                              prefix: prefix,
                              paddingWidth: selectedPadding,
                              separator: selectedSeparator,
                            );
                          } else if (config != null) {
                            // Reverted back to defaults — remove custom config
                            await _configService.deleteConfig(
                              workspaceId: wid,
                              documentType: documentType,
                            );
                          }

                          // Set counter if changed (counter stores last used,
                          // so "next = N" means counter = N - 1)
                          final desiredCounter = nextNum - 1;
                          if (desiredCounter != counter) {
                            await _configService.setCounter(
                              workspaceId: wid,
                              documentType: documentType,
                              value: desiredCounter,
                            );
                          }

                          if (context.mounted) Navigator.pop(context, true);
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      _load();
    }
  }
}
