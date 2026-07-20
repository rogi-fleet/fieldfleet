import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import '../../../services/floorplan/scan/room_scan_channel.dart';

/// Embeds the native AR view (RoomCaptureView on iOS, GLSurfaceView on
/// Android). The view's lifecycle is owned by the native plugin — the
/// MethodChannel `start`/`stop`/`finish` calls drive it, not the platform
/// view's mount/unmount alone.
class RoomScanPlatformView extends StatelessWidget {
  const RoomScanPlatformView({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return const UiKitView(
        viewType: RoomScanChannel.platformViewType,
        creationParams: <String, dynamic>{},
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    if (Platform.isAndroid) {
      // Hybrid composition so Flutter overlays (guidance, FABs) are hit-
      // testable on top of the camera surface.
      return PlatformViewLink(
        viewType: RoomScanChannel.platformViewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: RoomScanChannel.platformViewType,
            layoutDirection: TextDirection.ltr,
            creationParams: const <String, dynamic>{},
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      );
    }
    return const _UnsupportedSurface();
  }
}

class _UnsupportedSurface extends StatelessWidget {
  const _UnsupportedSurface();
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          'Room scan view is only available on iOS and Android.',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
