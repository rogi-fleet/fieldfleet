import Foundation
import simd

/// Converts a list of tapped XZ floor points (metres) into a
/// FloorPlanScanResult-shaped JSON payload. Used by the manual-tap engines
/// (ARKit on iOS, ARCore on Android via a parallel implementation).
enum TapPolygonBridge {
    static func toJson(
        polygon: [SIMD2<Float>],
        captureId: String,
        engine: String
    ) -> [String: Any] {
        let ccw = ensureCCW(polygon)
        let polyJson: [[String: Any]] = ccw.map { p in
            ["x": Double(p.x), "y": Double(p.y)]
        }
        let roomId = UUID().uuidString
        let room: [String: Any] = [
            "id": roomId,
            "label": NSNull(),
            "floorPolygonMeters": polyJson,
            "roomToWorld": ["x": 0, "y": 0, "yaw": 0],
        ]
        return [
            "captureId": captureId,
            "engine": engine,
            "confidence": 0.5,
            "rooms": [room],
            "openings": [],
            "objects": [],
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    private static func ensureCCW(_ polygon: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var sum: Float = 0
        for i in 0..<polygon.count {
            let p = polygon[i]
            let q = polygon[(i + 1) % polygon.count]
            sum += (q.x - p.x) * (q.y + p.y)
        }
        return sum > 0 ? polygon.reversed() : polygon
    }
}
