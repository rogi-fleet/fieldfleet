import '../models/task.dart';
import '../models/skill.dart';
import '../models/workspace_member.dart';
import '../models/capacity_planning.dart';
import 'service_locator.dart';

/// Configuration for the task scheduler algorithm.
class SchedulerConfig {
  final double maxUtilizationThreshold;
  final bool requireFullSkillMatch;

  const SchedulerConfig({
    this.maxUtilizationThreshold = 0.8,
    this.requireFullSkillMatch = false,
  });
}

/// A proposed assignment of a team member to a task.
class TaskAssignmentProposal {
  final Task task;
  String proposedAssigneeId;
  String proposedAssigneeName;
  double skillMatchScore;
  double availabilityScore;
  double combinedScore;
  List<String> matchedSkillNames;
  List<String> missingSkillNames;
  double avgUtilizationDuringTask;
  bool accepted;

  TaskAssignmentProposal({
    required this.task,
    required this.proposedAssigneeId,
    required this.proposedAssigneeName,
    required this.skillMatchScore,
    required this.availabilityScore,
    required this.combinedScore,
    required this.matchedSkillNames,
    required this.missingSkillNames,
    required this.avgUtilizationDuringTask,
    this.accepted = true,
  });
}

/// Result of the scheduling algorithm.
class SchedulerResult {
  final List<TaskAssignmentProposal> proposals;
  final List<Task> unassignableTasks;
  final int totalEligibleTasks;
  final int skippedNoDates;

  const SchedulerResult({
    required this.proposals,
    required this.unassignableTasks,
    required this.totalEligibleTasks,
    required this.skippedNoDates,
  });
}

/// Deterministic task scheduler that assigns team members to tasks
/// based on skill match and capacity availability.
class TaskSchedulerService {
  /// Score a single member against a single task.
  /// Returns null if the member should be skipped (no skill match or over capacity).
  static _CandidateScore? _scoreMember({
    required Task task,
    required WorkspaceMember member,
    required Set<String> taskSkills,
    required Set<String> memberSkills,
    required Map<String, CapacityMemberRow> capacityByUser,
    required SchedulerConfig config,
    double extraPenalty = 0.0,
  }) {
    // Skill scoring
    double skillScore;
    Set<String> matched;
    Set<String> missing;

    if (taskSkills.isEmpty) {
      skillScore = 1.0;
      matched = {};
      missing = {};
    } else {
      matched = taskSkills.intersection(memberSkills);
      missing = taskSkills.difference(memberSkills);
      skillScore = matched.length / taskSkills.length;
      if (skillScore == 0.0) return null;
      if (config.requireFullSkillMatch && skillScore < 1.0) return null;
    }

    // Availability scoring
    final capacityRow = capacityByUser[member.userId];
    double availabilityScore;
    double avgUtil;

    if (capacityRow == null) {
      availabilityScore = 0.3;
      avgUtil = 0.0;
    } else if (task.startDate == null && task.dueDate == null) {
      avgUtil = capacityRow.utilizationPct;
      if (avgUtil >= config.maxUtilizationThreshold) return null;
      availabilityScore =
          (1.0 - (avgUtil / config.maxUtilizationThreshold)).clamp(0.0, 1.0);
    } else {
      final taskStart = task.startDate ?? task.dueDate!;
      final taskEnd = task.dueDate ?? task.startDate!;
      final daysInRange = capacityRow.days
          .where(
              (d) => !d.date.isBefore(taskStart) && !d.date.isAfter(taskEnd))
          .toList();

      if (daysInRange.isEmpty) {
        availabilityScore = 0.5;
        avgUtil = capacityRow.utilizationPct;
      } else {
        avgUtil = daysInRange.fold(0.0, (sum, d) => sum + d.utilizationPct) /
            daysInRange.length;
        if (avgUtil >= config.maxUtilizationThreshold) return null;
        availabilityScore =
            (1.0 - (avgUtil / config.maxUtilizationThreshold)).clamp(0.0, 1.0);
      }
    }

    final combined =
        (skillScore * 0.6 + availabilityScore * 0.4 - extraPenalty)
            .clamp(0.0, 1.0);

    return _CandidateScore(
      userId: member.userId,
      skillScore: skillScore,
      availabilityScore: availabilityScore,
      combined: combined,
      avgUtil: avgUtil,
      matchedSkills: matched,
      missingSkills: missing,
    );
  }

  static TaskAssignmentProposal? _buildProposal({
    required Task task,
    required _CandidateScore candidate,
    required Map<String, String> skillMap,
    required Map<String, String> userDisplayNames,
  }) {
    return TaskAssignmentProposal(
      task: task,
      proposedAssigneeId: candidate.userId,
      proposedAssigneeName:
          userDisplayNames[candidate.userId] ?? 'Unknown',
      skillMatchScore: candidate.skillScore,
      availabilityScore: candidate.availabilityScore,
      combinedScore: candidate.combined,
      matchedSkillNames:
          candidate.matchedSkills.map((id) => skillMap[id] ?? id).toList(),
      missingSkillNames:
          candidate.missingSkills.map((id) => skillMap[id] ?? id).toList(),
      avgUtilizationDuringTask: candidate.avgUtil,
    );
  }

  SchedulerResult computeAssignments({
    required List<Task> tasks,
    required List<WorkspaceMember> members,
    required CapacitySnapshot capacitySnapshot,
    required List<Skill> skills,
    required Map<String, String> userDisplayNames,
    required SchedulerConfig config,
  }) {
    final skillMap = <String, String>{
      for (final s in skills) s.id: s.name,
    };
    final capacityByUser = <String, CapacityMemberRow>{
      for (final m in capacitySnapshot.members) m.userId: m,
    };
    final memberSkillsMap = <String, Set<String>>{
      for (final m in members) m.userId: m.skillIds.toSet(),
    };

    // Filter eligible tasks: incomplete, unassigned, not summary
    final unassignedTasks = tasks
        .where((t) =>
            !t.isComplete &&
            t.assignedToIds.isEmpty &&
            t.taskType != TaskType.summary)
        .toList();

    final withDates = <Task>[];
    var skippedNoDates = 0;
    for (final t in unassignedTasks) {
      if (t.startDate != null || t.dueDate != null) {
        withDates.add(t);
      } else {
        skippedNoDates++;
      }
    }

    final proposals = <TaskAssignmentProposal>[];
    final unassignable = <Task>[];

    // Track cumulative assignments to avoid overloading a single member
    final assignedCountPerUser = <String, int>{};

    for (final task in withDates) {
      final taskSkills = task.requiredSkillIds.toSet();
      _CandidateScore? bestCandidate;

      for (final member in members) {
        final priorAssignments = assignedCountPerUser[member.userId] ?? 0;
        final candidate = _scoreMember(
          task: task,
          member: member,
          taskSkills: taskSkills,
          memberSkills: memberSkillsMap[member.userId] ?? {},
          capacityByUser: capacityByUser,
          config: config,
          extraPenalty: priorAssignments * 0.05,
        );
        if (candidate == null) continue;
        if (bestCandidate == null || candidate.combined > bestCandidate.combined) {
          bestCandidate = candidate;
        }
      }

      if (bestCandidate == null) {
        unassignable.add(task);
      } else {
        assignedCountPerUser[bestCandidate.userId] =
            (assignedCountPerUser[bestCandidate.userId] ?? 0) + 1;
        proposals.add(_buildProposal(
          task: task,
          candidate: bestCandidate,
          skillMap: skillMap,
          userDisplayNames: userDisplayNames,
        )!);
      }
    }

    // Sort proposals by combined score descending
    proposals.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));

    return SchedulerResult(
      proposals: proposals,
      unassignableTasks: unassignable,
      totalEligibleTasks: withDates.length,
      skippedNoDates: skippedNoDates,
    );
  }

  /// Find the best assignee for a single task. Returns null if no match found.
  TaskAssignmentProposal? findBestAssignee({
    required Task task,
    required List<WorkspaceMember> members,
    required CapacitySnapshot capacitySnapshot,
    required List<Skill> skills,
    required Map<String, String> userDisplayNames,
    SchedulerConfig config = const SchedulerConfig(),
  }) {
    final skillMap = <String, String>{
      for (final s in skills) s.id: s.name,
    };
    final capacityByUser = <String, CapacityMemberRow>{
      for (final m in capacitySnapshot.members) m.userId: m,
    };

    final taskSkills = task.requiredSkillIds.toSet();
    _CandidateScore? best;

    for (final member in members) {
      final candidate = _scoreMember(
        task: task,
        member: member,
        taskSkills: taskSkills,
        memberSkills: member.skillIds.toSet(),
        capacityByUser: capacityByUser,
        config: config,
      );
      if (candidate == null) continue;
      if (best == null || candidate.combined > best.combined) {
        best = candidate;
      }
    }

    if (best == null) return null;
    return _buildProposal(
      task: task,
      candidate: best,
      skillMap: skillMap,
      userDisplayNames: userDisplayNames,
    );
  }

  /// Score a specific member against a specific task.
  /// Used by the wizard override dropdown to recalculate scores.
  TaskAssignmentProposal? scoreSpecificMember({
    required Task task,
    required WorkspaceMember member,
    required CapacitySnapshot capacitySnapshot,
    required List<Skill> skills,
    required Map<String, String> userDisplayNames,
    SchedulerConfig config = const SchedulerConfig(),
  }) {
    final skillMap = <String, String>{
      for (final s in skills) s.id: s.name,
    };
    final capacityByUser = <String, CapacityMemberRow>{
      for (final m in capacitySnapshot.members) m.userId: m,
    };
    final taskSkills = task.requiredSkillIds.toSet();

    final candidate = _scoreMember(
      task: task,
      member: member,
      taskSkills: taskSkills,
      memberSkills: member.skillIds.toSet(),
      capacityByUser: capacityByUser,
      config: config,
    );
    if (candidate == null) return null;
    return _buildProposal(
      task: task,
      candidate: candidate,
      skillMap: skillMap,
      userDisplayNames: userDisplayNames,
    );
  }

  /// Convenience: fetch all data and find the best assignee for a single task.
  static Future<TaskAssignmentProposal?> autoAssign({
    required Task task,
    required String workspaceId,
  }) async {
    final membersFuture = (ServiceLocator.workspaceMemberService
            .getWorkspaceMembers(workspaceId)
            .first as Future<dynamic>)
        .then((v) => v as List<WorkspaceMember>);
    final skillsFuture = (ServiceLocator.skillService
            .getSkills(workspaceId)
            .first as Future<dynamic>)
        .then((v) => v as List<Skill>);
    final snapshotFuture =
        ServiceLocator.capacityPlanningService.getCapacitySnapshot(
      workspaceId: workspaceId,
      start: DateTime.now(),
      end: DateTime.now().add(const Duration(days: 90)),
    );

    final results = await Future.wait<dynamic>(
        [membersFuture, skillsFuture, snapshotFuture]);
    final members = results[0] as List<WorkspaceMember>;
    final skills = results[1] as List<Skill>;
    final snapshot = results[2] as CapacitySnapshot;

    final displayNames = <String, String>{
      for (final m in snapshot.members) m.userId: m.displayName,
    };
    for (final m in members) {
      displayNames.putIfAbsent(m.userId, () => m.userId);
    }

    return TaskSchedulerService().findBestAssignee(
      task: task,
      members: members,
      capacitySnapshot: snapshot,
      skills: skills,
      userDisplayNames: displayNames,
    );
  }
}

class _CandidateScore {
  final String userId;
  final double skillScore;
  final double availabilityScore;
  final double combined;
  final double avgUtil;
  final Set<String> matchedSkills;
  final Set<String> missingSkills;

  _CandidateScore({
    required this.userId,
    required this.skillScore,
    required this.availabilityScore,
    required this.combined,
    required this.avgUtil,
    required this.matchedSkills,
    required this.missingSkills,
  });
}
