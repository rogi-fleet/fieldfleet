enum OpportunityStage {
  newLead,
  qualified,
  proposal,
  negotiation,
  won,
  lost;

  String get dbValue => switch (this) {
        OpportunityStage.newLead => 'new',
        OpportunityStage.qualified => 'qualified',
        OpportunityStage.proposal => 'proposal',
        OpportunityStage.negotiation => 'negotiation',
        OpportunityStage.won => 'won',
        OpportunityStage.lost => 'lost',
      };

  String get displayName => switch (this) {
        OpportunityStage.newLead => 'New',
        OpportunityStage.qualified => 'Qualified',
        OpportunityStage.proposal => 'Proposal',
        OpportunityStage.negotiation => 'Negotiation',
        OpportunityStage.won => 'Won',
        OpportunityStage.lost => 'Lost',
      };

  bool get isClosed =>
      this == OpportunityStage.won || this == OpportunityStage.lost;

  static OpportunityStage fromDb(String? value) {
    switch (value) {
      case 'new':
        return OpportunityStage.newLead;
      case 'qualified':
        return OpportunityStage.qualified;
      case 'proposal':
        return OpportunityStage.proposal;
      case 'negotiation':
        return OpportunityStage.negotiation;
      case 'won':
        return OpportunityStage.won;
      case 'lost':
        return OpportunityStage.lost;
      default:
        return OpportunityStage.newLead;
    }
  }
}

class Opportunity {
  final String id;
  final String workspaceId;
  final String? customerId;
  final String? projectId;
  final String? ownerId;
  final String name;
  final String? description;
  final OpportunityStage stage;
  final String? source;
  final double estimatedValue;
  final int probability; // 0..100
  final DateTime? expectedCloseDate;
  final DateTime? actualCloseDate;
  final String? lostReason;
  final String? nextAction;
  final DateTime? nextActionAt;
  final List<String> tags;
  final bool isActive;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Opportunity({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.stage,
    required this.estimatedValue,
    required this.probability,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.customerId,
    this.projectId,
    this.ownerId,
    this.description,
    this.source,
    this.expectedCloseDate,
    this.actualCloseDate,
    this.lostReason,
    this.nextAction,
    this.nextActionAt,
    this.tags = const [],
    this.createdBy,
  });

  double get weightedValue => estimatedValue * probability / 100.0;

  factory Opportunity.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return Opportunity(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String,
      customerId: map['customer_id'] as String?,
      projectId: map['project_id'] as String?,
      ownerId: map['owner_id'] as String?,
      name: (map['name'] ?? '') as String,
      description: map['description'] as String?,
      stage: OpportunityStage.fromDb(map['stage'] as String?),
      source: map['source'] as String?,
      estimatedValue: (map['estimated_value'] as num?)?.toDouble() ?? 0,
      probability: (map['probability'] as num?)?.toInt() ?? 50,
      expectedCloseDate: parseDate(map['expected_close_date']),
      actualCloseDate: parseDate(map['actual_close_date']),
      lostReason: map['lost_reason'] as String?,
      nextAction: map['next_action'] as String?,
      nextActionAt: parseDate(map['next_action_at']),
      tags: ((map['tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      isActive: (map['is_active'] as bool?) ?? true,
      createdBy: map['created_by'] as String?,
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: parseDate(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'workspace_id': workspaceId,
        if (customerId != null) 'customer_id': customerId,
        if (projectId != null) 'project_id': projectId,
        if (ownerId != null) 'owner_id': ownerId,
        'name': name,
        if (description != null) 'description': description,
        'stage': stage.dbValue,
        if (source != null) 'source': source,
        'estimated_value': estimatedValue,
        'probability': probability,
        if (expectedCloseDate != null)
          'expected_close_date':
              expectedCloseDate!.toIso8601String().substring(0, 10),
        if (lostReason != null) 'lost_reason': lostReason,
        if (nextAction != null) 'next_action': nextAction,
        if (nextActionAt != null)
          'next_action_at': nextActionAt!.toIso8601String(),
        'tags': tags,
        'is_active': isActive,
        if (createdBy != null) 'created_by': createdBy,
      };

  Opportunity copyWith({
    String? customerId,
    String? ownerId,
    String? name,
    String? description,
    OpportunityStage? stage,
    String? source,
    double? estimatedValue,
    int? probability,
    DateTime? expectedCloseDate,
    String? lostReason,
    String? nextAction,
    DateTime? nextActionAt,
    List<String>? tags,
    bool? isActive,
  }) =>
      Opportunity(
        id: id,
        workspaceId: workspaceId,
        customerId: customerId ?? this.customerId,
        projectId: projectId,
        ownerId: ownerId ?? this.ownerId,
        name: name ?? this.name,
        description: description ?? this.description,
        stage: stage ?? this.stage,
        source: source ?? this.source,
        estimatedValue: estimatedValue ?? this.estimatedValue,
        probability: probability ?? this.probability,
        expectedCloseDate: expectedCloseDate ?? this.expectedCloseDate,
        actualCloseDate: actualCloseDate,
        lostReason: lostReason ?? this.lostReason,
        nextAction: nextAction ?? this.nextAction,
        nextActionAt: nextActionAt ?? this.nextActionAt,
        tags: tags ?? this.tags,
        isActive: isActive ?? this.isActive,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
