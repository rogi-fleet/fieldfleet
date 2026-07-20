class AddressFormatter {
  static final RegExp _numericToken = RegExp(r'^\d+[A-Za-z]?$');
  static final RegExp _streetNumberPrefix = RegExp(r'^\d+[A-Za-z]?\b');
  static final RegExp _streetLikeToken = RegExp(
    r'\b(avenue|ave|road|rd|street|st|drive|dr|lane|ln|court|ct|circle|cir|crescent|cres|boulevard|blvd|place|pl|parkway|pkwy|way|trail|trl|terrace|ter|highway|hwy)\b',
    caseSensitive: false,
  );
  static final RegExp _postalLikeToken = RegExp(
    r'(^\d{5}(?:-\d{4})?$)|(^[A-Za-z]\d[A-Za-z][ -]?\d[A-Za-z]\d$)',
    caseSensitive: false,
  );
  static final RegExp _regionLikeToken = RegExp(
    r'\b(region|county|district|metro|metropolitan|area|municipality|province|state|horseshoe|eastern|western|northern|southern|northeastern|northwestern|southeastern|southwestern)\b',
    caseSensitive: false,
  );

  static String condense(String rawAddress) {
    final trimmed = rawAddress.trim();
    if (trimmed.length <= 70 || !trimmed.contains(',')) {
      return trimmed;
    }

    final parts = trimmed
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.length < 4) {
      return trimmed;
    }

    int postalIndex = -1;
    for (var i = parts.length - 1; i >= 0; i--) {
      if (_postalLikeToken.hasMatch(parts[i])) {
        postalIndex = i;
        break;
      }
    }

    var stateIndex = parts.length - 2;
    if (postalIndex > 0) {
      stateIndex = postalIndex - 1;
    }
    if (stateIndex < 1 || stateIndex >= parts.length) {
      return trimmed;
    }

    String? city;
    int? cityIndex;
    for (var i = stateIndex - 1; i >= 0; i--) {
      final candidate = parts[i];
      if (_regionLikeToken.hasMatch(candidate)) continue;
      if (_postalLikeToken.hasMatch(candidate)) continue;
      city = candidate;
      cityIndex = i;
      break;
    }
    if (city == null) {
      city = parts[stateIndex - 1];
      cityIndex = stateIndex - 1;
    }

    if (cityIndex == null || cityIndex <= 0) {
      return trimmed;
    }

    final street = _buildStreet(parts.sublist(0, cityIndex));
    if (street == null || street.isEmpty) {
      return trimmed;
    }

    final state = parts[stateIndex];
    final postal = postalIndex > 0 ? parts[postalIndex] : null;
    final locationLine = postal != null
        ? '$city, $state $postal'
        : '$city, $state';
    final condensed = '$street, $locationLine';

    return condensed.isEmpty ? trimmed : condensed;
  }

  static String? _buildStreet(List<String> prefixParts) {
    if (prefixParts.isEmpty) return null;

    for (var i = 0; i < prefixParts.length - 1; i++) {
      if (_numericToken.hasMatch(prefixParts[i]) &&
          !_postalLikeToken.hasMatch(prefixParts[i + 1])) {
        return '${prefixParts[i]} ${prefixParts[i + 1]}';
      }
    }

    for (final part in prefixParts) {
      if (_streetNumberPrefix.hasMatch(part)) {
        return part;
      }
    }

    for (final part in prefixParts) {
      if (_regionLikeToken.hasMatch(part) || _postalLikeToken.hasMatch(part)) {
        continue;
      }
      if (_streetLikeToken.hasMatch(part)) {
        return part;
      }
    }

    for (final part in prefixParts) {
      if (_regionLikeToken.hasMatch(part) || _postalLikeToken.hasMatch(part)) {
        continue;
      }
      return part;
    }

    return prefixParts.first;
  }
}
