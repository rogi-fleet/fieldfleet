String singularProjectTerminology(String pluralTerminology) {
  final trimmed = pluralTerminology.trim();
  if (trimmed.endsWith('s') && trimmed.length > 1) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

String projectTerminologyForCount(int count, String pluralTerminology) {
  return count == 1
      ? singularProjectTerminology(pluralTerminology)
      : pluralTerminology;
}

/// Rewrites a fixed UI label that hardcodes the word "Project"/"Projects" so it
/// reflects the workspace's configured terminology. Used for labels stored as
/// config identity (e.g. dashboard widget / quick-action catalogs) that must
/// keep their canonical English label but render the workspace's wording.
///
/// Substitutes the standalone words "Projects" → [pluralTerminology] and
/// "Project" → its singular, preserving the surrounding text. Both the
/// capitalised ("Project") and lower-case ("project") forms are handled so the
/// helper works on title-case labels and mid-sentence phrases alike. When the
/// terminology is the default ("Projects") the input is returned unchanged.
///
/// Only safe for app-generated fixed strings — never run it over free-form
/// user content, which could legitimately contain the word "project".
String substituteProjectTerminology(String label, String pluralTerminology) {
  final plural = pluralTerminology.trim();
  if (plural.isEmpty || plural.toLowerCase() == 'projects') return label;
  final singular = singularProjectTerminology(plural);
  return label
      .replaceAll(RegExp(r'\bProjects\b'), plural)
      .replaceAll(RegExp(r'\bProject\b'), singular)
      .replaceAll(RegExp(r'\bprojects\b'), plural.toLowerCase())
      .replaceAll(RegExp(r'\bproject\b'), singular.toLowerCase());
}
