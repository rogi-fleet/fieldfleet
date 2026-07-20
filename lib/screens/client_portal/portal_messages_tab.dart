import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';
import '../../widgets/common/list_skeleton.dart';
import 'portal_preview_scope.dart';

/// Messages tab inside the portal project screen. Lazy-loads (or creates)
/// the single portal-visible conversation thread for the project, then shows
/// messages newest-at-bottom with a compose box. Compose is disabled in
/// preview mode.
class PortalMessagesTab extends StatefulWidget {
  final String projectId;
  const PortalMessagesTab({super.key, required this.projectId});

  @override
  State<PortalMessagesTab> createState() => _PortalMessagesTabState();
}

class _PortalMessagesTabState extends State<PortalMessagesTab> {
  // Initial page size + how many older messages to fetch on "Load older".
  static const int _pageSize = 50;

  final dynamic _portalService = ServiceLocator.clientPortalService;
  final TextEditingController _composeCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingOlder = false;
  bool _hasMore = false;
  String? _error;
  String? _conversationId;
  String? _workspaceId;
  // Stored oldest-first so the rendered list matches scroll order.
  List<Map<String, dynamic>> _messages = const [];
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  final List<_PendingAttachment> _pending = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _composeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final preview = PortalPreviewScope.of(context);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    // Cancel any prior subscription before re-loading (e.g. retry).
    await _msgSub?.cancel();
    _msgSub = null;
    try {
      final thread = await _portalService.getOrCreateProjectThread(
        projectId: widget.projectId,
        previewCustomerId: preview,
      );
      final convId = thread['id'] as String;
      final workspaceId = thread['workspace_id'] as String?;
      // RPC returns newest-first within the page; reverse to oldest-first.
      final rpcMsgs = await _portalService.getThreadMessages(
        conversationId: convId,
        previewCustomerId: preview,
        limit: _pageSize,
      );
      final page = List<Map<String, dynamic>>.from(rpcMsgs);
      final ordered = page.reversed.toList();
      if (!mounted) return;
      setState(() {
        _conversationId = convId;
        _workspaceId = workspaceId;
        _messages = ordered;
        _hasMore = page.length == _pageSize;
        _isLoading = false;
      });
      if (preview == null) {
        await _portalService.markThreadRead(convId);
        // Subscribe to inserts. Preview impersonators don't pass the portal
        // RLS policy, so we keep them on the one-shot RPC view.
        _msgSub = _portalService
            .watchThreadInserts(conversationId: convId)
            .listen(_onInsert, onError: (Object e, StackTrace st) {
          AppLogger.warning(
            'Portal messages realtime error',
            metadata: {'conversationId': convId, 'error': e.toString()},
          );
        });
      }
      _jumpToBottom();
    } catch (e, st) {
      AppLogger.error('Portal messages load failed',
          error: e, stackTrace: st,
          metadata: {'projectId': widget.projectId});
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load messages.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadOlder() async {
    final convId = _conversationId;
    if (convId == null || _isLoadingOlder || !_hasMore || _messages.isEmpty) {
      return;
    }
    final preview = PortalPreviewScope.of(context);
    setState(() => _isLoadingOlder = true);
    try {
      final oldestRaw = _messages.first['created_at'] as String?;
      final oldest = oldestRaw != null ? DateTime.tryParse(oldestRaw) : null;
      final rpcMsgs = await _portalService.getThreadMessages(
        conversationId: convId,
        previewCustomerId: preview,
        limit: _pageSize,
        before: oldest,
      );
      final page = List<Map<String, dynamic>>.from(rpcMsgs);
      // Returned DESC; reverse and prepend. Dedupe by id in case the cursor
      // boundary overlaps.
      final existingIds = _messages.map((m) => m['id'] as String?).toSet();
      final older = page.reversed
          .where((m) => !existingIds.contains(m['id']))
          .toList();
      if (!mounted) return;
      setState(() {
        _messages = [...older, ..._messages];
        _hasMore = page.length == _pageSize;
        _isLoadingOlder = false;
      });
    } catch (e) {
      AppLogger.warning(
        'Portal messages load-older failed',
        metadata: {
          'conversationId': convId,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      setState(() => _isLoadingOlder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load older messages.')),
      );
    }
  }

  void _onInsert(Map<String, dynamic> row) {
    if (!mounted) return;
    final id = row['id'] as String?;
    if (id == null) return;
    // Dedupe: realtime can briefly race with our own send returning the row.
    if (_messages.any((m) => m['id'] == id)) return;
    // The realtime payload comes straight from the `messages` table, whose
    // timestamp column is named `timestamp` (a reserved-word column name
    // dating back to migration 002). The RPC-loaded rows have an aliased
    // `created_at` field. Normalize here so bubble rendering and the
    // pagination cursor can read a single key.
    final normalized = Map<String, dynamic>.from(row);
    if (normalized['created_at'] == null && normalized['timestamp'] != null) {
      normalized['created_at'] = normalized['timestamp'];
    }
    final wasAtBottom = _isNearBottom();
    setState(() => _messages = [..._messages, normalized]);
    final convId = _conversationId;
    if (convId != null) {
      _portalService.markThreadRead(convId).catchError((_) {});
    }
    if (wasAtBottom) {
      _jumpToBottom();
    }
  }

  bool _isNearBottom() {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    return (pos.maxScrollExtent - pos.pixels) < 80;
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _pickAttachments() async {
    if (_workspaceId == null || _conversationId == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final added = <_PendingAttachment>[];
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        added.add(_PendingAttachment(
          fileName: f.name,
          bytes: bytes,
          mimeType: _mimeFromName(f.name),
        ));
      }
      if (added.isEmpty) return;
      if (!mounted) return;
      setState(() => _pending.addAll(added));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick files.')),
      );
    }
  }

  void _removePending(_PendingAttachment a) {
    setState(() => _pending.remove(a));
  }

  Future<void> _send() async {
    final text = _composeCtrl.text.trim();
    final convId = _conversationId;
    final workspaceId = _workspaceId;
    if (convId == null || _isSending) return;
    if (text.isEmpty && _pending.isEmpty) return;
    setState(() => _isSending = true);
    try {
      // 1. Upload pending attachments first so the server-side message has
      //    its URLs at insert time. Sequential to keep memory bounded and
      //    give a deterministic order in the bubble.
      final uploaded = <Map<String, dynamic>>[];
      if (_pending.isNotEmpty) {
        if (workspaceId == null) {
          throw StateError('Missing workspace context for upload');
        }
        for (final p in _pending) {
          final att = await _portalService.uploadPortalAttachment(
            conversationId: convId,
            workspaceId: workspaceId,
            bytes: p.bytes,
            fileName: p.fileName,
            mimeType: p.mimeType,
          );
          uploaded.add(Map<String, dynamic>.from(att));
        }
      }
      // 2. The RPC accepts empty content when at least one attachment is
      //    present (relaxed in 20260524010000), so we send the text as-is.
      await _portalService.sendThreadMessage(
        conversationId: convId,
        content: text,
        attachments: uploaded,
      );
      _composeCtrl.clear();
      if (mounted) setState(() => _pending.clear());
      // Realtime will deliver the inserted row.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _mimeFromName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  Future<void> _openAttachment(Map<String, dynamic> a) async {
    final rawUrl = a['fileUrl'] as String?;
    if (rawUrl == null) return;
    try {
      final resolved = await _portalService.resolvePortalAttachmentUrl(rawUrl);
      final url = (resolved as String?) ?? rawUrl;
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open attachment.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open attachment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPreview = PortalPreviewScope.of(context) != null;

    if (_isLoading) {
      return const ListSkeleton();
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    // _messages is kept oldest-first by both _load() (which reverses the
    // RPC's DESC result) and the insert subscription (which appends).
    final showHeader = _hasMore || _isLoadingOlder;
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    isPreview
                        ? 'No messages yet (preview).'
                        : 'No messages yet. Say hello!',
                    style: const TextStyle(color: AppColors.textTertiary),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _messages.length + (showHeader ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (showHeader && i == 0) return _loadOlderHeader();
                    final msgIndex = showHeader ? i - 1 : i;
                    return _bubble(_messages[msgIndex]);
                  },
                ),
        ),
        const Divider(height: 1),
        if (_pending.isNotEmpty) _pendingStrip(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: (isPreview || _isSending) ? null : _pickAttachments,
                  tooltip: 'Attach file',
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    controller: _composeCtrl,
                    enabled: !isPreview && !_isSending,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: isPreview
                          ? 'Sending disabled in preview mode'
                          : 'Type a message…',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (isPreview || _isSending) ? null : _send,
                  icon: _isSending
                      ? const SizedBox(
                          width: 14, height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 18),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pendingStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      color: AppColors.surfaceAlt,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final p in _pending)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.insert_drive_file, size: 16),
                  label: Text(
                    p.fileName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onDeleted: _isSending ? null : () => _removePending(p),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loadOlderHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: _isLoadingOlder
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: _loadOlder,
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Load older messages'),
              ),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final sender = (m['sender_name'] as String?) ?? 'Unknown';
    final content = (m['content'] as String?) ?? '';
    final createdRaw = m['created_at'] as String?;
    DateTime? created;
    if (createdRaw != null) {
      created = DateTime.tryParse(createdRaw)?.toLocal();
    }
    final ts = created == null
        ? ''
        : DateFormat.yMMMd().add_jm().format(created);

    final rawAttachments = m['attachments'];
    final attachments = <Map<String, dynamic>>[];
    if (rawAttachments is List) {
      for (final a in rawAttachments) {
        if (a is Map) attachments.add(Map<String, dynamic>.from(a));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sender,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                ts,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (content.isNotEmpty) Text(content),
                if (attachments.isNotEmpty) ...[
                  if (content.isNotEmpty) const SizedBox(height: 6),
                  for (final a in attachments) _attachmentChip(a),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentChip(Map<String, dynamic> a) {
    final name = (a['fileName'] as String?) ?? 'Attachment';
    final size = a['fileSize'] is int ? a['fileSize'] as int : null;
    final sizeLabel = size == null ? null : _formatFileSize(size);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => _openAttachment(a),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sizeLabel != null) ...[
                const SizedBox(width: 6),
                Text(
                  sizeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PendingAttachment {
  final String fileName;
  final Uint8List bytes;
  final String mimeType;
  _PendingAttachment({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });
}
