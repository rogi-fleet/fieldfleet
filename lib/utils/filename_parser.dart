class FilenameParser {
  /// Extracts sheet number from filename
  /// Examples: "A-1_Floor_Plan.pdf" → "A-1", "E-2.1_Electrical.pdf" → "E-2.1"
  static String? extractSheetNumber(String filename) {
    // Remove file extension
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]+$'), '');

    // Pattern: letter(s) + dash + number(s) + optional decimal at start or after underscore/space
    final pattern = RegExp(r'(?:^|[_\s])([A-Z]+-\d+(?:\.\d+)?)', caseSensitive: false);
    final match = pattern.firstMatch(nameWithoutExt);

    if (match != null) {
      return match.group(1)?.toUpperCase();
    }

    return null;
  }

  /// Extracts version from filename
  /// Examples: "Plan_Rev_A.pdf" → "Rev A", "Drawing_R1.pdf" → "R1", "Floor_v2.pdf" → "v2"
  static String? extractVersion(String filename) {
    // Remove file extension
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]+$'), '');

    // Patterns to match:
    // - Rev A, Rev B, Rev 1, Rev 2
    // - R1, R2, R-1, R-2
    // - v1, v2, V1, V2
    final patterns = [
      RegExp(r'Rev[\s_-]?([A-Z0-9]+)', caseSensitive: false),
      RegExp(r'R[\s_-]?(\d+)', caseSensitive: false),
      RegExp(r'v[\s_-]?(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(nameWithoutExt);
      if (match != null) {
        final fullMatch = match.group(0);
        return fullMatch;
      }
    }

    return null;
  }

  /// Extracts plan name from filename
  /// Removes sheet number, version, and file extension, then formats nicely
  /// Examples: "A-1_First_Floor_Plan_Rev_A.pdf" → "First Floor Plan"
  static String extractName(String filename) {
    // Remove file extension
    String name = filename.replaceAll(RegExp(r'\.[^.]+$'), '');

    // Remove sheet number if present
    final sheetNumber = extractSheetNumber(filename);
    if (sheetNumber != null) {
      name = name.replaceAll(RegExp('${RegExp.escape(sheetNumber)}[_\\s-]*'), '');
    }

    // Remove version if present
    final version = extractVersion(filename);
    if (version != null) {
      name = name.replaceAll(RegExp('${RegExp.escape(version)}[_\\s-]*'), '');
    }

    // Clean up:
    // - Replace underscores and multiple spaces with single space
    // - Remove leading/trailing dashes, underscores, spaces
    // - Title case
    name = name.replaceAll('_', ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    name = name.replaceAll(RegExp(r'^[-_\s]+|[-_\s]+$'), '');
    name = name.trim();

    // Title case: capitalize first letter of each word
    if (name.isNotEmpty) {
      final words = name.split(' ');
      name = words.map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    return name.isNotEmpty ? name : filename;
  }

  /// Parse all metadata from filename
  static FilenameMetadata parse(String filename) {
    return FilenameMetadata(
      sheetNumber: extractSheetNumber(filename),
      version: extractVersion(filename),
      name: extractName(filename),
    );
  }
}

class FilenameMetadata {
  final String? sheetNumber;
  final String? version;
  final String name;

  FilenameMetadata({
    this.sheetNumber,
    this.version,
    required this.name,
  });
}
