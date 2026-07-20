class OvertimeRules {
  final double dailyOvertimeThreshold; // Hours per day before OT kicks in
  final double weeklyOvertimeThreshold; // Hours per week before OT kicks in
  final double dailyDoubleTimeThreshold; // Hours per day before double time
  final double overtimeMultiplier; // Typically 1.5
  final double doubleTimeMultiplier; // Typically 2.0

  /// Whether to ALSO apply the weekly (40h) overtime rule on top of daily OT.
  /// Off by default — weekly OT is a jurisdiction/payroll-policy choice, so a
  /// workspace must opt in. When off, only daily OT/DT applies (unchanged
  /// behavior). [E2 weekly OT]
  final bool applyWeeklyOvertime;

  const OvertimeRules({
    this.dailyOvertimeThreshold = 8.0,
    this.weeklyOvertimeThreshold = 40.0,
    this.dailyDoubleTimeThreshold = 12.0,
    this.overtimeMultiplier = 1.5,
    this.doubleTimeMultiplier = 2.0,
    this.applyWeeklyOvertime = false,
  });

  factory OvertimeRules.fromJson(Map<String, dynamic> json) {
    return OvertimeRules(
      dailyOvertimeThreshold: (json['dailyOvertimeThreshold'] as num?)?.toDouble() ?? 8.0,
      weeklyOvertimeThreshold: (json['weeklyOvertimeThreshold'] as num?)?.toDouble() ?? 40.0,
      dailyDoubleTimeThreshold: (json['dailyDoubleTimeThreshold'] as num?)?.toDouble() ?? 12.0,
      overtimeMultiplier: (json['overtimeMultiplier'] as num?)?.toDouble() ?? 1.5,
      doubleTimeMultiplier: (json['doubleTimeMultiplier'] as num?)?.toDouble() ?? 2.0,
      applyWeeklyOvertime: json['applyWeeklyOvertime'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dailyOvertimeThreshold': dailyOvertimeThreshold,
      'weeklyOvertimeThreshold': weeklyOvertimeThreshold,
      'dailyDoubleTimeThreshold': dailyDoubleTimeThreshold,
      'overtimeMultiplier': overtimeMultiplier,
      'doubleTimeMultiplier': doubleTimeMultiplier,
      'applyWeeklyOvertime': applyWeeklyOvertime,
    };
  }

  /// Apply the weekly threshold to a single entry: given this entry's
  /// daily-rule regular hours and the regular hours already logged earlier in
  /// the same workweek, convert the portion over [weeklyOvertimeThreshold] into
  /// overtime (daily OT is untouched, so no double-counting). Returns the
  /// adjusted regular hours and the extra overtime to add. No-op when the flag
  /// is off. [E2 weekly OT]
  ({double regular, double extraOvertime}) applyWeeklyToEntry(
    double entryRegular,
    double priorWeekRegular,
  ) {
    if (!applyWeeklyOvertime) {
      return (regular: entryRegular, extraOvertime: 0.0);
    }
    final allowed = weeklyOvertimeThreshold - priorWeekRegular;
    if (allowed >= entryRegular) {
      return (regular: entryRegular, extraOvertime: 0.0);
    }
    final newRegular = allowed < 0 ? 0.0 : allowed;
    return (regular: newRegular, extraOvertime: entryRegular - newRegular);
  }

  /// Calculate overtime for a single day's hours
  /// Returns (regularHours, overtimeHours, doubleTimeHours)
  ({double regular, double overtime, double doubleTime}) calculateOvertimeForDay(double totalHours) {
    if (totalHours <= dailyOvertimeThreshold) {
      // No overtime
      return (regular: totalHours, overtime: 0.0, doubleTime: 0.0);
    } else if (totalHours <= dailyDoubleTimeThreshold) {
      // Regular + overtime
      final overtime = totalHours - dailyOvertimeThreshold;
      return (
        regular: dailyOvertimeThreshold,
        overtime: overtime,
        doubleTime: 0.0,
      );
    } else {
      // Regular + overtime + double time
      final overtime = dailyDoubleTimeThreshold - dailyOvertimeThreshold;
      final doubleTime = totalHours - dailyDoubleTimeThreshold;
      return (
        regular: dailyOvertimeThreshold,
        overtime: overtime,
        doubleTime: doubleTime,
      );
    }
  }

  /// Calculate weekly overtime
  /// Takes total hours for the week and daily breakdown
  /// Returns adjusted (regularHours, overtimeHours) considering weekly threshold
  ({double regular, double overtime}) calculateOvertimeForWeek(
    double totalWeekHours,
    double regularHoursUsed,
  ) {
    if (totalWeekHours <= weeklyOvertimeThreshold) {
      return (regular: regularHoursUsed, overtime: 0.0);
    }

    // If weekly hours exceed threshold, convert some regular hours to OT
    final weeklyOT = totalWeekHours - weeklyOvertimeThreshold;
    final adjustedRegular = regularHoursUsed - weeklyOT;

    if (adjustedRegular < 0) {
      // All regular hours become OT
      return (regular: 0.0, overtime: regularHoursUsed);
    }

    return (regular: adjustedRegular, overtime: weeklyOT);
  }

  OvertimeRules copyWith({
    double? dailyOvertimeThreshold,
    double? weeklyOvertimeThreshold,
    double? dailyDoubleTimeThreshold,
    double? overtimeMultiplier,
    double? doubleTimeMultiplier,
    bool? applyWeeklyOvertime,
  }) {
    return OvertimeRules(
      dailyOvertimeThreshold: dailyOvertimeThreshold ?? this.dailyOvertimeThreshold,
      weeklyOvertimeThreshold: weeklyOvertimeThreshold ?? this.weeklyOvertimeThreshold,
      dailyDoubleTimeThreshold: dailyDoubleTimeThreshold ?? this.dailyDoubleTimeThreshold,
      overtimeMultiplier: overtimeMultiplier ?? this.overtimeMultiplier,
      doubleTimeMultiplier: doubleTimeMultiplier ?? this.doubleTimeMultiplier,
      applyWeeklyOvertime: applyWeeklyOvertime ?? this.applyWeeklyOvertime,
    );
  }
}
