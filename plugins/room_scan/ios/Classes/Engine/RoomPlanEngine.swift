import UIKit
import simd

#if canImport(RoomPlan)
import RoomPlan
#endif

/// RoomPlan-backed engine. Only usable on iOS 16+ LiDAR devices.
///
/// We mount Apple's `RoomCaptureView` directly — it owns the AR view and
/// coaching overlay. We listen on `RoomCaptureSessionDelegate` for progress
/// (wall / opening / object counts) and on `RoomCaptureViewDelegate` for
/// the final `CapturedRoom`, which we then convert to FloorPlanScanResult
/// JSON and ship through the event channel.
@available(iOS 16.0, *)
final class RoomPlanEngine: NSObject, RoomScanEngine {
    private let captureId: String
    private let multiRoom: Bool
    private let sink: RoomScanEventSink

    #if canImport(RoomPlan)
    private var captureView: RoomCaptureView?
    private var configuration = RoomCaptureSession.Configuration()
    private var finalRoom: CapturedRoom?
    private var lastProgress = (walls: 0, openings: 0, objects: 0)

    /// Rooms locked in so far during a multi-room capture. The first
    /// element is the room from the first `finishRoom` call, etc.
    /// On `finishAllRooms` we union these into the final result.
    private var capturedRooms: [CapturedRoom] = []

    /// When true, the next `didPresent` delegate callback should push
    /// onto capturedRooms and emit `roomCaptured` instead of `complete`.
    /// We flip it on `finishRoom` and back off on `finishAllRooms`.
    private var pendingRoomFinalisation: Bool = false
    #endif

    init(captureId: String, multiRoom: Bool, sink: RoomScanEventSink) {
        self.captureId = captureId
        self.multiRoom = multiRoom
        self.sink = sink
        super.init()
    }

    convenience init(captureId: String, sink: RoomScanEventSink) {
        self.init(captureId: captureId, multiRoom: false, sink: sink)
    }

    func mount(into host: UIView) {
        #if canImport(RoomPlan)
        let view = RoomCaptureView(frame: host.bounds)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.captureSession.delegate = self
        view.delegate = self
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        self.captureView = view
        #endif
    }

    func start() {
        #if canImport(RoomPlan)
        captureView?.captureSession.run(configuration: configuration)
        #endif
    }

    func finish() {
        #if canImport(RoomPlan)
        // Asking the session to stop triggers the view delegate's
        // captureView(didPresent:error:) callback once RoomBuilder is done.
        captureView?.captureSession.stop()
        #endif
    }

    func finishRoom() {
        #if canImport(RoomPlan)
        // Multi-room: lock in the current room. We pass
        // pauseARSession: false so the AR world frame survives —
        // when the user starts the next room, transforms are still
        // in the same coordinate system. Single-room mode ignores
        // the flag entirely.
        guard multiRoom else { finish(); return }
        pendingRoomFinalisation = true
        captureView?.captureSession.stop(pauseARSession: false)
        #endif
    }

    func finishAllRooms() {
        #if canImport(RoomPlan)
        guard multiRoom else { finish(); return }
        // The session might still be running (user picked "Finish all"
        // mid-room). Treat the in-flight capture as the last room and
        // emit the merged result via the delegate callback path.
        pendingRoomFinalisation = false
        captureView?.captureSession.stop()
        #endif
    }

    func stop() {
        #if canImport(RoomPlan)
        captureView?.captureSession.stop(pauseARSession: true)
        #endif
    }

    func resume() {
        #if canImport(RoomPlan)
        // After stop(pauseARSession: true), calling run(configuration:)
        // continues the capture — RoomPlan keeps the wall/door/object
        // state it had at the time of pause.
        captureView?.captureSession.run(configuration: configuration)
        #endif
    }

    func cancel() {
        #if canImport(RoomPlan)
        captureView?.captureSession.stop()
        captureView?.removeFromSuperview()
        captureView = nil
        #endif
    }

    private func emitError(_ kind: String, _ message: String?) {
        var payload: [String: Any] = ["type": "error", "kind": kind]
        if let m = message { payload["message"] = m }
        sink.send(payload)
    }
}

#if canImport(RoomPlan)

@available(iOS 16.0, *)
extension RoomPlanEngine: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let next = (
            walls: room.walls.count,
            openings: room.doors.count + room.windows.count + room.openings.count,
            objects: room.objects.count
        )
        guard next.walls != lastProgress.walls ||
                next.openings != lastProgress.openings ||
                next.objects != lastProgress.objects else { return }
        lastProgress = next
        sink.send([
            "type": "progress",
            "walls": next.walls,
            "openings": next.openings,
            "objects": next.objects,
        ])
    }

    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        let (msg, severity) = instructionDescription(instruction)
        sink.send([
            "type": "guidance",
            "message": msg,
            "severity": severity,
        ])
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        // Final processing happens via RoomBuilder. RoomCaptureView's
        // delegate is the place where we receive the finished CapturedRoom,
        // so this delegate method primarily handles the error path.
        if let error = error {
            emitError("unknown", error.localizedDescription)
        }
    }

    private func instructionDescription(_ instruction: RoomCaptureSession.Instruction) -> (String, String) {
        switch instruction {
        case .moveCloseToWall:
            return ("Move closer to the wall", "warn")
        case .moveAwayFromWall:
            return ("Move away from the wall", "warn")
        case .slowDown:
            return ("Slow down", "warn")
        case .turnOnLight:
            return ("Turn on the lights — more light improves accuracy", "warn")
        case .normal:
            return ("Looking good", "info")
        case .lowTexture:
            return ("Low-texture surface — try a different angle", "warn")
        @unknown default:
            return ("Hold steady", "info")
        }
    }
}

@available(iOS 16.0, *)
extension RoomPlanEngine: RoomCaptureViewDelegate {
    /// Returning false here keeps RoomPlan from showing its own share sheet,
    /// so we stay in control of the post-capture flow.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return false
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error = error {
            emitError("unknown", error.localizedDescription)
            return
        }
        if pendingRoomFinalisation {
            // Multi-room: this is room N, lock it in and prompt the
            // Dart side to either continue or merge.
            pendingRoomFinalisation = false
            capturedRooms.append(processedResult)
            sink.send([
                "type": "roomCaptured",
                "completedRoomCount": capturedRooms.count,
            ])
            return
        }
        finalRoom = processedResult
        if multiRoom {
            capturedRooms.append(processedResult)
            emitMerged()
        } else {
            emit(processedResult)
        }
    }

    private func emit(_ room: CapturedRoom) {
        let payload = CapturedRoomBridge.toJson(
            room,
            captureId: captureId
        )
        sink.send([
            "type": "complete",
            "result": payload,
        ])
    }

    /// Multi-room finalisation. Each CapturedRoom is converted
    /// independently and emitted as a separate ScannedRoom inside one
    /// FloorPlanScanResult. Because every wall's transform is in the
    /// shared AR world frame, the per-room polygons land at the right
    /// real-world positions when ScanToScene.convert applies their
    /// identity poses.
    private func emitMerged() {
        let payload = CapturedRoomBridge.toJsonMultiRoom(
            capturedRooms,
            captureId: captureId
        )
        sink.send([
            "type": "complete",
            "result": payload,
        ])
    }
}

#endif
