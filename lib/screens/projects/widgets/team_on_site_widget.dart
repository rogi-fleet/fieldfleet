import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/project.dart';
import '../../../models/time_entry.dart';
import '../../../models/user.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

/// Project Team widget showing all team members and their active status
class TeamOnSiteTodayWidget extends StatefulWidget {
  final Project project;

  const TeamOnSiteTodayWidget({super.key, required this.project});

  @override
  State<TeamOnSiteTodayWidget> createState() => _TeamOnSiteTodayWidgetState();
}

class _TeamOnSiteTodayWidgetState extends State<TeamOnSiteTodayWidget> {
  late Future<List<_TeamMemberInfo>> _teamFuture;
  late String _teamFutureKey;

  @override
  void initState() {
    super.initState();
    _teamFutureKey = _computeKey(widget.project);
    _teamFuture = _getProjectTeamStatus(widget.project);
  }

  @override
  void didUpdateWidget(covariant TeamOnSiteTodayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKey = _computeKey(widget.project);
    if (newKey != _teamFutureKey) {
      _teamFutureKey = newKey;
      _teamFuture = _getProjectTeamStatus(widget.project);
    }
  }

  String _computeKey(Project project) {
    final teamIds = [...project.teamMemberIds]..sort();
    return [
      project.id,
      project.workspaceId,
      project.projectManagerId ?? '',
      project.supervisorId ?? '',
      project.salespersonId ?? '',
      teamIds.join(','),
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.people,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '$singular Team',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<_TeamMemberInfo>>(
              future: _teamFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppColors.textTertiary),
                          const SizedBox(height: 8),
                          const Text(
                            'Error loading team data',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final teamMembers = snapshot.data ?? [];

                if (teamMembers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          const Icon(Icons.group_off, size: 48, color: AppColors.textTertiary),
                          const SizedBox(height: 8),
                          const Text(
                            'No team members assigned',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final onSiteCount = teamMembers.where((m) => m.timeEntry != null && m.timeEntry!.clockOut == null).length;

                return Column(
                  children: [
                    // Summary header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.badge,
                                size: 16,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$onSiteCount ${onSiteCount == 1 ? 'person' : 'people'} on site today',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            DateFormat('MMM d').format(DateTime.now()),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Team member list
                    ...teamMembers.map((member) => _buildTeamMemberCard(context, member)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamMemberCard(BuildContext context, _TeamMemberInfo member) {
    final hasEntry = member.timeEntry != null;
    final isActive = hasEntry && member.timeEntry!.clockOut == null;

    String durationText = '';
    if (hasEntry) {
      final duration = member.timeEntry!.clockOut != null
          ? member.timeEntry!.clockOut!.difference(member.timeEntry!.clockIn)
          : DateTime.now().difference(member.timeEntry!.clockIn);
      
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      durationText = '${hours}h ${minutes}m';
    }

    final memberSingular = singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    );
    String roleText = 'Team Member';
    if (member.user.id == widget.project.projectManagerId) {
      roleText = '$memberSingular Manager';
    } else if (member.user.id == widget.project.supervisorId) {
      roleText = 'Supervisor';
    } else if (member.user.id == widget.project.salespersonId) {
      roleText = 'Sales';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          // Avatar
          StreamBuilder<AppUser?>(
            stream: ServiceLocator.userService.getUserStream(member.user.id),
            builder: (context, snapshot) {
              final liveUser = snapshot.data ?? member.user;
              return CircleAvatar(
                radius: 20,
                backgroundColor: isActive
                    ? AppColors.success
                    : (hasEntry
                          ? AppColors.textTertiary
                          : Colors.grey.shade400),
                foregroundColor: Colors.white,
                backgroundImage: liveUser.profilePictureUrl != null
                    ? CachedNetworkImageProvider(liveUser.profilePictureUrl!)
                    : null,
                child: liveUser.profilePictureUrl == null
                    ? Text(
                        liveUser.displayName?.substring(0, 1).toUpperCase() ??
                            liveUser.email.substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )
                    : null,
              );
            },
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        member.user.displayName ?? member.user.email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text(
                        roleText,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isActive
                          ? Icons.circle
                          : (hasEntry ? Icons.check_circle : Icons.person_off),
                      size: 12,
                      color: isActive
                          ? AppColors.success
                          : (hasEntry ? AppColors.textTertiary : Colors.grey.shade500),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isActive
                          ? 'On site'
                          : (hasEntry ? 'Clocked out' : 'Off site'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive
                            ? AppColors.successDark
                            : (hasEntry ? AppColors.textSecondary : Colors.grey.shade600),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Time info
          if (hasEntry)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  durationText,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'In: ${DateFormat('h:mm a').format(member.timeEntry!.clockIn)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<List<_TeamMemberInfo>> _getProjectTeamStatus(Project project) async {
    try {
      final allUserIds = <String>{};

      if (project.projectManagerId != null) allUserIds.add(project.projectManagerId!);
      if (project.supervisorId != null) allUserIds.add(project.supervisorId!);
      if (project.salespersonId != null) allUserIds.add(project.salespersonId!);
      allUserIds.addAll(project.teamMemberIds);

      // Get today's date range
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      // Get time entries for this project today - note: this returns a Stream
      final timeEntryService = ServiceLocator.timeEntryService;
      final timeEntriesStream = timeEntryService.getTimeEntriesForProject(
        project.id,
        workspaceId: project.workspaceId,
      );

      // Get first snapshot from stream
      final timeEntries = await timeEntriesStream.first;

      // Filter for today's entries
      final todayEntries = timeEntries.where((entry) {
        final clockInDate = entry.clockIn;
        return clockInDate.isAfter(startOfDay) && clockInDate.isBefore(endOfDay);
      }).toList();

      for (final entry in todayEntries) {
        allUserIds.add(entry.workerId);
      }

      // Get user info for each entry
      final userService = ServiceLocator.userService;
      final teamMembers = <_TeamMemberInfo>[];

      for (final userId in allUserIds) {
        final user = await userService.getUserById(userId);
        if (user != null) {
          final userEntries = todayEntries.where((e) => e.workerId == userId).toList();
          userEntries.sort((a, b) => b.clockIn.compareTo(a.clockIn));
          final timeEntry = userEntries.isNotEmpty ? userEntries.first : null;
          
          teamMembers.add(_TeamMemberInfo(
            user: user,
            timeEntry: timeEntry,
          ));
        }
      }

      // Sort: active entries first, then clocked out, then off site, then alphabetical
      teamMembers.sort((a, b) {
        final aActive = a.timeEntry != null && a.timeEntry!.clockOut == null;
        final bActive = b.timeEntry != null && b.timeEntry!.clockOut == null;
        
        if (aActive && !bActive) return -1;
        if (!aActive && bActive) return 1;
        
        if (a.timeEntry != null && b.timeEntry != null) {
          return b.timeEntry!.clockIn.compareTo(a.timeEntry!.clockIn);
        }
        
        if (a.timeEntry != null && b.timeEntry == null) return -1;
        if (a.timeEntry == null && b.timeEntry != null) return 1;
        
        final aName = a.user.displayName ?? a.user.email;
        final bName = b.user.displayName ?? b.user.email;
        return aName.compareTo(bName);
      });

      return teamMembers;
    } catch (e) {
      debugPrint('Error getting team on site: $e');
      rethrow;
    }
  }
}

class _TeamMemberInfo {
  final AppUser user;
  final TimeEntry? timeEntry;

  _TeamMemberInfo({
    required this.user,
    this.timeEntry,
  });
}
