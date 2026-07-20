import Flutter
import UIKit

/// Bridges the Dart `RoomScanChannel` to the native engines.
///
/// One method channel for commands, one event channel for progress / final
/// payloads, and one platform-view factory that mounts the active engine's
/// view.
final class RoomScanPlugin: NSObject, FlutterPlugin {
    static let methodChannelName = "taskfleet/room_scan"
    static let eventChannelName = "taskfleet/room_scan/events"
    static let viewTypeName = "taskfleet/room_scan_view"

    // Singleton glue. The view factory needs to talk to the same plugin
    // instance that owns the engines.
    private static var shared: RoomScanPlugin?

    private let eventSink = RoomScanEventSink()
    private var session: RoomScanSession?

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = RoomScanPlugin()
        shared = plugin

        let method = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(plugin, channel: method)

        let events = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        events.setStreamHandler(plugin.eventSink)

        let factory = RoomScanViewFactory(plugin: plugin)
        registrar.register(factory, withId: viewTypeName)
    }

    static func attach(view: RoomScanPlatformView) {
        shared?.session?.attach(view: view)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCapabilities":
            result(Capabilities.detect().toMap())
        case "start":
            guard let args = call.arguments as? [String: Any],
                  let captureId = args["captureId"] as? String else {
                result(FlutterError(code: "bad_args", message: "captureId required", details: nil))
                return
            }
            let multiRoom = (args["multiRoom"] as? Bool) ?? false
            startSession(captureId: captureId, multiRoom: multiRoom)
            result(nil)
        case "finish":
            session?.finish()
            result(nil)
        case "finishRoom":
            session?.finishRoom()
            result(nil)
        case "finishAllRooms":
            session?.finishAllRooms()
            result(nil)
        case "stop":
            session?.stop()
            result(nil)
        case "resume":
            session?.resume()
            result(nil)
        case "undoLastTap":
            // Tap engines return the remaining count; engines without
            // discrete taps return -1 so the Dart side knows to no-op.
            let remaining = session?.undoLastTap() ?? -1
            result(remaining)
        case "cancel":
            session?.cancel()
            session = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startSession(captureId: String, multiRoom: Bool) {
        // If we're continuing a multi-room session (the user picked
        // "Scan room N+1" in the betweenRooms phase), keep the existing
        // engine so the AR world frame and the captured room list carry
        // through. The Dart side reuses the same captureId so we can
        // detect the chain.
        if let active = session, active.captureId == captureId {
            active.continueWithNextRoom()
            return
        }
        session?.cancel()
        let caps = Capabilities.detect()
        let engine: RoomScanEngine
        switch caps.engine {
        case .roomPlan:
            if #available(iOS 16.0, *) {
                engine = RoomPlanEngine(
                    captureId: captureId,
                    multiRoom: multiRoom && caps.supportsMultiRoom,
                    sink: eventSink
                )
            } else {
                engine = ArKitTapEngine(captureId: captureId, sink: eventSink)
            }
        case .arKitPlaneTap:
            engine = ArKitTapEngine(captureId: captureId, sink: eventSink)
        default:
            eventSink.send([
                "type": "error",
                "kind": "unsupportedDevice",
                "message": "No supported room scan engine for this device.",
            ])
            return
        }
        let next = RoomScanSession(engine: engine, sink: eventSink, captureId: captureId)
        session = next
        next.start()
    }
}

/// Forwards engine callbacks to the Dart EventChannel sink. Thread-safe in
/// the sense that all sends are marshalled to the main thread.
final class RoomScanEventSink: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.sink = nil
        return nil
    }

    func send(_ payload: [String: Any]) {
        let sink = self.sink
        DispatchQueue.main.async {
            sink?(payload)
        }
    }
}

/// Active scan session — owns one engine and routes its lifecycle through
/// the platform view.
final class RoomScanSession {
    private let engine: RoomScanEngine
    private let sink: RoomScanEventSink
    private weak var view: RoomScanPlatformView?
    let captureId: String

    init(engine: RoomScanEngine, sink: RoomScanEventSink, captureId: String) {
        self.engine = engine
        self.sink = sink
        self.captureId = captureId
    }

    /// Multi-room: continue an existing engine into another room.
    /// Dispatches to the engine's `start` so it can re-arm its
    /// capture session without losing the prior captures.
    func continueWithNextRoom() {
        engine.start()
    }

    func attach(view: RoomScanPlatformView) {
        self.view = view
        if let host = view.containerView {
            engine.mount(into: host)
        }
    }

    func start() {
        engine.start()
    }

    func finish() {
        engine.finish()
    }

    func stop() {
        engine.stop()
    }

    func resume() {
        engine.resume()
    }

    /// Returns -1 if the active engine doesn't track discrete taps.
    func undoLastTap() -> Int {
        return engine.undoLastTap()
    }

    func finishRoom() {
        engine.finishRoom()
    }

    func finishAllRooms() {
        engine.finishAllRooms()
    }

    func cancel() {
        engine.cancel()
        sink.send(["type": "cancelled"])
    }
}

// MARK: - Platform view

final class RoomScanViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: RoomScanPlugin?

    init(plugin: RoomScanPlugin) {
        self.plugin = plugin
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let view = RoomScanPlatformView(frame: frame)
        RoomScanPlugin.attach(view: view)
        return view
    }
}

final class RoomScanPlatformView: NSObject, FlutterPlatformView {
    let containerView: UIView?

    init(frame: CGRect) {
        let v = UIView(frame: frame)
        v.backgroundColor = .black
        self.containerView = v
    }

    func view() -> UIView {
        return containerView ?? UIView()
    }
}

// MARK: - Capabilities

struct Capabilities {
    enum Engine: String {
        case roomPlan
        case arKitPlaneTap
        case none
    }

    let engine: Engine
    let supportsMultiRoom: Bool
    let hasDepthSensor: Bool
    let unsupportedReason: String?

    static func detect() -> Capabilities {
        #if canImport(RoomPlan)
        if #available(iOS 16.0, *) {
            let roomPlanSupported = RoomPlanCompat.isSupported()
            if roomPlanSupported {
                return Capabilities(
                    engine: .roomPlan,
                    supportsMultiRoom: roomPlanMultiRoomSupported(),
                    hasDepthSensor: true,
                    unsupportedReason: nil
                )
            }
        }
        #endif

        #if canImport(ARKit)
        if ArKitCompat.isWorldTrackingSupported() {
            return Capabilities(
                engine: .arKitPlaneTap,
                supportsMultiRoom: false,
                hasDepthSensor: false,
                unsupportedReason: nil
            )
        }
        #endif

        return Capabilities(
            engine: .none,
            supportsMultiRoom: false,
            hasDepthSensor: false,
            unsupportedReason: "AR is not supported on this device."
        )
    }

    func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "engine": engine.rawValue,
            "supportsMultiRoom": supportsMultiRoom,
            "hasDepthSensor": hasDepthSensor,
        ]
        if let reason = unsupportedReason {
            map["unsupportedReason"] = reason
        }
        return map
    }

    private static func roomPlanMultiRoomSupported() -> Bool {
        if #available(iOS 17.0, *) {
            return true
        }
        return false
    }
}
