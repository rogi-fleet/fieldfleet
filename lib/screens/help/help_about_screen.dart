import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../config/build_info.dart';
import '../../widgets/feedback_dialog.dart';
import '../../theme/theme.dart';

class HelpAboutScreen extends StatefulWidget {
  const HelpAboutScreen({super.key});

  @override
  State<HelpAboutScreen> createState() => _HelpAboutScreenState();
}

class _HelpAboutScreenState extends State<HelpAboutScreen> {
  late final Future<_CommitUpdatesFeed?> _whatsNewFeed = _loadWhatsNewFeed();

  Future<void> _openUri(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.toString()}')),
      );
    }
  }

  Future<_CommitUpdatesFeed?> _loadWhatsNewFeed() async {
    try {
      final response = await http.get(Uri.parse('/commit-updates/data.json'));
      if (response.statusCode != 200) return null;

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return null;
      return _CommitUpdatesFeed.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

  String _formatDay(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final weekdayName = weekdays[parsed.weekday - 1];
    final monthName = months[parsed.month - 1];
    return '$weekdayName, $monthName ${parsed.day}, ${parsed.year}';
  }

  Widget _buildBulletedSection(
    BuildContext context,
    String title,
    List<String> items,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    const headingColor = Color(0xFF19202A);
    const bodyColor = Color(0xFF19202A);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: headingColor,
            ),
          ),
          const SizedBox(height: 4),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $item',
                style: textTheme.bodyMedium?.copyWith(color: bodyColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({required String label, required String value}) {
    const cardColor = Colors.white;
    const lineColor = Color(0xFFD8E0ED);
    const valueColor = Color(0xFF0B67C2);
    const labelColor = Color(0xFF5E6A7D);

    return Container(
      width: 180,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: lineColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: valueColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommitUpdatesContent(
    BuildContext context,
    _CommitUpdatesFeed feed,
  ) {
    final textTheme = Theme.of(context).textTheme;
    const bgColor = Color(0xFFF3F6FB);
    const cardColor = Colors.white;
    const inkColor = Color(0xFF19202A);
    const mutedColor = Color(0xFF5E6A7D);
    const lineColor = Color(0xFFD8E0ED);
    const brandColor = Color(0xFF0B67C2);
    const brandSoftColor = Color(0xFFE7F1FC);
    final totalCommits = feed.days.fold<int>(
      0,
      (sum, day) => sum + day.commits.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.r12),
            gradient: const RadialGradient(
              center: Alignment(-0.95, -1.1),
              radius: 1.4,
              colors: [Color(0xFFFFFFFF), Color(0xFFF3F6FB), Color(0xFFEAF0FA)],
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0C2F56),
                      Color(0xFF0B67C2),
                      Color(0xFF2F8AE2),
                    ],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33092348),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FieldFleet Sponsor Commit Updates',
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Daily AI summaries of development commits.',
                      style: textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD7E9FF),
                      ),
                    ),
                    if (feed.generatedAt.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Generated: ${feed.generatedAt}',
                          style: textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFD7E9FF),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildStatTile(
                    label: 'Coverage start',
                    value: feed.since.isNotEmpty ? feed.since : 'n/a',
                  ),
                  _buildStatTile(
                    label: 'Days covered',
                    value: '${feed.days.length}',
                  ),
                  _buildStatTile(
                    label: 'Total commits',
                    value: '$totalCommits',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...feed.days.map(
                (day) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardColor,
                    border: Border.all(color: lineColor),
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140E244A),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatDay(day.date),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: inkColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: brandSoftColor,
                              border: Border.all(
                                color: const Color(0xFFC4DBF8),
                              ),
                            ),
                            child: Text(
                              '${day.commits.length} commits',
                              style: textTheme.labelMedium?.copyWith(
                                color: const Color(0xFF0B4F98),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (day.summaryText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            day.summaryText,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: inkColor,
                            ),
                          ),
                        ),
                      if (day.summarySource.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Summary source: ${day.summarySource}',
                            style: textTheme.bodySmall?.copyWith(
                              color: mutedColor,
                            ),
                          ),
                        ),
                      _buildBulletedSection(
                        context,
                        'Client Impact',
                        day.clientImpact.isNotEmpty
                            ? day.clientImpact
                            : const <String>[
                                'General product quality and reliability improvements.',
                              ],
                      ),
                      _buildBulletedSection(
                        context,
                        'Highlights',
                        day.highlights.isNotEmpty
                            ? day.highlights
                            : const <String>[
                                'No specific highlights available.',
                              ],
                      ),
                      _buildBulletedSection(
                        context,
                        'Risks / Watchouts',
                        day.risks.isNotEmpty
                            ? day.risks
                            : const <String>['No explicit risks noted.'],
                      ),
                      if (day.commits.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(bottom: 8),
                              title: Text(
                                'View commit list',
                                style: textTheme.titleSmall?.copyWith(
                                  color: brandColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              children: day.commits
                                  .map(
                                    (commit) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: RichText(
                                        text: TextSpan(
                                          style: textTheme.bodyMedium?.copyWith(
                                            color: inkColor,
                                          ),
                                          children: [
                                            WidgetSpan(
                                              alignment:
                                                  PlaceholderAlignment.middle,
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF0F4FB,
                                                  ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFD6E1F3,
                                                    ),
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  commit.shortHash,
                                                  style: textTheme.bodySmall
                                                      ?.copyWith(
                                                    fontFamily: 'monospace',
                                                    color: inkColor,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            TextSpan(text: commit.subject),
                                            TextSpan(
                                              text: '  ${commit.author}',
                                              style: textTheme.bodySmall
                                                  ?.copyWith(color: mutedColor),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // The page title/subtitle sit directly on the scaffold (chrome) background,
    // which is dark in dark-chrome mode — so they must use chrome colors, not
    // the default content text colors (which would render dark-on-dark).
    final chrome = ChromeColors.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            Text(
              'Help & About',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: chrome.textActive,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Support links, release details, and current build information.',
              style: textTheme.bodyMedium?.copyWith(
                color: chrome.text,
              ),
            ),
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Need Help?',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openUri(
                      context,
                      Uri.parse('mailto:support@example.com'),
                    ),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Email Support'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openUri(
                      context,
                      Uri.parse('https://app.example.com'),
                    ),
                    icon: const Icon(Icons.public),
                    label: const Text('Portal'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showFeedbackDialog(context),
                    icon: const Icon(Icons.feedback_outlined),
                    label: const Text('Send Feedback'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _InfoCard(
              title: 'About FieldFleet',
              child: Text(
                'FieldFleet centralizes project operations, scheduling, documents, and reporting for restoration teams.',
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            _InfoCard(
              title: 'What\'s New',
              child: FutureBuilder<_CommitUpdatesFeed?>(
                future: _whatsNewFeed,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 56,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final feed = snapshot.data;
                  if (feed == null || feed.days.isEmpty) {
                    return Text(
                      'No recent updates to show yet — check back soon.',
                      style: textTheme.bodyMedium,
                    );
                  }

                  return _buildCommitUpdatesContent(context, feed);
                },
              ),
            ),
            const SizedBox(height: 12),
            _InfoCard(
              title: 'Build Indicator',
              child: SelectableText(
                BuildInfo.fullLabel,
                style: textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitUpdatesFeed {
  final String since;
  final String generatedAt;
  final List<_CommitUpdatesDay> days;

  const _CommitUpdatesFeed({
    required this.since,
    required this.generatedAt,
    required this.days,
  });

  factory _CommitUpdatesFeed.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final parsedDays = rawDays is List
        ? rawDays
            .whereType<Map<String, dynamic>>()
            .map(_CommitUpdatesDay.fromJson)
            .where((day) => day.date.isNotEmpty)
            .toList()
        : const <_CommitUpdatesDay>[];
    return _CommitUpdatesFeed(
      since: json['since']?.toString().trim() ?? '',
      generatedAt: json['generated_at']?.toString().trim() ?? '',
      days: parsedDays,
    );
  }
}

class _CommitUpdatesDay {
  final String date;
  final String summaryText;
  final String summarySource;
  final List<String> clientImpact;
  final List<String> highlights;
  final List<String> risks;
  final List<_CommitUpdatesCommit> commits;

  const _CommitUpdatesDay({
    required this.date,
    required this.summaryText,
    required this.summarySource,
    required this.clientImpact,
    required this.highlights,
    required this.risks,
    required this.commits,
  });

  factory _CommitUpdatesDay.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final summaryMap =
        summary is Map<String, dynamic> ? summary : const <String, dynamic>{};
    final rawCommits = json['commits'];
    return _CommitUpdatesDay(
      date: json['date']?.toString().trim() ?? '',
      summaryText: summaryMap['summary']?.toString().trim() ?? '',
      summarySource: summaryMap['source']?.toString().trim() ?? '',
      clientImpact: _toStringList(summaryMap['client_impact']),
      highlights: _toStringList(summaryMap['highlights']),
      risks: _toStringList(summaryMap['risks']),
      commits: rawCommits is List
          ? rawCommits
              .whereType<Map<String, dynamic>>()
              .map(_CommitUpdatesCommit.fromJson)
              .where((commit) => commit.shortHash.isNotEmpty)
              .toList()
          : const <_CommitUpdatesCommit>[],
    );
  }
}

class _CommitUpdatesCommit {
  final String shortHash;
  final String author;
  final String subject;

  const _CommitUpdatesCommit({
    required this.shortHash,
    required this.author,
    required this.subject,
  });

  factory _CommitUpdatesCommit.fromJson(Map<String, dynamic> json) {
    return _CommitUpdatesCommit(
      shortHash: json['short_hash']?.toString().trim() ?? '',
      author: json['author']?.toString().trim() ?? '',
      subject: json['subject']?.toString().trim() ?? '',
    );
  }
}

List<String> _toStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
