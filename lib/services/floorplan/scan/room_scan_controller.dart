import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../../models/floorplan/scan/floor_plan_scan_result.dart';
import '../../../models/floorplan/scan/room_scan_capabilities.dart';
import 'room_scan_channel.dart';

enum RoomScanPhase {
  /// Initial state, before any side effects.
  idle,

  /// Asking the OS for CAMERA permission.
  requestingPermission,

  /// Asking the native plugin what it can do.
  checkingCapabilities,

  /// The native plugin has no engine for this device.
  unsupported,

  /// Capabilities resolved, waiting for the user to tap "Start scanning".
  /// We keep this as an explicit state so the platform view doesn't start
  /// the AR session before the user is ready.
  ready,

  /// Native scan session is running. Progress events stream in.
  capturing,

  /// App was backgrounded mid-capture; the native AR session is paused
  /// and waiting for [RoomScanController.resumeCapture]. Captured
  /// geometry survives across pause/resume on engines that support it
  /// (RoomPlan, ARKit); on engines that don't (ARCore taps), it doesn't.
  paused,

  /// Multi-room only. The user finished a room (RoomPlan stopped, the
  /// room is locked in) and is now choosing between starting another
  /// room or merging everything captured so far. The AR session is
  /// alive — the device's world tracking carries through so the next
  /// room is positioned correctly relative to the previous ones.
  betweenRooms,

  /// User tapped "Done" — the native side is finalising the capture
  /// (e.g. RoomBuilder is processing).
  finishing,

  /// A [FloorPlanScanResult] arrived. The review sheet is up.
  reviewing,

  /// Scan was cancelled by the user.
  cancelled,

  /// Scan ended in failure (permission denied, tracking lost, etc).
  failed,
}

/// Owns the scan flow state. The screen is a dumb listener.
class RoomScanController extends ChangeNotifier {
  RoomScanController({
    RoomScanChannel? channel,
    Uuid? uuid,
  })  : _channel = channel ?? RoomScanChannel(),
        _uuid = uuid ?? const Uuid();

  final RoomScanChannel _channel;
  final Uuid _uuid;

  RoomScanPhase _phase = RoomScanPhase.idle;
  RoomScanPhase get phase => _phase;

  RoomScanCapabilities? _capabilities;
  RoomScanCapabilities? get capabilities => _capabilities;

  RoomScanProgressEvent _progress =
      const RoomScanProgressEvent(walls: 0, openings: 0, objects: 0);
  RoomScanProgressEvent get progress => _progress;

  RoomScanGuidanceEvent? _guidance;
  RoomScanGuidanceEvent? get guidance => _guidance;

  FloorPlanScanResult? _result;
  FloorPlanScanResult? get result => _result;

  ScanFailure? _failure;
  ScanFailure? get failure => _failure;

  String? _captureId;
  String? get captureId => _captureId;

  /// Set by the caller before `startCapture` when the user wants to
  /// scan multiple rooms in one continuous session. Multi-room is
  /// iOS 17+ LiDAR only; on every other engine the flag is silently
  /// ignored and the flow behaves as single-room.
  bool _multiRoomEnabled = false;
  bool get multiRoomEnabled => _multiRoomEnabled;

  /// Number of rooms locked in so far during a multi-room capture.
  /// Drives the "Room N captured" prompt in the [betweenRooms] phase.
  int _completedRoomCount = 0;
  int get completedRoomCount => _completedRoomCount;

  bool get supportsMultiRoom => _capabilities?.supportsMultiRoom ?? false;

  /// Caller toggles this from the ready overlay before starting a
  /// scan. No-op when the engine doesn't support multi-room.
  void setMultiRoomEnabled(bool enabled) {
    if (!supportsMultiRoom && enabled) return;
    if (_multiRoomEnabled == enabled) return;
    _multiRoomEnabled = enabled;
    notifyListeners();
  }

  StreamSubscription<RoomScanEvent>? _eventSub;
  bool _disposed = false;

  /// Get on screen entry: check capabilities first (so web/desktop hit the
  /// correct unsupported message without being asked for a camera permission
  /// they can never grant), then ask for camera permission, then move to
  /// `ready` (or `unsupported` / `failed`).
  Future<void> bootstrap() async {
    _setPhase(RoomScanPhase.checkingCapabilities);
    final caps = await _channel.getCapabilities();
    _capabilities = caps;
    if (!caps.isSupported) {
      _setPhase(RoomScanPhase.unsupported);
      return;
    }

    _setPhase(RoomScanPhase.requestingPermission);
    final granted = await _ensureCameraPermission();
    if (!granted) {
      _failure = const ScanFailure(
        ScanFailureKind.permissionDenied,
        'Camera permission is required to scan a room.',
      );
      _setPhase(RoomScanPhase.failed);
      return;
    }

    _setPhase(RoomScanPhase.ready);
  }

  /// User tapped "Start scanning". Begins streaming events. When
  /// continuing from `betweenRooms` (starting room N+1), we keep the
  /// existing capture id + event subscription so the native side can
  /// merge captures under one session.
  Future<void> startCapture() async {
    final continuingMultiRoom = _phase == RoomScanPhase.betweenRooms;
    if (_phase != RoomScanPhase.ready &&
        _phase != RoomScanPhase.cancelled &&
        _phase != RoomScanPhase.failed &&
        !continuingMultiRoom) {
      return;
    }
    if (!continuingMultiRoom) {
      _captureId = _uuid.v4();
      _failure = null;
      _result = null;
      _completedRoomCount = 0;
      _eventSub?.cancel();
      _eventSub = _channel.events().listen(_onEvent, onError: _onStreamError);
    }
    _progress =
        const RoomScanProgressEvent(walls: 0, openings: 0, objects: 0);
    try {
      await _channel.start(
        captureId: _captureId!,
        multiRoom: _multiRoomEnabled && supportsMultiRoom,
      );
      _setPhase(RoomScanPhase.capturing);
    } catch (e) {
      _failure = ScanFailure(ScanFailureKind.unknown, e.toString());
      _setPhase(RoomScanPhase.failed);
    }
  }

  /// User tapped "Done". In single-room mode the native side finalises
  /// and emits `complete`. In multi-room mode this locks in the current
  /// room and moves to `betweenRooms`, waiting on the user to either
  /// scan another room or merge everything.
  Future<void> finishCapture() async {
    if (_phase != RoomScanPhase.capturing) return;
    if (_multiRoomEnabled && supportsMultiRoom) {
      _setPhase(RoomScanPhase.finishing);
      try {
        await _channel.finishRoom();
        // The native side will emit a `roomCaptured` event when the
        // current room is processed; the event handler advances the
        // phase to betweenRooms and bumps _completedRoomCount.
      } catch (e) {
        _failure = ScanFailure(ScanFailureKind.unknown, e.toString());
        _setPhase(RoomScanPhase.failed);
      }
      return;
    }
    _setPhase(RoomScanPhase.finishing);
    try {
      await _channel.finish();
    } catch (e) {
      _failure = ScanFailure(ScanFailureKind.unknown, e.toString());
      _setPhase(RoomScanPhase.failed);
    }
  }

  /// Multi-room only. User said "I'm done with every room — merge them
  /// all and show me the result." The native side runs the final merge
  /// (RoomPlan's StructureBuilder when available, or simple union of
  /// per-room results) and emits `complete`.
  Future<void> finishAllRooms() async {
    if (_phase != RoomScanPhase.betweenRooms) return;
    _setPhase(RoomScanPhase.finishing);
    try {
      await _channel.finishAllRooms();
    } catch (e) {
      _failure = ScanFailure(ScanFailureKind.unknown, e.toString());
      _setPhase(RoomScanPhase.failed);
    }
  }

  Future<void> cancelCapture() async {
    if (_phase != RoomScanPhase.capturing &&
        _phase != RoomScanPhase.finishing &&
        _phase != RoomScanPhase.paused &&
        _phase != RoomScanPhase.betweenRooms) {
      return;
    }
    try {
      await _channel.cancel();
    } catch (_) {
      // Ignore — the screen is about to pop anyway.
    }
    await _eventSub?.cancel();
    _eventSub = null;
    _setPhase(RoomScanPhase.cancelled);
  }

  /// Pause the in-flight capture — the native AR session stops but the
  /// engine retains the captured geometry where supported. Called when
  /// the app moves to background. No-op outside of `capturing`.
  Future<void> pauseCapture() async {
    if (_phase != RoomScanPhase.capturing) return;
    try {
      await _channel.stop();
    } catch (_) {
      // Best-effort — if the native side already tore down, the resume
      // path will detect it and roll back to a failure state.
    }
    _setPhase(RoomScanPhase.paused);
  }

  /// Resume a previously paused capture. If the engine can't resume —
  /// typically because the OS reclaimed the AR session while we were
  /// backgrounded — the controller surfaces a failure so the user can
  /// rescan.
  Future<void> resumeCapture() async {
    if (_phase != RoomScanPhase.paused) return;
    try {
      await _channel.resume();
      _setPhase(RoomScanPhase.capturing);
    } catch (e) {
      _failure = ScanFailure(
        ScanFailureKind.trackingLost,
        'Scan was paused too long and the AR session ended. Start a new scan.',
      );
      _setPhase(RoomScanPhase.failed);
    }
  }

  /// Remove the most recent tap on engines that expose per-tap corner
  /// placement (ARKit / ARCore tap engines). Returns true if a tap was
  /// removed, false if nothing to undo. No-op when the engine doesn't
  /// support discrete taps (RoomPlan — the AR session itself decides
  /// what to capture; there's no individual tap to retract).
  Future<bool> undoLastTap() async {
    if (_phase != RoomScanPhase.capturing) return false;
    final caps = _capabilities;
    final tapBased = caps?.engine == ScanSourceEngine.arKitPlaneTap ||
        caps?.engine == ScanSourceEngine.arCoreDepth ||
        caps?.engine == ScanSourceEngine.arCorePlaneTap;
    if (!tapBased) return false;
    try {
      final remaining = await _channel.undoLastTap();
      // The native side emits a progress event with the new counts on
      // success, so we don't need to update [_progress] here.
      return remaining != null;
    } catch (_) {
      return false;
    }
  }

  /// Discard the current review result and go back to ready.
  void discardResult() {
    _result = null;
    _setPhase(RoomScanPhase.ready);
  }

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.camera.request();
    return result.isGranted;
  }

  void _onEvent(RoomScanEvent ev) {
    if (_disposed) return;
    switch (ev) {
      case RoomScanProgressEvent p:
        _progress = p;
        notifyListeners();
      case RoomScanGuidanceEvent g:
        _guidance = g;
        notifyListeners();
      case RoomScanRoomCapturedEvent r:
        _completedRoomCount = r.completedRoomCount;
        _setPhase(RoomScanPhase.betweenRooms);
      case RoomScanCompleteEvent c:
        _result = c.result;
        _setPhase(RoomScanPhase.reviewing);
      case RoomScanErrorEvent e:
        _failure = e.failure;
        _setPhase(RoomScanPhase.failed);
      case RoomScanCancelledEvent _:
        _setPhase(RoomScanPhase.cancelled);
      case RoomScanUnknownEvent _:
        // Ignore unknown events — they're forward-compat slots.
        break;
    }
  }

  void _onStreamError(Object error, StackTrace stack) {
    _failure = ScanFailure(ScanFailureKind.unknown, error.toString());
    _setPhase(RoomScanPhase.failed);
  }

  void _setPhase(RoomScanPhase next) {
    if (_disposed) return;
    if (_phase == next) return;
    _phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSub?.cancel();
    // Best-effort: tell native to tear down if the user backgrounds mid-scan.
    if (_phase == RoomScanPhase.capturing ||
        _phase == RoomScanPhase.finishing) {
      _channel.cancel().catchError((_) {});
    }
    super.dispose();
  }
}
