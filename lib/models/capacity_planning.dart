class CapacityDayCell {
  final DateTime date;
  final double plannedHours;
  final double actualHours;
  final double committedHours;
  final double capacityHours;
  final double utilizationPct;

  const CapacityDayCell({
    required this.date,
    required this.plannedHours,
    required this.actualHours,
    required this.committedHours,
    required this.capacityHours,
    required this.utilizationPct,
  });
}

class CapacityMemberRow {
  final String userId;
  final String displayName;
  final List<CapacityDayCell> days;
  final double totalPlannedHours;
  final double totalActualHours;
  final double totalCommittedHours;
  final double totalCapacityHours;
  final double utilizationPct;

  const CapacityMemberRow({
    required this.userId,
    required this.displayName,
    required this.days,
    required this.totalPlannedHours,
    required this.totalActualHours,
    required this.totalCommittedHours,
    required this.totalCapacityHours,
    required this.utilizationPct,
  });
}

class CapacityIssue {
  final String userId;
  final String displayName;
  final DateTime date;
  final String issueType; // over_capacity | high_risk
  final double committedHours;
  final double capacityHours;
  final double utilizationPct;

  const CapacityIssue({
    required this.userId,
    required this.displayName,
    required this.date,
    required this.issueType,
    required this.committedHours,
    required this.capacityHours,
    required this.utilizationPct,
  });
}

class CapacitySnapshot {
  final DateTime start;
  final DateTime end;
  final List<CapacityMemberRow> members;
  final List<CapacityIssue> issues;

  const CapacitySnapshot({
    required this.start,
    required this.end,
    required this.members,
    required this.issues,
  });
}

class MemberCapacityException {
  final String id;
  final String workspaceId;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final double capacityMultiplier;
  final String? reason;

  const MemberCapacityException({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.capacityMultiplier,
    this.reason,
  });

  factory MemberCapacityException.fromRow(Map<String, dynamic> row) {
    return MemberCapacityException(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      userId: row['user_id'] as String,
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: DateTime.parse(row['end_date'] as String),
      capacityMultiplier:
          (row['capacity_multiplier'] as num?)?.toDouble() ?? 0.0,
      reason: row['reason'] as String?,
    );
  }
}
