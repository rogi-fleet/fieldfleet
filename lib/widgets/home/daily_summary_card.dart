import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../models/daily_ai_summary.dart';
import '../../models/conversation.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../messaging_popup.dart';

class DailySummaryCard extends StatefulWidget {
  final String workspaceId;
  final String userId;

  const DailySummaryCard({
    super.key,
    required this.workspaceId,
    required this.userId,
  });

  @override
  State<DailySummaryCard> createState() => _DailySummaryCardState();
}

class _DailySummaryCardState extends State<DailySummaryCard> {
  final _summaryService = ServiceLocator.dailySummaryService;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  DailyAiSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary({bool force = false}) async {
    if (!mounted) return;

    setState(() {
      _error = null;
      _isLoading = !_isRefreshing;
    });

    try {
      if (force) {
        await _summaryService.generateSummary(
          workspaceId: widget.workspaceId,
          userId: widget.userId,
          force: true,
        );
      }

      var summary = await _summaryService.getTodaySummary(
        workspaceId: widget.workspaceId,
        userId: widget.userId,
      );

      if (summary == null) {
        await _summaryService.generateSummary(
          workspaceId: widget.workspaceId,
          userId: widget.userId,
        );

        summary = await _summaryService.getTodaySummary(
          workspaceId: widget.workspaceId,
          userId: widget.userId,
        );
      }

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load summary';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  String _formatUpdatedAt(DailyAiSummary summary) {
    return DateFormat('MMM d, yyyy h:mm a').format(summary.generatedAt);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.iconGap),
                const Expanded(
                  child: Text(
                    "Today's Summary",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isRefreshing
                      ? null
                      : () {
                          setState(() => _isRefreshing = true);
                          _loadSummary(force: true);
                        },
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh summary',
                ),
              ],
            ),
            if (_summary != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.base),
                child: Text(
                  'Updated ${_formatUpdatedAt(_summary!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              const SizedBox(height: AppSpacing.base),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.base),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: AppColors.textSecondary),
              )
            else if (_summary == null)
              const Text(
                'No summary yet. Check back in a moment.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else if (_summary!.summaryMarkdown.trim().isEmpty)
              const Text(
                'No actions requiring attention today.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else ...[
              StreamBuilder<List<Conversation>>(
                stream: ServiceLocator.messageService.getConversations(
                  workspaceId: widget.workspaceId,
                  userId: widget.userId,
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final unread = snapshot.data!
                      .fold<int>(0, (sum, c) => sum + c.getUnreadCount(widget.userId));
                  if (unread == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.base),
                    child: InkWell(
                      onTap: () => showMessagingPopup(context),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.messageAccentLight,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: AppColors.messageAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.mark_email_unread_outlined,
                              size: 16,
                              color: AppColors.messageAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$unread unread message${unread == 1 ? '' : 's'} — tap to open inbox',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.messageAccentDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              MarkdownBody(
                data: _summary!.summaryMarkdown,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(height: 1.4),
                  listBullet: const TextStyle(height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
