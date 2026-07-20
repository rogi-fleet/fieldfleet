class SpecSection {
  final String id;
  final String workspaceId;
  final String bookId;
  final String? parentId;
  final String? code;
  final String title;
  final String? body;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SpecSection({
    required this.id,
    required this.workspaceId,
    required this.bookId,
    this.parentId,
    this.code,
    required this.title,
    this.body,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SpecSection.fromMap(Map<String, dynamic> m) => SpecSection(
        id: m['id'] as String,
        workspaceId: m['workspace_id'] as String,
        bookId: m['book_id'] as String,
        parentId: m['parent_id'] as String?,
        code: m['code'] as String?,
        title: m['title'] as String,
        body: m['body'] as String?,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}

class SpecItem {
  final String id;
  final String workspaceId;
  final String bookId;
  final String sectionId;
  final String? itemNo;
  final String description;
  final String? manufacturer;
  final String? model;
  final num? qty;
  final String? unit;
  final String? notes;
  final int sortOrder;

  const SpecItem({
    required this.id,
    required this.workspaceId,
    required this.bookId,
    required this.sectionId,
    this.itemNo,
    required this.description,
    this.manufacturer,
    this.model,
    this.qty,
    this.unit,
    this.notes,
    required this.sortOrder,
  });

  factory SpecItem.fromMap(Map<String, dynamic> m) => SpecItem(
        id: m['id'] as String,
        workspaceId: m['workspace_id'] as String,
        bookId: m['book_id'] as String,
        sectionId: m['section_id'] as String,
        itemNo: m['item_no'] as String?,
        description: m['description'] as String,
        manufacturer: m['manufacturer'] as String?,
        model: m['model'] as String?,
        qty: m['qty'] as num?,
        unit: m['unit'] as String?,
        notes: m['notes'] as String?,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class SpecSignoff {
  final String id;
  final String bookId;
  final int versionAtSign;
  final String signerName;
  final String? signerEmail;
  final String? signerRole;
  final String? signatureText;
  final DateTime signedAt;
  final String? notes;

  const SpecSignoff({
    required this.id,
    required this.bookId,
    required this.versionAtSign,
    required this.signerName,
    this.signerEmail,
    this.signerRole,
    this.signatureText,
    required this.signedAt,
    this.notes,
  });

  factory SpecSignoff.fromMap(Map<String, dynamic> m) => SpecSignoff(
        id: m['id'] as String,
        bookId: m['book_id'] as String,
        versionAtSign: (m['version_at_sign'] as num).toInt(),
        signerName: m['signer_name'] as String,
        signerEmail: m['signer_email'] as String?,
        signerRole: m['signer_role'] as String?,
        signatureText: m['signature_text'] as String?,
        signedAt: DateTime.parse(m['signed_at'] as String),
        notes: m['notes'] as String?,
      );
}
