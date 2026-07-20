enum OpportunityActivityKind {
  note,
  call,
  email,
  meeting,
  followUp,
  stageChange,
  won,
  lost;

  String get dbValue => switch (this) {
        OpportunityActivityKind.note => 'note',
        OpportunityActivityKind.call => 'call',
        OpportunityActivityKind.email => 'email',
        OpportunityActivityKind.meeting => 'meeting',
        OpportunityActivityKind.followUp => 'follow_up',
        OpportunityActivityKind.stageChange => 'stage_change',
        OpportunityActivityKind.won => 'won',
        OpportunityActivityKind.lost => 'lost',
      };

  String get displayName => switch (this) {
        OpportunityActivityKind.note => 'Note',
        OpportunityActivityKind.call => 'Call',
        OpportunityActivityKind.email => 'Email',
        OpportunityActivityKind.meeting => 'Meeting',
        OpportunityActivityKind.followUp => 'Follow-up',
        OpportunityActivityKind.stageChange => 'Stage change',
        OpportunityActivityKind.won => 'Won',
        OpportunityActivityKind.lost => 'Lost',
      };

  static OpportunityActivityKind fromDb(String? v) {
    switch (v) {
      case 'note':
        return OpportunityActivityKind.note;
      case 'call':
        return OpportunityActivityKind.call;
      case 'email':
        return OpportunityActivityKind.email;
      case 'meeting':
        return OpportunityActivityKind.meeting;
      case 'follow_up':
        return OpportunityActivityKind.followUp;
      case 'stage_change':
        return OpportunityActivityKind.stageChange;
      case 'won':
        return OpportunityActivityKind.won;
      case 'lost':
        return OpportunityActivityKind.lost;
      default:
        return OpportunityActivityKind.note;
    }
  }
}

class OpportunityActivity {
  final String id;
  final String opportunityId;
  final String workspaceId;
  final OpportunityActivityKind kind;
  final String? subject;
  final String? body;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OpportunityActivity({
    required this.id,
    required this.opportunityId,
    required this.workspaceId,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.subject,
    this.body,
    this.dueAt,
    this.completedAt,
    this.createdBy,
  });

  bool get isOpenFollowUp =>
      kind == OpportunityActivityKind.followUp && completedAt == null;

  factory OpportunityActivity.fromMap(Map<String, dynamic> m) {
    DateTime? d(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return OpportunityActivity(
      id: m['id'] as String,
      opportunityId: m['opportunity_id'] as String,
      workspaceId: m['workspace_id'] as String,
      kind: OpportunityActivityKind.fromDb(m['kind'] as String?),
      subject: m['subject'] as String?,
      body: m['body'] as String?,
      dueAt: d(m['due_at']),
      completedAt: d(m['completed_at']),
      createdBy: m['created_by'] as String?,
      createdAt: d(m['created_at']) ?? DateTime.now(),
      updatedAt: d(m['updated_at']) ?? DateTime.now(),
    );
  }
}
