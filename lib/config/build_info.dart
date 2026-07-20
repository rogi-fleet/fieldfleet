class BuildInfo {
  const BuildInfo._();

  static const String version = String.fromEnvironment(
    'TF_BUILD_VERSION',
    defaultValue: 'dev',
  );

  static const String sha = String.fromEnvironment(
    'TF_BUILD_SHA',
    defaultValue: '',
  );

  static const String builtAt = String.fromEnvironment(
    'TF_BUILD_DATE',
    defaultValue: '',
  );

  static String get shortSha {
    if (sha.isEmpty) return 'local';
    return sha.length > 8 ? sha.substring(0, 8) : sha;
  }

  static String get indicatorLabel {
    final cleanVersion = version.trim();
    if (cleanVersion.isEmpty || cleanVersion == 'dev') {
      return shortSha;
    }
    return '$cleanVersion+$shortSha';
  }

  static String get fullLabel {
    final parts = <String>[
      'Version: ${version.trim().isEmpty ? 'dev' : version.trim()}',
      'Build: $shortSha',
    ];
    if (builtAt.trim().isNotEmpty) {
      parts.add('Built: ${builtAt.trim()}');
    }
    return parts.join('\n');
  }
}
