import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../models/floorplan/scan/floor_plan_scan_result.dart';
import '../../../models/floorplan/scan/room_scan_capabilities.dart';

/// Thin wrapper around the platform channels exposed by the native room-scan
/// plugin. One [MethodChannel] for commands, one [EventChannel] for the
/// streaming progress and the final result.
///
/// Channel contract (kept in lockstep with the native code):
///
///   * `getCapabilities` → `Map` matching [RoomScanCapabilities.fromMap]
///   * `start` (args: `{captureId, multiRoom: bool}`) → `null`
///   * `stop` → `null`
///   * `resume` → `null`
///   * `cancel` → `null`
///   * `finish` → `null`            // single-room: wrap up + emit complete
///   * `finishRoom` → `null`        // multi-room: lock in this room, emit `roomCaptured`
///   * `finishAllRooms` → `null`    // multi-room: merge everything + emit `complete`
///   * `undoLastTap` → `int`        // remaining tap count, or -1
///
/// Events on the event channel are tagged maps:
///   `{type: 'progress',    walls: int, openings: int, objects: int}`
///   `{type: 'guidance',    message: String, severity: 'info'|'warn'|'error'}`
///   `{type: 'roomCaptured', completedRoomCount: int}`
///   `{type: 'complete',    result: FloorPlanScanResult JSON}`
///   `{type: 'error',       kind: String, message: String?}`
///   `{type: 'cancelled'}`
class RoomScanChannel {
  RoomScanChannel({
    MethodChannel? method,
    EventChannel? events,
  })  : _method = method ?? const MethodChannel('taskfleet/room_scan'),
        _events = events ?? const EventChannel('taskfleet/room_scan/events');

  static const String platformViewType = 'taskfleet/room_scan_view';

  final MethodChannel _method;
  final EventChannel _events;

  bool get isAvailableOnThisPlatform => Platform.isAndroid || Platform.isIOS;

  Future<RoomScanCapabilities> getCapabilities() async {
    if (!isAvailableOnThisPlatform) {
      return RoomScanCapabilities.unsupported(
          'Room scanning is only available on the mobile app.');
    }
    try {
      final raw = await _method.invokeMapMethod<dynamic, dynamic>(
        'getCapabilities',
      );
      if (raw == null) {
        return RoomScanCapabilities.unsupported('No native plugin response.');
      }
      return RoomScanCapabilities.fromMap(raw);
    } on MissingPluginException {
      return RoomScanCapabilities.unsupported(
          'Room scan plugin is not installed on this build.');
    } on PlatformException catch (e) {
      return RoomScanCapabilities.unsupported(e.message ?? e.code);
    }
  }

  Future<void> start({
    required String captureId,
    bool multiRoom = false,
  }) async {
    await _method.invokeMethod<void>('start', {
      'captureId': captureId,
      'multiRoom': multiRoom,
    });
  }

  Future<void> stop() => _method.invokeMethod<void>('stop');
  Future<void> resume() => _method.invokeMethod<void>('resume');
  Future<void> cancel() => _method.invokeMethod<void>('cancel');
  Future<void> finish() => _method.invokeMethod<void>('finish');

  /// Multi-room only: lock in the current room and wait for the user to
  /// either start another room (via `start`) or merge everything (via
  /// `finishAllRooms`). The native side emits `roomCaptured` once the
  /// current room is processed.
  Future<void> finishRoom() => _method.invokeMethod<void>('finishRoom');

  /// Multi-room only: combine every locked-in room into the final
  /// FloorPlanScanResult and emit `complete`.
  Future<void> finishAllRooms() =>
      _method.invokeMethod<void>('finishAllRooms');

  /// Tell the active engine to drop its most recently registered tap.
  /// No-op on engines that don't expose tap-based corner placement
  /// (RoomPlan walks the room continuously, there is no discrete tap to
  /// undo). Returns the number of remaining taps, or `null` when the
  /// engine doesn't track them.
  Future<int?> undoLastTap() async {
    final result = await _method.invokeMethod<int>('undoLastTap');
    return result;
  }

  /// One stream per call. Native side broadcasts the same payload regardless
  /// of how many Dart listeners attach.
  Stream<RoomScanEvent> events() {
    return _events.receiveBroadcastStream().map((raw) {
      final m = (raw as Map).cast<String, dynamic>();
      final type = m['type'] as String? ?? 'unknown';
      switch (type) {
        case 'progress':
          return RoomScanProgressEvent(
            walls: (m['walls'] as num?)?.toInt() ?? 0,
            openings: (m['openings'] as num?)?.toInt() ?? 0,
            objects: (m['objects'] as num?)?.toInt() ?? 0,
          );
        case 'guidance':
          return RoomScanGuidanceEvent(
            message: m['message'] as String? ?? '',
            severity:
                _guidanceSeverityFromString(m['severity'] as String? ?? 'info'),
          );
        case 'roomCaptured':
          return RoomScanRoomCapturedEvent(
            completedRoomCount: (m['completedRoomCount'] as num?)?.toInt() ?? 1,
          );
        case 'complete':
          final resultMap =
              (m['result'] as Map).cast<String, dynamic>();
          return RoomScanCompleteEvent(
            result: FloorPlanScanResult.fromJson(resultMap),
          );
        case 'error':
          return RoomScanErrorEvent(
            failure: ScanFailure(
              scanFailureKindFromString(m['kind'] as String? ?? 'unknown'),
              m['message'] as String?,
            ),
          );
        case 'cancelled':
          return const RoomScanCancelledEvent();
        default:
          return RoomScanUnknownEvent(raw: m);
      }
    });
  }
}

GuidanceSeverity _guidanceSeverityFromString(String s) {
  switch (s) {
    case 'warn':
      return GuidanceSeverity.warn;
    case 'error':
      return GuidanceSeverity.error;
    case 'info':
    default:
      return GuidanceSeverity.info;
  }
}

enum GuidanceSeverity { info, warn, error }

sealed class RoomScanEvent {
  const RoomScanEvent();
}

class RoomScanProgressEvent extends RoomScanEvent {
  final int walls;
  final int openings;
  final int objects;
  const RoomScanProgressEvent({
    required this.walls,
    required this.openings,
    required this.objects,
  });
}

class RoomScanGuidanceEvent extends RoomScanEvent {
  final String message;
  final GuidanceSeverity severity;
  const RoomScanGuidanceEvent({required this.message, required this.severity});
}

class RoomScanRoomCapturedEvent extends RoomScanEvent {
  /// Number of rooms locked in so far during a multi-room session.
  /// The first emitted value is 1.
  final int completedRoomCount;
  const RoomScanRoomCapturedEvent({required this.completedRoomCount});
}

class RoomScanCompleteEvent extends RoomScanEvent {
  final FloorPlanScanResult result;
  const RoomScanCompleteEvent({required this.result});
}

class RoomScanErrorEvent extends RoomScanEvent {
  final ScanFailure failure;
  const RoomScanErrorEvent({required this.failure});
}

class RoomScanCancelledEvent extends RoomScanEvent {
  const RoomScanCancelledEvent();
}

class RoomScanUnknownEvent extends RoomScanEvent {
  final Map<String, dynamic> raw;
  const RoomScanUnknownEvent({required this.raw});
}
