class BetaSignupConfig {
  const BetaSignupConfig._();

  static const String creatorSignupQueryParam = 'creator_access';
  static const String _creatorSignupToken = String.fromEnvironment(
    'CREATOR_SIGNUP_TOKEN',
  );

  static bool get creatorSignupEnabled => _creatorSignupToken.isNotEmpty;

  static bool allowsSignup({required Uri uri, String? redirectTo}) {
    if (redirectTo != null && redirectTo.startsWith('/invite/')) {
      return true;
    }

    final providedToken = uri.queryParameters[creatorSignupQueryParam];
    return creatorSignupEnabled && providedToken == _creatorSignupToken;
  }
}
