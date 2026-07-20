import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'; // For WriteBuffer
import 'dart:ui'; // For Size

/// Service for detecting room types using ML Kit image labeling
class RoomDetector {
  late ImageLabeler _imageLabeler;
  bool _initialized = false;

  /// Initialize the ML Kit image labeler
  Future<void> initialize() async {
    if (_initialized) return;
    
    final options = ImageLabelerOptions(
      confidenceThreshold: 0.5, // Only use labels with 50%+ confidence
    );
    _imageLabeler = ImageLabeler(options: options);
    _initialized = true;
  }

  /// Detect room type from camera image
  Future<String?> detectRoomType(CameraImage? cameraImage) async {
    if (!_initialized || cameraImage == null) return null;

    try {
      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _convertCameraImage(cameraImage);
      if (inputImage == null) return null;

      // Run image labeling
      final labels = await _imageLabeler.processImage(inputImage);

      // Analyze labels and determine room type
      return _inferRoomType(labels);
    } catch (e) {
      print('Room detection error: $e');
      return null;
    }
  }

  /// Infer room type from detected labels
  String? _inferRoomType(List<ImageLabel> labels) {
    // Create a map of detected objects
    final detectedObjects = <String, double>{};
    for (var label in labels) {
      detectedObjects[label.label.toLowerCase()] = label.confidence;
    }

    // Bathroom detection
    if (_hasAny(detectedObjects, ['toilet', 'sink', 'shower', 'bathtub', 'bathroom'])) {
      return 'Bathroom';
    }

    // Kitchen detection
    if (_hasAny(detectedObjects, ['stove', 'oven', 'refrigerator', 'microwave', 'kitchen', 'dishwasher'])) {
      return 'Kitchen';
    }

    // Bedroom detection
    if (_hasAny(detectedObjects, ['bed', 'bedroom', 'dresser', 'nightstand'])) {
      return 'Bedroom';
    }

    // Living room detection
    if (_hasAny(detectedObjects, ['couch', 'sofa', 'television', 'tv', 'living room'])) {
      return 'Living Room';
    }

    // Dining room detection
    if (_hasAny(detectedObjects, ['dining table', 'dining room', 'table'])) {
      return 'Dining Room';
    }

    // Laundry room detection
    if (_hasAny(detectedObjects, ['washer', 'dryer', 'washing machine', 'laundry'])) {
      return 'Laundry Room';
    }

    // Office/Study detection
    if (_hasAny(detectedObjects, ['desk', 'office', 'bookshelf', 'computer'])) {
      return 'Office';
    }

    // Garage detection
    if (_hasAny(detectedObjects, ['car', 'garage', 'vehicle', 'tool'])) {
      return 'Garage';
    }

    return null; // Unknown room type
  }

  /// Check if any of the keywords exist in detected objects
  bool _hasAny(Map<String, double> objects, List<String> keywords) {
    for (var keyword in keywords) {
      for (var object in objects.keys) {
        if (object.contains(keyword) && objects[object]! > 0.5) {
          return true;
        }
      }
    }
    return false;
  }

  /// Convert CameraImage to InputImage for ML Kit
  InputImage? _convertCameraImage(CameraImage cameraImage) {
    try {
      // Note: This is a simplified conversion
      // In production, you'd need proper format conversion
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImageData = InputImageMetadata(
        size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );
    } catch (e) {
      print('Image conversion error: $e');
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    if (_initialized) {
      _imageLabeler.close();
      _initialized = false;
    }
  }
}
