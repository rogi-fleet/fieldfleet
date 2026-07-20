import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/project.dart';

/// Service for handling GPS location tracking and geofencing
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Default geofence radius in meters
  static const int defaultGeofenceRadiusMeters = 500;

  /// Minimum accuracy threshold in meters (don't accept locations worse than this)
  static const double minimumAccuracyMeters = 50.0;

  /// Maximum age of location data in seconds
  static const int maxLocationAgeSeconds = 300; // 5 minutes

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check current location permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Check if we have location permission
  Future<bool> hasPermission() async {
    final permission = await checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Request permission and return whether it was granted
  Future<bool> requestLocationPermission() async {
    try {
      // First check if location services are enabled
      bool serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      // Check current permission status
      LocationPermission permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return false;
    }
  }

  /// Get current position with high accuracy
  Future<Position?> getCurrentPosition() async {
    try {
      if (!await hasPermission()) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // Validate accuracy
      if (position.accuracy > minimumAccuracyMeters) {
        debugPrint('Location accuracy too low: ${position.accuracy}m');
        // Still return it but it will be flagged
      }

      return position;
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  /// Get last known position (faster but may be stale)
  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint('Error getting last known position: $e');
      return null;
    }
  }

  /// Calculate distance between two coordinates in meters
  double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Check if a position is within a project's geofence
  GeofenceValidationResult validateGeofence({
    required Position workerPosition,
    required Project project,
  }) {
    // If project has no location, we can't validate
    if (project.latitude == null || project.longitude == null) {
      return GeofenceValidationResult(
        isWithinGeofence: true,
        distanceMeters: null,
        geofenceRadiusMeters: project.geofenceRadiusMeters,
        projectLatitude: null,
        projectLongitude: null,
        workerLatitude: workerPosition.latitude,
        workerLongitude: workerPosition.longitude,
        locationAccuracy: workerPosition.accuracy,
        message: 'Project location not set - geofence validation skipped',
      );
    }

    final distance = calculateDistance(
      workerPosition.latitude,
      workerPosition.longitude,
      project.latitude!,
      project.longitude!,
    );

    final isWithinGeofence = distance <= project.geofenceRadiusMeters;

    String message;
    if (isWithinGeofence) {
      message =
          'Within geofence (${distance.toStringAsFixed(0)}m from project)';
    } else {
      message =
          'Outside geofence (${distance.toStringAsFixed(0)}m from project, limit: ${project.geofenceRadiusMeters}m)';
    }

    return GeofenceValidationResult(
      isWithinGeofence: isWithinGeofence,
      distanceMeters: distance,
      geofenceRadiusMeters: project.geofenceRadiusMeters,
      projectLatitude: project.latitude,
      projectLongitude: project.longitude,
      workerLatitude: workerPosition.latitude,
      workerLongitude: workerPosition.longitude,
      locationAccuracy: workerPosition.accuracy,
      message: message,
    );
  }

  /// Check if geofence validation is required and if worker can proceed
  Future<GeofenceCheckResult> checkGeofenceForProject(Project project) async {
    // If geofence validation is not required, allow
    if (!project.requireGeofenceValidation) {
      return GeofenceCheckResult(
        canProceed: true,
        requiresValidation: false,
        validationResult: null,
        warningMessage: null,
      );
    }

    // Geofence is required but the project has no pin — we cannot validate.
    // Honor the project's "allow outside" flag rather than silently passing.
    if (project.latitude == null || project.longitude == null) {
      return GeofenceCheckResult(
        canProceed: project.allowClockInOutsideGeofence,
        requiresValidation: true,
        validationResult: null,
        warningMessage:
            'Project has no geofence pin set. ${project.allowClockInOutsideGeofence ? "Clock-in will be recorded without distance validation." : "Ask a supervisor to set the project pin before clocking in."}',
      );
    }

    // Get current position
    final position = await getCurrentPosition();

    if (position == null) {
      // No location available
      return GeofenceCheckResult(
        canProceed: project.allowClockInOutsideGeofence,
        requiresValidation: true,
        validationResult: null,
        warningMessage:
            'Unable to get GPS location. ${project.allowClockInOutsideGeofence ? "You can still clock in, but location will not be recorded." : "Location is required to clock in."}',
      );
    }

    // Validate against geofence
    final validation = validateGeofence(
      workerPosition: position,
      project: project,
    );

    if (validation.isWithinGeofence) {
      return GeofenceCheckResult(
        canProceed: true,
        requiresValidation: true,
        validationResult: validation,
        warningMessage: null,
      );
    }

    // Outside geofence
    return GeofenceCheckResult(
      canProceed: project.allowClockInOutsideGeofence,
      requiresValidation: true,
      validationResult: validation,
      warningMessage: validation.message,
    );
  }

  /// Stream of position updates (for live tracking)
  Stream<Position>? getPositionStream({
    LocationAccuracy desiredAccuracy = LocationAccuracy.best,
    int distanceFilterMeters = 10,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: desiredAccuracy,
        distanceFilter: distanceFilterMeters,
      ),
    );
  }

  /// Convert Position to LatLng (for maps)
  static LatLng positionToLatLng(Position position) {
    return LatLng(position.latitude, position.longitude);
  }

  /// Format distance for display
  static String formatDistance(double? distanceMeters) {
    if (distanceMeters == null) return 'Unknown';

    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)}m';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// Format accuracy for display
  static String formatAccuracy(double? accuracyMeters) {
    if (accuracyMeters == null) return 'Unknown';
    return '±${accuracyMeters.toStringAsFixed(0)}m';
  }
}

/// Result of geofence validation
class GeofenceValidationResult {
  final bool isWithinGeofence;
  final double? distanceMeters;
  final int geofenceRadiusMeters;
  final double? projectLatitude;
  final double? projectLongitude;
  final double workerLatitude;
  final double workerLongitude;
  final double locationAccuracy;
  final String message;

  GeofenceValidationResult({
    required this.isWithinGeofence,
    this.distanceMeters,
    required this.geofenceRadiusMeters,
    this.projectLatitude,
    this.projectLongitude,
    required this.workerLatitude,
    required this.workerLongitude,
    required this.locationAccuracy,
    required this.message,
  });

  bool get hasProjectLocation =>
      projectLatitude != null && projectLongitude != null;
}

/// Result of geofence check for clock in/out
class GeofenceCheckResult {
  final bool canProceed;
  final bool requiresValidation;
  final GeofenceValidationResult? validationResult;
  final String? warningMessage;

  GeofenceCheckResult({
    required this.canProceed,
    required this.requiresValidation,
    this.validationResult,
    this.warningMessage,
  });

  bool get isWithinGeofence => validationResult?.isWithinGeofence ?? false;
  bool get hasWarning => warningMessage != null;
  bool get hasLocation => validationResult != null;
}
