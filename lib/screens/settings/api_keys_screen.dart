import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/supabase_config.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase/api_key_service.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';

/// Admin management of workspace API keys for the MCP server / public API.
/// Keys connect external AI assistants (Claude, ChatGPT, any MCP client) to
/// this workspace.
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  final _service = ApiKeyService();
  static final _dateFormat = DateFormat('MMM d, yyyy');

  List<WorkspaceApiKey> _keys = const [];
  bool _loading = true;
  String? _error;

  String? get _workspaceId =>
      context.read<AuthProvider>().appUser?.currentWorkspaceId;

  String get _mcpEndpoint => '${SupabaseConfig.url}/functions/v1/mcp-server';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final workspaceId = _workspaceId;
    if (workspaceId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final keys = await _service.listKeys(workspaceId);
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = UserFacingError.uiMessage(e, action: 'load API keys');
      });
    }
  }

  Future<void> _createKey() async {
    final workspaceId = _workspaceId;
    if (workspaceId == null) return;

    final nameController = TextEditingController();
    var allowWrite = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Claude connector',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow writes'),
                subtitle: const Text(
                  'Off = read-only (reports, lists). On also allows '
                  'creating tasks.',
                ),
                value: allowWrite,
                onChanged: (v) => setDialogState(() => allowWrite = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    try {
      final key = await _service.createKey(
        workspaceId: workspaceId,
        name: name,
        scopes: allowWrite ? const ['read', 'write'] : const ['read'],
      );
      if (!mounted) return;
      await _showKeyOnce(key);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(UserFacingError.uiMessage(e, action: 'create the API key')),
        ),
      );
    }
  }

  Future<void> _showKeyOnce(String key) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('API Key Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copy this key now — it will not be shown again.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _copyableBox(ctx, key),
            const SizedBox(height: 16),
            const Text('MCP endpoint for your AI assistant:'),
            const SizedBox(height: 6),
            _copyableBox(ctx, _mcpEndpoint),
            const SizedBox(height: 10),
            Text(
              'In Claude (or any MCP client), add a custom connector with '
              'this URL and the key as the Bearer token.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _copyableBox(BuildContext ctx, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.secondarySurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(WorkspaceApiKey key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke "${key.name}"?'),
        content: const Text(
          'Any AI assistant or integration using this key will immediately '
          'lose access. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.revokeKey(key.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(UserFacingError.uiMessage(e, action: 'revoke the key')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().canManageUsers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Keys'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _createKey,
              icon: const Icon(Icons.add),
              label: const Text('New Key'),
            )
          : null,
      body: !isAdmin
          ? const Center(
              child: Text('Only workspace admins can manage API keys.'),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    children: [
                      Card(
                        color: AppColors.infoLight,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.base),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Connect AI assistants to this workspace',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'API keys let MCP-capable assistants '
                                '(Claude, ChatGPT, …) read your jobs, WIP '
                                'schedule, cash flow, and catalog — and '
                                'create tasks when given write access.',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 10),
                              _copyableBox(context, _mcpEndpoint),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                      if (_keys.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(AppSpacing.xl),
                            child: Center(
                              child: Text(
                                'No API keys yet. Create one to connect an '
                                'AI assistant.',
                              ),
                            ),
                          ),
                        )
                      else
                        ..._keys.map(_keyTile),
                    ],
                  ),
                ),
    );
  }

  Widget _keyTile(WorkspaceApiKey key) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          key.isRevoked ? Icons.key_off : Icons.key,
          color: key.isRevoked ? AppColors.textTertiary : AppColors.info,
        ),
        title: Row(
          children: [
            Flexible(child: Text(key.name)),
            const SizedBox(width: 8),
            if (key.isRevoked)
              _chip('Revoked', AppColors.error)
            else if (key.scopes.contains('write'))
              _chip('Read + Write', AppColors.warning)
            else
              _chip('Read-only', AppColors.success),
          ],
        ),
        subtitle: Text(
          '${key.keyPrefix}…  ·  created ${_dateFormat.format(key.createdAt)}'
          '${key.lastUsedAt != null ? '  ·  last used ${_dateFormat.format(key.lastUsedAt!)}' : '  ·  never used'}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: key.isRevoked
            ? null
            : TextButton(
                onPressed: () => _revoke(key),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Revoke'),
              ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
