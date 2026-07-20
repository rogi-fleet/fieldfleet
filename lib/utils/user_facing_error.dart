class UserFacingException implements Exception {
  final String message;
  final Object? cause;

  const UserFacingException(this.message, {this.cause});

  @override
  String toString() => message;
}

class UserFacingError {
  static String uiMessage(Object? error, {required String action}) {
    if (_usesOperationWording(action)) {
      if (error is UserFacingException) {
        return error.message;
      }

      if (error != null && _isConnectivityOrRefreshError(error)) {
        return 'Unable to continue while offline. Reconnect and try again.';
      }

      return 'There was a problem $action. Please try again.';
    }

    if (error is UserFacingException) {
      return error.message;
    }

    if (error != null && _isConnectivityOrRefreshError(error)) {
      return 'Unable to $action while offline. Reconnect and try again.';
    }

    return 'Unable to $action right now. Please try again.';
  }

  static String operationMessage(Object error, String operation) {
    if (_isConnectivityOrRefreshError(error)) {
      return 'Unable to continue while offline. Reconnect and try again.';
    }

    return 'There was a problem $operation. Please try again.';
  }

  static String projectLoadMessage(Object error) {
    if (_isConnectivityOrRefreshError(error)) {
      return 'Unable to load this project while offline. Reconnect and try again.';
    }

    return 'Unable to load this project right now. Please try again.';
  }

  static bool _isConnectivityOrRefreshError(Object error) {
    final message = error.toString().toLowerCase();

    return message.contains('authretryablefetchexception') ||
        message.contains('failed to fetch') ||
        message.contains('clientexception') ||
        message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection reset by peer') ||
        message.contains('connection closed') ||
        message.contains('connection refused') ||
        message.contains('/auth/v1/token?grant_type=refresh_token');
  }

  static bool _usesOperationWording(String action) {
    final normalized = action.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final firstWord = normalized.split(RegExp(r'\s+')).first;
    return firstWord.endsWith('ing');
  }
}
