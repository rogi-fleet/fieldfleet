enum DocumentStatus {
  draft,
  sent,
  viewed,
  signed,
  denied,
  changesRequested,
  pending,
  approved,
  responded,
  applied,
  notSelected,
  withdrawn,
}

extension DocumentStatusExtension on DocumentStatus {
  String get displayName {
    switch (this) {
      case DocumentStatus.draft:
        return 'Draft';
      case DocumentStatus.sent:
        return 'Sent';
      case DocumentStatus.viewed:
        return 'Viewed';
      case DocumentStatus.signed:
        return 'Signed';
      case DocumentStatus.denied:
        return 'Denied';
      case DocumentStatus.changesRequested:
        return 'Changes Requested';
      case DocumentStatus.pending:
        return 'Awaiting Approval';
      case DocumentStatus.approved:
        return 'Approved';
      case DocumentStatus.responded:
        return 'Bid Received';
      case DocumentStatus.applied:
        return 'Applied';
      case DocumentStatus.notSelected:
        return 'Not Selected';
      case DocumentStatus.withdrawn:
        return 'Withdrawn';
    }
  }

  /// The database value for this status (snake_case).
  String get dbValue {
    switch (this) {
      case DocumentStatus.changesRequested:
        return 'changes_requested';
      case DocumentStatus.notSelected:
        return 'not_selected';
      default:
        return name;
    }
  }

  /// Parse a database status string to enum value.
  static DocumentStatus fromDbValue(String? value) {
    if (value == null) return DocumentStatus.draft;
    if (value == 'changes_requested') return DocumentStatus.changesRequested;
    if (value == 'not_selected') return DocumentStatus.notSelected;
    return DocumentStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DocumentStatus.draft,
    );
  }

  String get icon {
    switch (this) {
      case DocumentStatus.draft:
        return 'edit';
      case DocumentStatus.sent:
        return 'send';
      case DocumentStatus.viewed:
        return 'visibility';
      case DocumentStatus.signed:
        return 'check_circle';
      case DocumentStatus.denied:
        return 'cancel';
      case DocumentStatus.changesRequested:
        return 'edit_note';
      case DocumentStatus.pending:
        return 'hourglass_empty';
      case DocumentStatus.approved:
        return 'verified';
      case DocumentStatus.responded:
        return 'mark_email_read';
      case DocumentStatus.applied:
        return 'done_all';
      case DocumentStatus.notSelected:
        return 'block';
      case DocumentStatus.withdrawn:
        return 'do_not_disturb_on';
    }
  }
}
