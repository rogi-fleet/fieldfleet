import 'package:cloud_firestore/cloud_firestore.dart';
import 'price_type.dart';
import 'cost_plus_type.dart';
import 'job_type.dart';

enum ProjectStatus {
  lead,
  bidding,
  proposalSent,
  awarded,
  active,
  onHold,
  complete,
  lost,
  canceled;

  String get displayName {
    switch (this) {
      case ProjectStatus.lead:
        return 'Lead';
      case ProjectStatus.bidding:
        return 'Bidding';
      case ProjectStatus.proposalSent:
        return 'Proposal Sent';
      case ProjectStatus.awarded:
        return 'Awarded';
      case ProjectStatus.active:
        return 'Active';
      case ProjectStatus.onHold:
        return 'On Hold';
      case ProjectStatus.complete:
        return 'Complete';
      case ProjectStatus.lost:
        return 'Lost';
      case ProjectStatus.canceled:
        return 'Canceled';
    }
  }

  String get shortDescription {
    switch (this) {
      case ProjectStatus.lead:
        return 'New opportunity';
      case ProjectStatus.bidding:
        return 'Preparing pricing';
      case ProjectStatus.proposalSent:
        return 'Quote sent';
      case ProjectStatus.awarded:
        return 'Won, not started';
      case ProjectStatus.active:
        return 'Work in progress';
      case ProjectStatus.onHold:
        return 'Temporarily paused';
      case ProjectStatus.complete:
        return 'Work finished';
      case ProjectStatus.lost:
        return 'Opportunity not won';
      case ProjectStatus.canceled:
        return 'Stopped or withdrawn';
    }
  }

  /// The database column uses snake_case values.
  String get dbValue {
    switch (this) {
      case ProjectStatus.proposalSent:
        return 'proposal_sent';
      case ProjectStatus.onHold:
        return 'on_hold';
      default:
        return name;
    }
  }

  static ProjectStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'lead':
        return ProjectStatus.lead;
      case 'bidding':
        return ProjectStatus.bidding;
      case 'proposal_sent':
      case 'proposalsent':
        return ProjectStatus.proposalSent;
      case 'awarded':
        return ProjectStatus.awarded;
      case 'active':
        return ProjectStatus.active;
      case 'on_hold':
      case 'onhold':
        return ProjectStatus.onHold;
      case 'complete':
        return ProjectStatus.complete;
      case 'lost':
        return ProjectStatus.lost;
      case 'canceled':
        return ProjectStatus.canceled;
      default:
        throw ArgumentError('Invalid project status: $status');
    }
  }

  /// Whether this status represents an "open" project (work may happen).
  bool get isOpen => this == active || this == onHold || this == awarded;

  /// Whether this status represents a pre-sale pipeline stage.
  bool get isPipeline =>
      this == lead || this == bidding || this == proposalSent;

  /// Whether this status is a terminal state.
  bool get isClosed => this == complete || this == lost || this == canceled;

  /// Whether the estimate has been approved (quote approved, sent, or signed).
  bool get isEstimateApproved =>
      this == proposalSent ||
      this == awarded ||
      this == active ||
      this == onHold ||
      this == complete ||
      this == canceled;
}

enum ProjectUpdateField {
  clientId,
  estimatedBudget,
  startDate,
  targetCompletionDate,
  latitude,
  longitude,
  geofenceRadiusMeters,
  requireGeofenceValidation,
  allowClockInOutsideGeofence,
  photoUrl,
  contractAmount,
  costPlusType,
  costPlusValue,
  description,
  projectManagerId,
  jobType,
  purchaseOrderNumber,
  dateRequestReceived,
  locationDetails,
  salespersonId,
  supervisorId,
  primaryContactName,
  customerName,
  primaryContactRole,
  primaryContactPhone,
  primaryContactEmail,
  serialNumber,
  customerLocationId,
  vendorSubdivisionId,
  customFields,
}

class Project {
  final String id;
  final String workspaceId;
  final String name;
  final String address;
  final ProjectStatus status;
  final String? clientId;
  final double? estimatedBudget;
  final double materialMarkupPercent;
  final double laborMarkupPercent;
  final DateTime? startDate;
  final DateTime? targetCompletionDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Geocoding fields
  final double? latitude;
  final double? longitude;

  // Project photo
  final String? photoUrl;

  // Price type fields
  final PriceType priceType;
  final double? contractAmount; // Required for fixed price
  final CostPlusType? costPlusType; // Required for cost plus
  final double?
  costPlusValue; // Required for cost plus (percentage or fixed fee amount)
  final String? description;
  final String? projectManagerId;

  // Enhanced project fields
  final JobType? jobType;
  final String? purchaseOrderNumber;
  final DateTime? dateRequestReceived;
  final String? locationDetails; // Sub-location within address
  final String? salespersonId;
  final String? supervisorId;

  // Primary contact fields
  final String? primaryContactName;
  final String? customerName;
  final String? primaryContactRole;
  final String? primaryContactPhone;
  final String? primaryContactEmail;
  final String? serialNumber;

  // Customer location link
  final String? customerLocationId;

  // Vendor subdivision link
  final String? vendorSubdivisionId;

  // Team members assigned to this project
  final List<String> teamMemberIds;

  // Geofencing settings
  final int geofenceRadiusMeters;
  final bool requireGeofenceValidation;
  final bool allowClockInOutsideGeofence;

  /// Default holdback (retainage) percent to suggest when creating invoices
  /// for this project. 0 = no default.
  final double holdbackDefaultPercent;

  /// Workspace admin-defined custom field values, keyed by
  /// [CustomFieldDefinition.key]. Empty when the workspace has no
  /// custom fields defined or none are populated.
  final Map<String, dynamic> customFields;

  Project({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.address,
    required this.status,
    this.clientId,
    this.estimatedBudget,
    this.materialMarkupPercent = 20.0,
    this.laborMarkupPercent = 30.0,
    this.startDate,
    this.targetCompletionDate,
    required this.createdAt,
    required this.updatedAt,
    this.latitude,
    this.longitude,
    this.photoUrl,
    this.priceType = PriceType.timeAndMaterial,
    this.contractAmount,
    this.costPlusType,
    this.costPlusValue,
    this.description,
    this.projectManagerId,
    this.jobType,
    this.purchaseOrderNumber,
    this.dateRequestReceived,
    this.locationDetails,
    this.salespersonId,
    this.supervisorId,
    this.primaryContactName,
    this.customerName,
    this.primaryContactRole,
    this.primaryContactPhone,
    this.primaryContactEmail,
    this.serialNumber,
    this.customerLocationId,
    this.vendorSubdivisionId,
    this.teamMemberIds = const [],
    this.geofenceRadiusMeters = 500,
    this.requireGeofenceValidation = false,
    this.allowClockInOutsideGeofence = true,
    this.holdbackDefaultPercent = 0,
    this.customFields = const {},
  });

  factory Project.fromJson(Map<String, dynamic> json, String id) {
    return Project(
      id: id,
      workspaceId: json['workspaceId'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      status: ProjectStatus.fromString(json['status'] as String),
      clientId: json['clientId'] as String?,
      estimatedBudget: json['estimatedBudget'] != null
          ? (json['estimatedBudget'] as num).toDouble()
          : null,
      materialMarkupPercent: json['materialMarkupPercent'] != null
          ? (json['materialMarkupPercent'] as num).toDouble()
          : 20.0,
      laborMarkupPercent: json['laborMarkupPercent'] != null
          ? (json['laborMarkupPercent'] as num).toDouble()
          : 30.0,
      startDate: json['startDate'] != null
          ? (json['startDate'] as Timestamp).toDate()
          : null,
      targetCompletionDate: json['targetCompletionDate'] != null
          ? (json['targetCompletionDate'] as Timestamp).toDate()
          : null,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      photoUrl: json['photoUrl'] as String?,
      priceType: json['priceType'] != null
          ? PriceType.fromString(json['priceType'] as String)
          : PriceType.timeAndMaterial,
      contractAmount: json['contractAmount'] != null
          ? (json['contractAmount'] as num).toDouble()
          : null,
      costPlusType: json['costPlusType'] != null
          ? CostPlusType.fromString(json['costPlusType'] as String)
          : null,
      costPlusValue: json['costPlusValue'] != null
          ? (json['costPlusValue'] as num).toDouble()
          : null,
      description: json['description'] as String?,
      projectManagerId: json['projectManagerId'] as String?,
      jobType: json['jobType'] != null
          ? JobType.fromString(json['jobType'] as String)
          : null,
      purchaseOrderNumber: json['purchaseOrderNumber'] as String?,
      dateRequestReceived: json['dateRequestReceived'] != null
          ? (json['dateRequestReceived'] as Timestamp).toDate()
          : null,
      locationDetails: json['locationDetails'] as String?,
      salespersonId: json['salespersonId'] as String?,
      supervisorId: json['supervisorId'] as String?,
      primaryContactName: json['primaryContactName'] as String?,
      customerName: json['customerName'] as String?,
      primaryContactRole: json['primaryContactRole'] as String?,
      primaryContactPhone: json['primaryContactPhone'] as String?,
      primaryContactEmail: json['primaryContactEmail'] as String?,
      serialNumber: json['serialNumber'] as String?,
      customerLocationId: json['customerLocationId'] as String?,
      vendorSubdivisionId: json['vendorSubdivisionId'] as String?,
      teamMemberIds:
          (json['teamMemberIds'] as List<dynamic>?)?.cast<String>() ?? [],
      geofenceRadiusMeters: json['geofenceRadiusMeters'] as int? ?? 500,
      requireGeofenceValidation:
          json['requireGeofenceValidation'] as bool? ?? false,
      allowClockInOutsideGeofence:
          json['allowClockInOutsideGeofence'] as bool? ?? true,
      holdbackDefaultPercent: json['holdbackDefaultPercent'] != null
          ? (json['holdbackDefaultPercent'] as num).toDouble()
          : 0,
      customFields: (json['customFields'] as Map?)?.cast<String, dynamic>() ??
          const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'address': address,
      'status': status.dbValue,
      'clientId': clientId,
      'estimatedBudget': estimatedBudget,
      'materialMarkupPercent': materialMarkupPercent,
      'laborMarkupPercent': laborMarkupPercent,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'targetCompletionDate': targetCompletionDate != null
          ? Timestamp.fromDate(targetCompletionDate!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'latitude': latitude,
      'longitude': longitude,
      'photoUrl': photoUrl,
      'priceType': priceType.toString(),
      'contractAmount': contractAmount,
      'costPlusType': costPlusType?.toString(),
      'costPlusValue': costPlusValue,
      'description': description,
      'projectManagerId': projectManagerId,
      'jobType': jobType?.toJson(),
      'purchaseOrderNumber': purchaseOrderNumber,
      'dateRequestReceived': dateRequestReceived != null
          ? Timestamp.fromDate(dateRequestReceived!)
          : null,
      'locationDetails': locationDetails,
      'salespersonId': salespersonId,
      'supervisorId': supervisorId,
      'primaryContactName': primaryContactName,
      'customerName': customerName,
      'primaryContactRole': primaryContactRole,
      'primaryContactPhone': primaryContactPhone,
      'primaryContactEmail': primaryContactEmail,
      'serialNumber': serialNumber,
      'customerLocationId': customerLocationId,
      'vendorSubdivisionId': vendorSubdivisionId,
      'teamMemberIds': teamMemberIds,
      'geofenceRadiusMeters': geofenceRadiusMeters,
      'requireGeofenceValidation': requireGeofenceValidation,
      'allowClockInOutsideGeofence': allowClockInOutsideGeofence,
      'holdbackDefaultPercent': holdbackDefaultPercent,
      'customFields': customFields,
    };
  }

  Project copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? address,
    ProjectStatus? status,
    String? clientId,
    double? estimatedBudget,
    double? materialMarkupPercent,
    double? laborMarkupPercent,
    DateTime? startDate,
    DateTime? targetCompletionDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? latitude,
    double? longitude,
    String? photoUrl,
    PriceType? priceType,
    double? contractAmount,
    CostPlusType? costPlusType,
    double? costPlusValue,
    String? description,
    String? projectManagerId,
    JobType? jobType,
    String? purchaseOrderNumber,
    DateTime? dateRequestReceived,
    String? locationDetails,
    String? salespersonId,
    String? supervisorId,
    String? primaryContactName,
    String? customerName,
    String? primaryContactRole,
    String? primaryContactPhone,
    String? primaryContactEmail,
    String? serialNumber,
    String? customerLocationId,
    String? vendorSubdivisionId,
    List<String>? teamMemberIds,
    int? geofenceRadiusMeters,
    bool? requireGeofenceValidation,
    bool? allowClockInOutsideGeofence,
    double? holdbackDefaultPercent,
    Map<String, dynamic>? customFields,
  }) {
    return Project(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      address: address ?? this.address,
      status: status ?? this.status,
      clientId: clientId ?? this.clientId,
      estimatedBudget: estimatedBudget ?? this.estimatedBudget,
      materialMarkupPercent:
          materialMarkupPercent ?? this.materialMarkupPercent,
      laborMarkupPercent: laborMarkupPercent ?? this.laborMarkupPercent,
      startDate: startDate ?? this.startDate,
      targetCompletionDate: targetCompletionDate ?? this.targetCompletionDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      photoUrl: photoUrl ?? this.photoUrl,
      priceType: priceType ?? this.priceType,
      contractAmount: contractAmount ?? this.contractAmount,
      costPlusType: costPlusType ?? this.costPlusType,
      costPlusValue: costPlusValue ?? this.costPlusValue,
      description: description ?? this.description,
      projectManagerId: projectManagerId ?? this.projectManagerId,
      jobType: jobType ?? this.jobType,
      purchaseOrderNumber: purchaseOrderNumber ?? this.purchaseOrderNumber,
      dateRequestReceived: dateRequestReceived ?? this.dateRequestReceived,
      locationDetails: locationDetails ?? this.locationDetails,
      salespersonId: salespersonId ?? this.salespersonId,
      supervisorId: supervisorId ?? this.supervisorId,
      primaryContactName: primaryContactName ?? this.primaryContactName,
      customerName: customerName ?? this.customerName,
      primaryContactRole: primaryContactRole ?? this.primaryContactRole,
      primaryContactPhone: primaryContactPhone ?? this.primaryContactPhone,
      primaryContactEmail: primaryContactEmail ?? this.primaryContactEmail,
      serialNumber: serialNumber ?? this.serialNumber,
      customerLocationId: customerLocationId ?? this.customerLocationId,
      vendorSubdivisionId: vendorSubdivisionId ?? this.vendorSubdivisionId,
      teamMemberIds: teamMemberIds ?? this.teamMemberIds,
      geofenceRadiusMeters: geofenceRadiusMeters ?? this.geofenceRadiusMeters,
      requireGeofenceValidation:
          requireGeofenceValidation ?? this.requireGeofenceValidation,
      allowClockInOutsideGeofence:
          allowClockInOutsideGeofence ?? this.allowClockInOutsideGeofence,
      holdbackDefaultPercent:
          holdbackDefaultPercent ?? this.holdbackDefaultPercent,
      customFields: customFields ?? this.customFields,
    );
  }

  bool validate() {
    return name.isNotEmpty && address.isNotEmpty;
  }

  /// Calculate total project duration in days
  int get totalDays {
    if (startDate == null || targetCompletionDate == null) {
      return 0;
    }
    return targetCompletionDate!.difference(startDate!).inDays;
  }

  /// Check if project is overdue
  bool isOverdue() {
    if (targetCompletionDate == null || status.isClosed) {
      return false;
    }
    return targetCompletionDate!.isBefore(DateTime.now());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
