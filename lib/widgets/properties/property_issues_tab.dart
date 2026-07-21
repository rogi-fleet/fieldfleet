import 'package:flutter/material.dart';

import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/property_issue.dart';
import '../../services/supabase/property_issue_service.dart';
import '../../theme/theme.dart';

/// Staff-side tab showing issues unit holders have reported against this
/// property, with status triage (open -> in progress -> resolved/closed).
class PropertyIssuesTab extends StatefulWidget {
  final Project project;
  final Property property;

  const PropertyIssuesTab({
    super.key,
    required this.project,
    required this.property,
  });

  @override
  State<PropertyIssuesTab> createState() => _PropertyIssuesTabState();
}

class _PropertyIssuesTabState extends State<PropertyIssuesTab> {
  final _issueService = SupabasePropertyIssueService();

  static const _statusLabels = {
    'open': 'Open',
    'in_progress': 'In Progress',
    'resolved': 'Resolved',
    'closed': 'Closed',
  };

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return AppColors.error;
      case 'high':
        return AppColors.warning;
      case 'low':
        return AppColors.textTertiary;
      default:
        return AppColors.info;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
      case 'closed':
        return AppColors.success;
      case 'in_progress':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  Future<void> _changeStatus(PropertyIssue issue, String newStatus) async {
    try {
      await _issueService.updateIssueStatus(issue.id, newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update status: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PropertyIssue>>(
      stream: _issueService.watchPropertyIssues(widget.property.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final issues = snapshot.data ?? const <PropertyIssue>[];
        if (issues.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.report_problem_outlined,
                    size: 48, color: AppColors.textTertiary),
                SizedBox(height: 12),
                Text(
                  'No issues reported yet',
                  style:
                      TextStyle(fontSize: 18, color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: issues.length,
          itemBuilder: (context, index) {
            final issue = issues[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            issue.title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        DropdownButton<String>(
                          value: issue.status,
                          underline: const SizedBox.shrink(),
                          items: _statusLabels.entries
                              .map((e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      style: TextStyle(
                                        color: _statusColor(e.key),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null && value != issue.status) {
                              _changeStatus(issue, value);
                            }
                          },
                        ),
                      ],
                    ),
                    if ((issue.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(issue.description!),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.flag,
                            size: 14, color: _priorityColor(issue.priority)),
                        const SizedBox(width: 4),
                        Text(
                          issue.priority,
                          style: TextStyle(
                              fontSize: 12,
                              color: _priorityColor(issue.priority)),
                        ),
                        const SizedBox(width: 12),
                        if (issue.reporterName != null) ...[
                          const Icon(Icons.person,
                              size: 14, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            issue.reporterName!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textTertiary),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${issue.createdAt.month}/${issue.createdAt.day}/${issue.createdAt.year}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
