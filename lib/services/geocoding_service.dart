import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/app_logger.dart';
import '../utils/address_formatter.dart';

class AddressSuggestion {
  static final RegExp _streetNumberPrefix = RegExp(r'^\d+[A-Za-z]?\b');
  static final RegExp _leadingStreetNumber = RegExp(r'^\s*(\d+[A-Za-z]?)\b');
  static const Map<String, String> _streetTokenNormalizations = {
    'ave': 'avenue',
    'av': 'avenue',
    'blvd': 'boulevard',
    'cir': 'circle',
    'cres': 'crescent',
    'ct': 'court',
    'dr': 'drive',
    'hwy': 'highway',
    'ln': 'lane',
    'pkwy': 'parkway',
    'pl': 'place',
    'rd': 'road',
    'n': 'north',
    's': 'south',
    'e': 'east',
    'w': 'west',
    'ne': 'northeast',
    'nw': 'northwest',
    'se': 'southeast',
    'sw': 'southwest',
    'st': 'street',
    'ter': 'terrace',
    'trl': 'trail',
  };

  final String displayName;
  final double latitude;
  final double longitude;
  final String? street;
  final String? city;
  final String? state;
  final String? postcode;
  final String? country;
  final String? countryCode;

  const AddressSuggestion({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.street,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.countryCode,
  });

  String singleLineAddress({String? typedQuery}) {
    final displayStreet = _streetWithTypedNumber(typedQuery);
    final parts = <String>[];

    if (displayStreet != null && displayStreet.isNotEmpty) {
      parts.add(displayStreet);
    }

    final cityPart = city?.trim();
    if (cityPart != null && cityPart.isNotEmpty) {
      parts.add(cityPart);
    }

    final statePart = state?.trim();
    final postcodePart = postcode?.trim();
    final statePostal = [
      if (statePart != null && statePart.isNotEmpty) statePart,
      if (postcodePart != null && postcodePart.isNotEmpty) postcodePart,
    ].join(' ');
    if (statePostal.isNotEmpty) {
      parts.add(statePostal);
    }

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    return AddressFormatter.condense(displayName);
  }

  String? _streetWithTypedNumber(String? typedQuery) {
    final baseStreet = street?.trim();
    if (baseStreet == null || baseStreet.isEmpty) return null;
    if (_streetNumberPrefix.hasMatch(baseStreet)) return baseStreet;

    final query = typedQuery?.trim();
    if (query == null || query.isEmpty) return baseStreet;

    final numberMatch = _leadingStreetNumber.firstMatch(query);
    if (numberMatch == null) return baseStreet;

    final typedStreet =
        query.substring(numberMatch.end).replaceFirst(RegExp(r'^[,\s-]+'), '');
    if (typedStreet.isEmpty) return baseStreet;

    if (_normalizeStreetName(typedStreet) != _normalizeStreetName(baseStreet)) {
      return baseStreet;
    }

    final houseNumber = numberMatch.group(1);
    if (houseNumber == null || houseNumber.isEmpty) return baseStreet;
    return '$houseNumber $baseStreet';
  }

  static String _normalizeStreetName(String value) {
    final cleaned = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .map((token) => _streetTokenNormalizations[token] ?? token)
        .join(' ')
        .trim();
    return cleaned;
  }
}

/// Service for geocoding addresses using OpenStreetMap Nominatim API.
class GeocodingService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const String _userAgent = 'FieldFleet/1.0';

  // Rate limiting: Nominatim allows 1 request per second
  static DateTime? _lastRequestTime;
  static const Duration _minTimeBetweenRequests = Duration(seconds: 1);

  /// Geocode an address to latitude/longitude coordinates
  ///
  /// Returns a map with 'latitude' and 'longitude' keys, or null if geocoding fails
  Future<({double latitude, double longitude})?> geocodeAddress(
    String address,
  ) async {
    try {
      // Rate limiting: ensure at least 1 second between requests
      if (_lastRequestTime != null) {
        final timeSinceLastRequest = DateTime.now().difference(
          _lastRequestTime!,
        );
        if (timeSinceLastRequest < _minTimeBetweenRequests) {
          final waitTime = _minTimeBetweenRequests - timeSinceLastRequest;
          AppLogger.debug(
            'Rate limiting: waiting ${waitTime.inMilliseconds}ms',
          );
          await Future.delayed(waitTime);
        }
      }

      _lastRequestTime = DateTime.now();

      // Build the request URL
      final queryParams = {
        'q': address,
        'format': 'json',
        'limit': '1',
        'addressdetails': '1',
      };

      final uri = Uri.parse(
        '$_baseUrl/search',
      ).replace(queryParameters: queryParams);

      AppLogger.debug(
        'Geocoding address',
        metadata: {'address': address, 'url': uri.toString()},
      );

      // Make the HTTP request
      final response = await http.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        AppLogger.warning(
          'Geocoding request failed',
          metadata: {'statusCode': response.statusCode, 'address': address},
        );
        return null;
      }

      // Parse the response
      final List<dynamic> results = json.decode(response.body);

      if (results.isEmpty) {
        AppLogger.info(
          'No geocoding results found',
          metadata: {'address': address},
        );
        return null;
      }

      final result = results[0];
      final latitude = double.parse(result['lat'] as String);
      final longitude = double.parse(result['lon'] as String);

      if (latitude.isNaN || longitude.isNaN) return null;

      AppLogger.info(
        'Geocoding successful',
        metadata: {
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
        },
      );

      return (latitude: latitude, longitude: longitude);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Geocoding failed',
        error: e,
        stackTrace: stackTrace,
        metadata: {'address': address},
      );
      return null;
    }
  }

  /// Returns address suggestions for autocomplete.
  ///
  /// If [countryCode] is provided (ISO 3166-1 alpha-2, e.g. 'US'),
  /// results are restricted to that country so local addresses appear first.
  Future<List<AddressSuggestion>> searchAddressSuggestions(
    String query, {
    int limit = 5,
    String? countryCode,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 3) return const [];

    try {
      if (_lastRequestTime != null) {
        final timeSinceLastRequest = DateTime.now().difference(
          _lastRequestTime!,
        );
        if (timeSinceLastRequest < _minTimeBetweenRequests) {
          final waitTime = _minTimeBetweenRequests - timeSinceLastRequest;
          await Future.delayed(waitTime);
        }
      }

      _lastRequestTime = DateTime.now();

      final queryParams = {
        'q': trimmedQuery,
        'format': 'json',
        'limit': limit.toString(),
        'addressdetails': '1',
        if (countryCode != null && countryCode.isNotEmpty)
          'countrycodes': countryCode.toLowerCase(),
      };

      final uri = Uri.parse(
        '$_baseUrl/search',
      ).replace(queryParameters: queryParams);
      final response = await http.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return const [];
      }

      final List<dynamic> results = json.decode(response.body);
      return results
          .whereType<Map<String, dynamic>>()
          .map((result) {
            final displayName = result['display_name'] as String?;
            final lat = result['lat'] as String?;
            final lon = result['lon'] as String?;
            if (displayName == null || lat == null || lon == null) return null;
            final parsedLat = double.tryParse(lat);
            final parsedLon = double.tryParse(lon);
            if (parsedLat == null || parsedLon == null) return null;

            final addr = result['address'] as Map<String, dynamic>?;
            String? street;
            if (addr != null) {
              final road = addr['road'] as String?;
              final houseNumber = addr['house_number'] as String?;
              if (road != null) {
                street = houseNumber != null ? '$houseNumber $road' : road;
              }
            }

            return AddressSuggestion(
              displayName: displayName,
              latitude: parsedLat,
              longitude: parsedLon,
              street: street,
              city: addr?['city'] as String? ??
                  addr?['town'] as String? ??
                  addr?['village'] as String?,
              state: addr?['state'] as String?,
              postcode: addr?['postcode'] as String?,
              country: addr?['country'] as String?,
              countryCode: (addr?['country_code'] as String?)?.toUpperCase(),
            );
          })
          .whereType<AddressSuggestion>()
          // Nominatim often returns several rows that render to the same
          // address line (same street/city/postcode, different OSM objects) —
          // keep only the first of each.
          .fold<List<AddressSuggestion>>([], (acc, s) {
            final key = s.singleLineAddress();
            if (acc.every((e) => e.singleLineAddress() != key)) acc.add(s);
            return acc;
          })
          .toList(growable: false);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Address suggestions failed',
        error: e,
        stackTrace: stackTrace,
        metadata: {'query': trimmedQuery},
      );
      return const [];
    }
  }
}
