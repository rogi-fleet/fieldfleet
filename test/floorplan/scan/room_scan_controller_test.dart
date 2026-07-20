import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/scan/floor_plan_scan_result.dart';
import 'package:taskfleet_ops/models/floorplan/scan/room_scan_capabilities.dart';
import 'package:taskfleet_ops/services/floorplan/scan/room_scan_channel.dart';
import 'package:taskfleet_ops/services/floorplan/scan/room_scan_controller.dart';

/// Test double that lets the test inject events into the controller
/// directly. Implements every public method on [RoomScanChannel] so the
/// controller treats it as a real channel.
class _FakeRoomScanChannel implements RoomScanChannel {
  final StreamController<RoomScanEvent> _events =
      StreamController<RoomScanEvent>.broadcast();

  RoomScanCapabilities capabilities =
      const RoomScanCapabilities(engine: ScanSourceEngine.arKitPlaneTap);

  bool startThrows = false;
  bool finishThrows = false;
  bool cancelThrows = false;
  bool resumeThrows = false;
  bool undoThrows = false;

  // Spied call counts for assertions.
  int startCount = 0;
  int finishCount = 0;
  int finishRoomCount = 0;
  int finishAllRoomsCount = 0;
  int stopCount = 0;
  int resumeCount = 0;
  int cancelCount = 0;
  int undoCount = 0;
  int undoReturnValue = 0;
  bool lastStartMultiRoom = false;

  @override
  bool get isAvailableOnThisPlatform => true;

  @override
  Future<RoomScanCapabilities> getCapabilities() async => capabilities;

  @override
  Future<void> start({
    required String captureId,
    bool multiRoom = false,
  }) async {
    startCount++;
    lastStartMultiRoom = multiRoom;
    if (startThrows) throw PlatformException(code: 'boom');
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> resume() async {
    resumeCount++;
    if (resumeThrows) throw PlatformException(code: 'boom');
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    if (cancelThrows) throw PlatformException(code: 'boom');
  }

  @override
  Future<void> finish() async {
    finishCount++;
    if (finishThrows) throw PlatformException(code: 'boom');
  }

  @override
  Future<void> finishRoom() async {
    finishRoomCount++;
  }

  @override
  Future<void> finishAllRooms() async {
    finishAllRoomsCount++;
  }

  @override
  Future<int?> undoLastTap() async {
    undoCount++;
    if (undoThrows) throw PlatformException(code: 'boom');
    return undoReturnValue;
  }

  @override
  Stream<RoomScanEvent> events() => _events.stream;

  void emit(RoomScanEvent event) => _events.add(event);
  Future<void> close() => _events.close();
}

void _grantCameraPermission() {
  // permission_handler talks to Baseflow's platform channel. Mock both
  // the "check" and "request" methods to return granted (value 1).
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
      case 'checkServiceStatus':
        return 1; // PermissionStatus.granted
      case 'requestPermissions':
        return {0: 1}; // {Permission.camera.value: PermissionStatus.granted}
      default:
        return null;
    }
  });
}

void _denyCameraPermission() {
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
        return 4; // PermissionStatus.permanentlyDenied
      case 'requestPermissions':
        return {0: 0}; // PermissionStatus.denied
      default:
        return null;
    }
  });
}

FloorPlanScanResult _sampleResult() => FloorPlanScanResult(
      captureId: 'cap-1',
      engine: ScanSourceEngine.arKitPlaneTap,
      confidence: 0.8,
      rooms: const [],
      capturedAt: DateTime.utc(2026, 5, 12),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('RoomScanController bootstrap', () {
    test('granted permission + supported capabilities -> ready', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel();
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      expect(controller.phase, RoomScanPhase.ready);
      controller.dispose();
      await fake.close();
    });

    test('denied permission -> failed', () async {
      _denyCameraPermission();
      final fake = _FakeRoomScanChannel();
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      expect(controller.phase, RoomScanPhase.failed);
      expect(controller.failure?.kind, ScanFailureKind.permissionDenied);
      controller.dispose();
      await fake.close();
    });

    test('unsupported engine -> unsupported', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities =
            RoomScanCapabilities.unsupported('No AR on this device');
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      expect(controller.phase, RoomScanPhase.unsupported);
      controller.dispose();
      await fake.close();
    });
  });

  group('RoomScanController capture lifecycle', () {
    late _FakeRoomScanChannel fake;
    late RoomScanController controller;

    setUp(() async {
      _grantCameraPermission();
      fake = _FakeRoomScanChannel();
      controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      assert(controller.phase == RoomScanPhase.ready);
    });

    tearDown(() async {
      controller.dispose();
      await fake.close();
    });

    test('startCapture transitions ready -> capturing', () async {
      await controller.startCapture();
      expect(controller.phase, RoomScanPhase.capturing);
      expect(fake.startCount, 1);
    });

    test('progress event updates progress without changing phase', () async {
      await controller.startCapture();
      fake.emit(const RoomScanProgressEvent(
          walls: 4, openings: 2, objects: 1));
      // Listeners notify synchronously after the event stream resolves.
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, RoomScanPhase.capturing);
      expect(controller.progress.walls, 4);
      expect(controller.progress.openings, 2);
    });

    test('guidance event updates guidance without changing phase', () async {
      await controller.startCapture();
      fake.emit(const RoomScanGuidanceEvent(
        message: 'Slow down',
        severity: GuidanceSeverity.warn,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.guidance?.message, 'Slow down');
      expect(controller.guidance?.severity, GuidanceSeverity.warn);
    });

    test('complete event -> reviewing with result', () async {
      await controller.startCapture();
      fake.emit(RoomScanCompleteEvent(result: _sampleResult()));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, RoomScanPhase.reviewing);
      expect(controller.result, isNotNull);
      expect(controller.result!.captureId, 'cap-1');
    });

    test('error event -> failed with failure populated', () async {
      await controller.startCapture();
      fake.emit(const RoomScanErrorEvent(
          failure: ScanFailure(ScanFailureKind.trackingLost)));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, RoomScanPhase.failed);
      expect(controller.failure?.kind, ScanFailureKind.trackingLost);
    });

    test('finishCapture transitions capturing -> finishing', () async {
      await controller.startCapture();
      await controller.finishCapture();
      expect(controller.phase, RoomScanPhase.finishing);
      expect(fake.finishCount, 1);
    });

    test('start throws -> failed', () async {
      fake.startThrows = true;
      await controller.startCapture();
      expect(controller.phase, RoomScanPhase.failed);
      expect(controller.failure?.kind, ScanFailureKind.unknown);
    });
  });

  group('RoomScanController races', () {
    late _FakeRoomScanChannel fake;
    late RoomScanController controller;

    setUp(() async {
      _grantCameraPermission();
      fake = _FakeRoomScanChannel();
      controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      await controller.startCapture();
    });

    tearDown(() async {
      controller.dispose();
      await fake.close();
    });

    test('cancelCapture during finishing transitions to cancelled', () async {
      await controller.finishCapture();
      expect(controller.phase, RoomScanPhase.finishing);
      await controller.cancelCapture();
      expect(controller.phase, RoomScanPhase.cancelled);
      expect(fake.cancelCount, 1);
    });

    test('complete arriving after cancel does not unwind cancelled state',
        () async {
      await controller.cancelCapture();
      expect(controller.phase, RoomScanPhase.cancelled);
      // Late event from the native side — the event subscription was
      // cancelled during cancelCapture so it should never reach _onEvent.
      // We verify by emitting and checking phase stays cancelled.
      fake.emit(RoomScanCompleteEvent(result: _sampleResult()));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, RoomScanPhase.cancelled);
      expect(controller.result, isNull);
    });

    test('error arriving after cancel does not flip to failed', () async {
      await controller.cancelCapture();
      fake.emit(const RoomScanErrorEvent(
          failure: ScanFailure(ScanFailureKind.trackingLost)));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, RoomScanPhase.cancelled);
    });
  });

  group('RoomScanController pause/resume', () {
    late _FakeRoomScanChannel fake;
    late RoomScanController controller;

    setUp(() async {
      _grantCameraPermission();
      fake = _FakeRoomScanChannel();
      controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      await controller.startCapture();
    });

    tearDown(() async {
      controller.dispose();
      await fake.close();
    });

    test('pauseCapture transitions capturing -> paused', () async {
      await controller.pauseCapture();
      expect(controller.phase, RoomScanPhase.paused);
      expect(fake.stopCount, 1);
    });

    test('resumeCapture transitions paused -> capturing', () async {
      await controller.pauseCapture();
      await controller.resumeCapture();
      expect(controller.phase, RoomScanPhase.capturing);
      expect(fake.resumeCount, 1);
    });

    test('pauseCapture is a no-op when not capturing', () async {
      await controller.finishCapture(); // moves to finishing
      await controller.pauseCapture();
      expect(controller.phase, RoomScanPhase.finishing);
      expect(fake.stopCount, 0);
    });

    test('resumeCapture failure transitions paused -> failed', () async {
      await controller.pauseCapture();
      fake.resumeThrows = true;
      await controller.resumeCapture();
      expect(controller.phase, RoomScanPhase.failed);
      expect(controller.failure?.kind, ScanFailureKind.trackingLost);
    });

    test('cancelCapture from paused tears down cleanly', () async {
      await controller.pauseCapture();
      await controller.cancelCapture();
      expect(controller.phase, RoomScanPhase.cancelled);
      expect(fake.cancelCount, 1);
    });
  });

  group('RoomScanController undoLastTap', () {
    test('routes to channel when engine is tap-based', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities =
            const RoomScanCapabilities(engine: ScanSourceEngine.arCoreDepth)
        ..undoReturnValue = 2;
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      await controller.startCapture();
      final removed = await controller.undoLastTap();
      expect(removed, isTrue);
      expect(fake.undoCount, 1);
      controller.dispose();
      await fake.close();
    });

    test('no-op when engine is RoomPlan (no discrete taps)', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities =
            const RoomScanCapabilities(engine: ScanSourceEngine.roomPlan);
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      await controller.startCapture();
      final removed = await controller.undoLastTap();
      expect(removed, isFalse);
      expect(fake.undoCount, 0);
      controller.dispose();
      await fake.close();
    });

    test('no-op when not capturing', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities =
            const RoomScanCapabilities(engine: ScanSourceEngine.arCorePlaneTap);
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      // Still in `ready` — not capturing yet.
      final removed = await controller.undoLastTap();
      expect(removed, isFalse);
      expect(fake.undoCount, 0);
      controller.dispose();
      await fake.close();
    });

    test('returns false when the channel throws', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities =
            const RoomScanCapabilities(engine: ScanSourceEngine.arKitPlaneTap)
        ..undoThrows = true;
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      await controller.startCapture();
      final removed = await controller.undoLastTap();
      expect(removed, isFalse);
      expect(controller.phase, RoomScanPhase.capturing); // didn't flip to failed
      controller.dispose();
      await fake.close();
    });
  });

  group('RoomScanController multi-room', () {
    test('setMultiRoomEnabled is no-op when engine does not support it',
        () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities = const RoomScanCapabilities(
          engine: ScanSourceEngine.arKitPlaneTap,
          supportsMultiRoom: false,
        );
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      controller.setMultiRoomEnabled(true);
      expect(controller.multiRoomEnabled, isFalse);
      controller.dispose();
      await fake.close();
    });

    test('multi-room flag is forwarded to start()', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities = const RoomScanCapabilities(
          engine: ScanSourceEngine.roomPlan,
          supportsMultiRoom: true,
        );
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      controller.setMultiRoomEnabled(true);
      await controller.startCapture();
      expect(fake.lastStartMultiRoom, isTrue);
      controller.dispose();
      await fake.close();
    });

    test('finishCapture in multi-room routes to finishRoom', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities = const RoomScanCapabilities(
          engine: ScanSourceEngine.roomPlan,
          supportsMultiRoom: true,
        );
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      controller.setMultiRoomEnabled(true);
      await controller.startCapture();
      await controller.finishCapture();
      expect(fake.finishRoomCount, 1);
      expect(fake.finishCount, 0);
      controller.dispose();
      await fake.close();
    });

    test('roomCaptured event lands in betweenRooms and bumps the count',
        () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities = const RoomScanCapabilities(
          engine: ScanSourceEngine.roomPlan,
          supportsMultiRoom: true,
        );
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      controller.setMultiRoomEnabled(true);
      await controller.startCapture();
      await controller.finishCapture();
      fake.emit(const RoomScanRoomCapturedEvent(completedRoomCount: 1));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, RoomScanPhase.betweenRooms);
      expect(controller.completedRoomCount, 1);
      controller.dispose();
      await fake.close();
    });

    test('startCapture from betweenRooms keeps the same captureId', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities = const RoomScanCapabilities(
          engine: ScanSourceEngine.roomPlan,
          supportsMultiRoom: true,
        );
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      controller.setMultiRoomEnabled(true);
      await controller.startCapture();
      final firstId = controller.captureId;
      await controller.finishCapture();
      fake.emit(const RoomScanRoomCapturedEvent(completedRoomCount: 1));
      await Future<void>.delayed(Duration.zero);
      await controller.startCapture();
      expect(controller.captureId, firstId);
      expect(controller.phase, RoomScanPhase.capturing);
      controller.dispose();
      await fake.close();
    });

    test('finishAllRooms routes to channel and waits for complete', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities = const RoomScanCapabilities(
          engine: ScanSourceEngine.roomPlan,
          supportsMultiRoom: true,
        );
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      controller.setMultiRoomEnabled(true);
      await controller.startCapture();
      await controller.finishCapture();
      fake.emit(const RoomScanRoomCapturedEvent(completedRoomCount: 1));
      await Future<void>.delayed(Duration.zero);
      await controller.finishAllRooms();
      expect(fake.finishAllRoomsCount, 1);
      expect(controller.phase, RoomScanPhase.finishing);
      controller.dispose();
      await fake.close();
    });

    test('cancelCapture from betweenRooms tears down cleanly', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel()
        ..capabilities = const RoomScanCapabilities(
          engine: ScanSourceEngine.roomPlan,
          supportsMultiRoom: true,
        );
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      controller.setMultiRoomEnabled(true);
      await controller.startCapture();
      await controller.finishCapture();
      fake.emit(const RoomScanRoomCapturedEvent(completedRoomCount: 1));
      await Future<void>.delayed(Duration.zero);
      await controller.cancelCapture();
      expect(controller.phase, RoomScanPhase.cancelled);
      expect(fake.cancelCount, 1);
      controller.dispose();
      await fake.close();
    });
  });

  group('RoomScanController discardResult', () {
    test('discardResult rewinds reviewing -> ready', () async {
      _grantCameraPermission();
      final fake = _FakeRoomScanChannel();
      final controller = RoomScanController(channel: fake);
      await controller.bootstrap();
      await controller.startCapture();
      fake.emit(RoomScanCompleteEvent(result: _sampleResult()));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, RoomScanPhase.reviewing);
      controller.discardResult();
      expect(controller.phase, RoomScanPhase.ready);
      expect(controller.result, isNull);
      controller.dispose();
      await fake.close();
    });
  });
}
