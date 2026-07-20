import 'package:flutter/material.dart';
import 'mobile_map_widget.dart';

/// An adaptive map widget that uses OpenStreetMap tiles across all platforms
/// Since we're now using flutter_map, the same implementation works everywhere
class AdaptiveMapWidget extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double zoom;
  final String? markerTitle;
  final String? address;
  final double height;

  const AdaptiveMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.zoom = 14.0,
    this.markerTitle,
    this.address,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    // Use MobileMapWidget (now OSM-based) for all platforms
    return MobileMapWidget(
      latitude: latitude,
      longitude: longitude,
      zoom: zoom,
      markerTitle: markerTitle,
      address: address,
      height: height,
    );
  }
}
