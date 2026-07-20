String sanitizeStoragePathSegment(String value, {String fallback = 'file'}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  final whitespaceNormalized = trimmed.replaceAll(RegExp(r'\s+'), '_');
  final safeCharactersOnly = whitespaceNormalized.replaceAll(
    RegExp(r'[^A-Za-z0-9._-]'),
    '_',
  );
  final collapsedUnderscores = safeCharactersOnly.replaceAll(
    RegExp(r'_+'),
    '_',
  );
  final cleaned = collapsedUnderscores.replaceAll(
    RegExp(r'^[._-]+|[._-]+$'),
    '',
  );

  return cleaned.isEmpty ? fallback : cleaned;
}

String buildUniqueStorageFileName(
  String originalFileName, {
  required int timestampMs,
  String fallbackBase = 'file',
}) {
  final trimmed = originalFileName.trim();
  final lastDot = trimmed.lastIndexOf('.');
  final hasExtension = lastDot > 0 && lastDot < trimmed.length - 1;

  final rawBaseName = hasExtension ? trimmed.substring(0, lastDot) : trimmed;
  final rawExtension = hasExtension ? trimmed.substring(lastDot + 1) : '';

  final safeBaseName = sanitizeStoragePathSegment(
    rawBaseName,
    fallback: fallbackBase,
  );
  final safeExtension = sanitizeStoragePathSegment(rawExtension, fallback: '');

  if (safeExtension.isEmpty) {
    return '${safeBaseName}_$timestampMs';
  }

  return '${safeBaseName}_$timestampMs.$safeExtension';
}
