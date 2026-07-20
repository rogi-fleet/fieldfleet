import UIKit

/// Lifecycle contract every native engine implements.
///
/// `mount` is called once the Flutter platform view is created; the engine
/// installs its own subviews into the host. `start` begins the AR session;
/// `finish` asks for the final result (RoomBuilder for RoomPlan, immediate
/// polygon emission for the tap engines); `cancel` tears down without
/// emitting a result; `stop` pauses the AR session without tearing the
/// engine down, and `resume` brings the session back. Pause/resume preserve
/// captured geometry on engines that support it (RoomPlan and ARKit do;
/// ARCore taps don't keep state but the session itself resumes).
protocol RoomScanEngine: AnyObject {
    func mount(into host: UIView)
    func start()
    func finish()
    func stop()
    func resume()
    func cancel()
    /// Drop the most recently registered corner tap. Return the new
    /// remaining tap count, or -1 if the engine doesn't track discrete
    /// taps (RoomPlan — the AR session captures continuously).
    func undoLastTap() -> Int

    /// Multi-room only: lock in the current room (so we can chain to
    /// another capture in the same AR world frame) and emit a
    /// `roomCaptured` event when processing finishes. Engines that
    /// don't support multi-room fall back to single-room `finish`.
    func finishRoom()

    /// Multi-room only: merge every locked-in room into the final
    /// FloorPlanScanResult and emit `complete`. Engines that don't
    /// support multi-room treat this as `finish`.
    func finishAllRooms()
}

extension RoomScanEngine {
    func undoLastTap() -> Int { -1 }
    /// Default: treat finishRoom as finish — single-room engines
    /// emit complete on their one and only room.
    func finishRoom() { finish() }
    func finishAllRooms() { finish() }
}

// MARK: - Shared compatibility shims

enum ArKitCompat {
    static func isWorldTrackingSupported() -> Bool {
        #if canImport(ARKit)
        if #available(iOS 11.0, *) {
            return ARKitCompatRuntime.isWorldTrackingSupported()
        }
        #endif
        return false
    }
}

enum RoomPlanCompat {
    @available(iOS 16.0, *)
    static func isSupported() -> Bool {
        #if canImport(RoomPlan)
        return RoomPlanCompatRuntime.isSupported()
        #else
        return false
        #endif
    }
}

// Runtime helpers — split out so the file compiles on toolchains where the
// frameworks themselves are unavailable. They use Objective-C runtime calls
// to avoid hard imports.
enum ARKitCompatRuntime {
    static func isWorldTrackingSupported() -> Bool {
        guard let cls = NSClassFromString("ARWorldTrackingConfiguration") as? NSObject.Type else {
            return false
        }
        let sel = NSSelectorFromString("isSupported")
        guard cls.responds(to: sel) else { return false }
        let result = cls.perform(sel)
        return (result?.takeUnretainedValue() as? Bool) ?? false
    }
}

enum RoomPlanCompatRuntime {
    @available(iOS 16.0, *)
    static func isSupported() -> Bool {
        guard let cls = NSClassFromString("RoomCaptureSession") as? NSObject.Type else {
            return false
        }
        let sel = NSSelectorFromString("isSupported")
        guard cls.responds(to: sel) else { return false }
        let result = cls.perform(sel)
        return (result?.takeUnretainedValue() as? Bool) ?? false
    }
}
