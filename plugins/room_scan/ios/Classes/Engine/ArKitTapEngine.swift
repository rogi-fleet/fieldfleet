import UIKit
import simd

#if canImport(ARKit)
import ARKit
import SceneKit
#endif

/// ARKit-based fallback. The user taps each corner of the room on a detected
/// horizontal plane; we drop a sphere at each tap, draw a polyline between
/// consecutive taps, and on finish ship a single-room FloorPlanScanResult.
final class ArKitTapEngine: NSObject, RoomScanEngine {
    private let captureId: String
    private let sink: RoomScanEventSink

    #if canImport(ARKit)
    private var sceneView: ARSCNView?
    private var configuration: ARWorldTrackingConfiguration = {
        let c = ARWorldTrackingConfiguration()
        c.planeDetection = .horizontal
        return c
    }()
    private var floorY: Float?
    private var tappedPointsXZMeters: [SIMD2<Float>] = []
    // Per-tap visual nodes, parallel to tappedPointsXZMeters. Each entry
    // holds the corner sphere; the connecting edge cylinder (when present)
    // is stored alongside so undo can pull both at once.
    private var tapNodes: [(corner: SCNNode, edge: SCNNode?)] = []
    #endif

    init(captureId: String, sink: RoomScanEventSink) {
        self.captureId = captureId
        self.sink = sink
        super.init()
    }

    func mount(into host: UIView) {
        #if canImport(ARKit)
        let v = ARSCNView(frame: host.bounds)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.delegate = self
        v.session.delegate = self
        v.automaticallyUpdatesLighting = true
        v.debugOptions = []
        host.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: host.topAnchor),
            v.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        v.addGestureRecognizer(tap)
        self.sceneView = v
        #endif
    }

    func start() {
        #if canImport(ARKit)
        sceneView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        sink.send([
            "type": "guidance",
            "message": "Point the camera at the floor",
            "severity": "info",
        ])
        #endif
    }

    func finish() {
        #if canImport(ARKit)
        let polygon = tappedPointsXZMeters
        if polygon.count < 3 {
            sink.send([
                "type": "error",
                "kind": "insufficientFeatures",
                "message": "Tap at least three corners before finishing.",
            ])
            return
        }
        sceneView?.session.pause()
        let payload = TapPolygonBridge.toJson(
            polygon: polygon,
            captureId: captureId,
            engine: "arKitPlaneTap"
        )
        sink.send([
            "type": "complete",
            "result": payload,
        ])
        #endif
    }

    func stop() {
        #if canImport(ARKit)
        sceneView?.session.pause()
        #endif
    }

    func resume() {
        #if canImport(ARKit)
        // ARKit recovers tracking from where it left off when the
        // session pause was brief. Tapped points stayed in our Dart-side
        // state, so just kick the session back on.
        sceneView?.session.run(configuration)
        #endif
    }

    func cancel() {
        #if canImport(ARKit)
        sceneView?.session.pause()
        sceneView?.removeFromSuperview()
        sceneView = nil
        tappedPointsXZMeters.removeAll()
        floorY = nil
        #endif
    }

    #if canImport(ARKit)
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = sceneView else { return }
        let point = gesture.location(in: view)
        // Prefer raycasting against detected planes; fall back to the
        // initial floor estimate if we have one.
        if #available(iOS 13.0, *),
           let q = view.raycastQuery(from: point,
                                     allowing: .existingPlaneInfinite,
                                     alignment: .horizontal),
           let hit = view.session.raycast(q).first {
            register(transform: hit.worldTransform)
        } else if let result = view.hitTest(point, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane]).first {
            register(transform: result.worldTransform)
        } else {
            sink.send([
                "type": "guidance",
                "message": "No floor detected here — try another spot",
                "severity": "warn",
            ])
        }
    }

    private func register(transform: simd_float4x4) {
        let position = simd_float3(transform.columns.3.x,
                                   transform.columns.3.y,
                                   transform.columns.3.z)
        if floorY == nil {
            floorY = position.y
        }
        tappedPointsXZMeters.append(SIMD2<Float>(position.x, position.z))
        let cornerNode = addCornerSphere(at: position)
        var edgeNode: SCNNode? = nil
        if tappedPointsXZMeters.count >= 2 {
            edgeNode = addEdgeBetween(
                a: tappedPointsXZMeters[tappedPointsXZMeters.count - 2],
                b: tappedPointsXZMeters.last!,
                y: floorY ?? position.y
            )
        }
        tapNodes.append((corner: cornerNode, edge: edgeNode))
        emitProgress()
    }

    private func emitProgress() {
        sink.send([
            "type": "progress",
            "walls": max(0, tappedPointsXZMeters.count - 1),
            "openings": 0,
            "objects": 0,
        ])
    }

    @discardableResult
    private func addCornerSphere(at position: simd_float3) -> SCNNode {
        let sphere = SCNSphere(radius: 0.04)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(position.x, position.y, position.z)
        sceneView?.scene.rootNode.addChildNode(node)
        return node
    }

    @discardableResult
    private func addEdgeBetween(a: SIMD2<Float>, b: SIMD2<Float>, y: Float) -> SCNNode {
        let line = SCNCylinder(radius: 0.01, height: CGFloat(simd_distance(a, b)))
        line.firstMaterial?.diffuse.contents = UIColor.systemGreen
        let node = SCNNode(geometry: line)
        let mid = SIMD3<Float>((a.x + b.x) / 2, y, (a.y + b.y) / 2)
        node.position = SCNVector3(mid.x, mid.y, mid.z)
        // Rotate cylinder (default axis is Y) to lie along the XZ vector.
        let dx = b.x - a.x
        let dz = b.y - a.y
        let yaw = atan2f(dz, dx)
        // Lay flat — pitch 90° so cylinder axis runs along XZ plane.
        let pitch: Float = .pi / 2
        node.eulerAngles = SCNVector3(pitch, -yaw, 0)
        sceneView?.scene.rootNode.addChildNode(node)
        return node
    }
    #endif

    /// Pop the most recent tap. Removes the SceneKit nodes that visualised
    /// it and emits an updated progress event so the Flutter HUD's wall
    /// counter ticks back down. Returns the new tap count, or 0 when
    /// the engine has no remaining taps. Outside of `canImport(ARKit)`
    /// the engine isn't usable anyway, but we return -1 to match the
    /// protocol's "engine doesn't track taps" contract.
    func undoLastTap() -> Int {
        #if canImport(ARKit)
        guard !tappedPointsXZMeters.isEmpty else { return 0 }
        tappedPointsXZMeters.removeLast()
        if let removed = tapNodes.popLast() {
            removed.corner.removeFromParentNode()
            removed.edge?.removeFromParentNode()
        }
        emitProgress()
        return tappedPointsXZMeters.count
        #else
        return -1
        #endif
    }
}

#if canImport(ARKit)
extension ArKitTapEngine: ARSCNViewDelegate, ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        sink.send([
            "type": "error",
            "kind": "trackingLost",
            "message": error.localizedDescription,
        ])
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .notAvailable:
            sink.send([
                "type": "guidance",
                "message": "Tracking unavailable — move slowly",
                "severity": "warn",
            ])
        case .limited(let reason):
            sink.send([
                "type": "guidance",
                "message": "Tracking limited: \(reason)",
                "severity": "warn",
            ])
        case .normal:
            sink.send([
                "type": "guidance",
                "message": "Tap each corner of the room",
                "severity": "info",
            ])
        }
    }
}
#endif
