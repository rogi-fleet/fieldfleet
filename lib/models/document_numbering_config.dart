/// Workspace-level configuration for document numbering format.
class DocumentNumberingConfig {
  final String id;
  final String workspaceId;
  final String documentType;
  final String prefix;
  final int paddingWidth;
  final String separator;

  const DocumentNumberingConfig({
    required this.id,
    required this.workspaceId,
    required this.documentType,
    required this.prefix,
    this.paddingWidth = 3,
    this.separator = '-',
  });

  factory DocumentNumberingConfig.fromJson(Map<String, dynamic> json) {
    return DocumentNumberingConfig(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      documentType: json['document_type'] as String,
      prefix: json['prefix'] as String,
      paddingWidth: json['padding_width'] as int? ?? 3,
      separator: json['separator'] as String? ?? '-',
    );
  }

  Map<String, dynamic> toJson() => {
    'workspace_id': workspaceId,
    'document_type': documentType,
    'prefix': prefix,
    'padding_width': paddingWidth,
    'separator': separator,
  };

  DocumentNumberingConfig copyWith({
    String? prefix,
    int? paddingWidth,
    String? separator,
  }) {
    return DocumentNumberingConfig(
      id: id,
      workspaceId: workspaceId,
      documentType: documentType,
      prefix: prefix ?? this.prefix,
      paddingWidth: paddingWidth ?? this.paddingWidth,
      separator: separator ?? this.separator,
    );
  }

  /// Format a number using this config's prefix, separator, and padding.
  String format(int number) {
    final numberStr = number.toString().padLeft(paddingWidth, '0');
    return '$prefix$separator$numberStr';
  }
}
