import Foundation
import simd

#if canImport(RoomPlan)
import RoomPlan
#endif

/// Translates RoomPlan's `CapturedRoom` into the FloorPlanScanResult JSON
/// the Dart side knows how to parse.
///
/// Polygon extraction: each wall surface is projected to the floor plane
/// (y = 0 in the capture world) as a 2D segment between its endpoints,
/// computed from `transform * (±dimensions.x/2, 0, 0)`. Endpoints within
/// `MERGE_TOLERANCE_M` are merged into a single graph node; the resulting
/// planar graph is walked to produce a single closed polygon. If the walk
/// can't close (graph not Eulerian etc.), the convex hull of all wall
/// endpoints is used as a degenerate fallback so the user always gets
/// *something* to edit.
enum CapturedRoomBridge {
    static let mergeToleranceMeters: Float = 0.10  // 10 cm

    #if canImport(RoomPlan)
    /// Multi-room JSON: each CapturedRoom is converted via `toJson`
    /// and the rooms / openings / objects arrays are unioned. We keep
    /// every per-room polygon in the shared AR world frame (transforms
    /// from RoomPlan are already in that frame), so the Dart side's
    /// ScanToScene.convert places them at the right relative positions
    /// when it applies their (identity) roomToWorld poses.
    ///
    /// Confidence is the average of per-room averages; ceiling height
    /// is the mean of per-room ceiling estimates.
    @available(iOS 16.0, *)
    static func toJsonMultiRoom(
        _ rooms: [CapturedRoom],
        captureId: String
    ) -> [String: Any] {
        if rooms.isEmpty {
            return [
                "captureId": captureId,
                "engine": "roomPlan",
                "confidence": 0,
                "rooms": [],
                "openings": [],
                "objects": [],
                "capturedAt": ISO8601DateFormatter().string(from: Date()),
            ]
        }
        var allRooms: [[String: Any]] = []
        var allOpenings: [[String: Any]] = []
        var allObjects: [[String: Any]] = []
        var confidenceSum: Double = 0
        var ceilingSum: Double = 0
        var ceilingCount: Int = 0

        for room in rooms {
            let perRoom = toJson(room, captureId: captureId)
            if let rs = perRoom["rooms"] as? [[String: Any]] {
                allRooms.append(contentsOf: rs)
            }
            if let os = perRoom["openings"] as? [[String: Any]] {
                allOpenings.append(contentsOf: os)
            }
            if let obs = perRoom["objects"] as? [[String: Any]] {
                allObjects.append(contentsOf: obs)
            }
            confidenceSum += (perRoom["confidence"] as? Double) ?? 0.5
            if let ch = perRoom["ceilingHeightMeters"] as? Double {
                ceilingSum += ch
                ceilingCount += 1
            }
        }
        var payload: [String: Any] = [
            "captureId": captureId,
            "engine": "roomPlan",
            "confidence": confidenceSum / Double(rooms.count),
            "rooms": allRooms,
            "openings": allOpenings,
            "objects": allObjects,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if ceilingCount > 0 {
            payload["ceilingHeightMeters"] = ceilingSum / Double(ceilingCount)
        }
        return payload
    }

    @available(iOS 16.0, *)
    static func toJson(_ room: CapturedRoom, captureId: String) -> [String: Any] {
        let walls = room.walls
        let wallSegments = walls.map { wallSegment(from: $0) }

        let (polygon, _, fellBackToHull) = mergeAndWalk(wallSegments)
        // When the bridge couldn't form a confident wall loop and used
        // the convex hull instead, clamp confidence to 0.3 so the
        // review sheet shows the "Low confidence — verify dimensions"
        // banner. A 99% confident set of walls that can't form a loop
        // is still a low-confidence *room shape*.
        let rawConfidence = averageConfidence(room)
        let avgConfidence = fellBackToHull
            ? min(rawConfidence, 0.3)
            : rawConfidence
        let ceilingHeight = estimateCeilingHeight(walls)
        let perWallHeights = perWallHeightsForPolygon(polygon: polygon, walls: walls)

        let roomId = room.identifier.uuidString
        var scannedRoom: [String: Any] = [
            "id": roomId,
            "label": NSNull(),
            "floorPolygonMeters": polygon.map { ["x": $0.x, "y": $0.y] },
            "roomToWorld": ["x": 0, "y": 0, "yaw": 0],
        ]
        if let perWallHeights = perWallHeights {
            scannedRoom["perWallHeightsMeters"] = perWallHeights
        }

        // Openings: doors, windows, openings — each placed on the nearest
        // wall edge of the polygon.
        var openings: [[String: Any]] = []
        let doors = room.doors.map { (kind: "door", surface: $0) }
        let windows = room.windows.map { (kind: "window", surface: $0) }
        let plain = room.openings.map { (kind: "opening", surface: $0) }
        for (kind, surface) in doors + windows + plain {
            guard let placement = placeOpening(surface, on: polygon) else { continue }
            openings.append([
                "kind": kind,
                "roomId": roomId,
                "wallEdgeIndex": placement.edgeIndex,
                "offsetAlongWall": placement.offsetMeters,
                "widthMeters": Double(surface.dimensions.x),
                "heightMeters": Double(surface.dimensions.y),
                "sillHeightMeters": kind == "door" ? 0 : max(0, Double(surface.transform.columns.3.y - surface.dimensions.y / 2)),
            ])
        }

        var objects: [[String: Any]] = []
        for obj in room.objects {
            objects.append([
                "id": obj.identifier.uuidString,
                "category": objectCategoryName(obj.category),
                "pose": [
                    "x": Double(obj.transform.columns.3.x),
                    "y": Double(obj.transform.columns.3.z),
                    "yaw": Double(yawFromTransform(obj.transform)),
                ],
                "sizeMeters": [
                    "x": Double(obj.dimensions.x),
                    "y": Double(obj.dimensions.y),
                    "z": Double(obj.dimensions.z),
                ],
            ])
        }

        let now = ISO8601DateFormatter().string(from: Date())
        return [
            "captureId": captureId,
            "engine": "roomPlan",
            "confidence": avgConfidence,
            "rooms": [scannedRoom],
            "openings": openings,
            "objects": objects,
            "ceilingHeightMeters": ceilingHeight as Any,
            "capturedAt": now,
        ]
    }

    // MARK: - Wall geometry

    @available(iOS 16.0, *)
    private static func wallSegment(from wall: CapturedRoom.Surface) -> (a: SIMD2<Float>, b: SIMD2<Float>) {
        // The wall's local X axis is its length axis; ±width/2 gives the
        // two endpoints in local space.
        let halfW = wall.dimensions.x / 2
        let local = [SIMD4<Float>(-halfW, 0, 0, 1), SIMD4<Float>(halfW, 0, 0, 1)]
        let worldA = wall.transform * local[0]
        let worldB = wall.transform * local[1]
        return (SIMD2<Float>(worldA.x, worldA.z), SIMD2<Float>(worldB.x, worldB.z))
    }

    @available(iOS 16.0, *)
    private static func averageConfidence(_ room: CapturedRoom) -> Double {
        let scores: [Double] = room.walls.map { confidenceScore($0.confidence) }
            + room.doors.map { confidenceScore($0.confidence) }
            + room.windows.map { confidenceScore($0.confidence) }
        guard !scores.isEmpty else { return 0.7 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    @available(iOS 16.0, *)
    private static func confidenceScore(_ c: CapturedRoom.Confidence) -> Double {
        switch c {
        case .high: return 0.95
        case .medium: return 0.7
        case .low: return 0.4
        @unknown default: return 0.5
        }
    }

    @available(iOS 16.0, *)
    private static func estimateCeilingHeight(_ walls: [CapturedRoom.Surface]) -> Double? {
        let heights = walls.map { Double($0.dimensions.y) }.filter { $0 > 1.5 && $0 < 6 }
        guard !heights.isEmpty else { return nil }
        return heights.reduce(0, +) / Double(heights.count)
    }

    /// Per-polygon-edge wall heights, in metres. Each output entry is the
    /// height of the wall surface closest to the midpoint of edge `i`.
    /// If no wall sits within `matchTolerance` of the midpoint, that
    /// edge gets NaN so the Dart side knows to fall back to the scene
    /// default for it. Returns nil if no walls were captured.
    @available(iOS 16.0, *)
    private static func perWallHeightsForPolygon(
        polygon: [SIMD2<Float>],
        walls: [CapturedRoom.Surface]
    ) -> [Double]? {
        guard !walls.isEmpty, polygon.count >= 3 else { return nil }
        let segments = walls.map { (segment: wallSegment(from: $0), height: Double($0.dimensions.y)) }
        let matchTolerance: Float = 0.5  // 50 cm — generous, picks up after merge wobble

        var heights: [Double] = []
        heights.reserveCapacity(polygon.count)
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let mid = (a + b) / 2

            var bestDistance: Float = .greatestFiniteMagnitude
            var bestHeight: Double = .nan
            for entry in segments {
                let projection = projectPointToSegment(mid, entry.segment.a, entry.segment.b)
                if projection.distance < bestDistance {
                    bestDistance = projection.distance
                    bestHeight = entry.height
                }
            }
            heights.append(bestDistance <= matchTolerance ? bestHeight : Double.nan)
        }
        return heights
    }

    private static func projectPointToSegment(
        _ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>
    ) -> (point: SIMD2<Float>, distance: Float) {
        let ab = b - a
        let len2 = simd_dot(ab, ab)
        if len2 < 1e-6 { return (a, simd_distance(a, p)) }
        let t = max(0, min(1, simd_dot(p - a, ab) / len2))
        let proj = a + t * ab
        return (proj, simd_distance(proj, p))
    }
    #endif

    // MARK: - Object category mapping

    #if canImport(RoomPlan)
    @available(iOS 16.0, *)
    private static func objectCategoryName(_ c: CapturedRoom.Object.Category) -> String {
        switch c {
        case .bed: return "bed"
        case .chair: return "chair"
        case .sofa: return "sofa"
        case .table: return "table"
        case .storage: return "storage"
        case .refrigerator: return "refrigerator"
        case .stove: return "stove"
        case .sink: return "sink"
        case .toilet: return "toilet"
        case .bathtub: return "bathtub"
        case .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .washerDryer: return "washer"
        case .fireplace: return "fireplace"
        case .television: return "television"
        case .stairs: return "stairs"
        @unknown default: return "other"
        }
    }
    #endif

    // MARK: - Planar graph walk

    /// Merges endpoints within `mergeToleranceMeters` and walks the resulting
    /// graph to produce a closed polygon. Falls back to a convex hull when
    /// the graph can't form a single cycle. `fellBackToHull` is true when
    /// the result is the hull (lower confidence — caller should surface).
    static func mergeAndWalk(_ segments: [(a: SIMD2<Float>, b: SIMD2<Float>)]) -> (polygon: [SIMD2<Float>], lookup: [Int], fellBackToHull: Bool) {
        if segments.isEmpty { return ([], [], false) }

        // 1. Union-find on endpoints.
        var nodes: [SIMD2<Float>] = []
        var nodeForSegmentEndpoint: [(Int, Int)] = []
        for seg in segments {
            let ia = mergeOrAdd(nodes: &nodes, point: seg.a, tolerance: mergeToleranceMeters)
            let ib = mergeOrAdd(nodes: &nodes, point: seg.b, tolerance: mergeToleranceMeters)
            nodeForSegmentEndpoint.append((ia, ib))
        }

        // 2. Build adjacency list.
        var adj: [Int: [Int]] = [:]
        for (ia, ib) in nodeForSegmentEndpoint {
            if ia == ib { continue }
            adj[ia, default: []].append(ib)
            adj[ib, default: []].append(ia)
        }

        // 3. Walk: pick a start with at least one neighbour, follow the
        // graph keeping rightmost turns until we return to start. This is
        // sufficient for the polygon-of-walls case where every node has
        // exactly two neighbours.
        guard let start = adj.first(where: { $0.value.count >= 2 })?.key else {
            return (convexHull(nodes), Array(0..<nodes.count), true)
        }

        var ordered: [Int] = [start]
        var visitedEdges = Set<UInt64>()
        var current = start
        var previous: Int? = nil
        let maxIter = nodes.count * 4
        var iterations = 0
        while iterations < maxIter {
            iterations += 1
            let neighbours = adj[current] ?? []
            // Pick the next neighbour that is not the one we came from and
            // whose edge we haven't traversed.
            let next = neighbours.first { n in
                if let prev = previous, n == prev { return false }
                return !visitedEdges.contains(edgeKey(current, n))
            } ?? neighbours.first(where: { $0 != previous })
            guard let n = next else { break }
            visitedEdges.insert(edgeKey(current, n))
            if n == start { break }
            ordered.append(n)
            previous = current
            current = n
        }

        // If we didn't close back to start, fall back to convex hull so
        // the user always gets a usable polygon — but signal the
        // confidence drop.
        if ordered.count < 3 {
            return (convexHull(nodes), Array(0..<nodes.count), true)
        }

        let polygon = ordered.map { nodes[$0] }
        return (ensureCCW(polygon), ordered, false)
    }

    private static func mergeOrAdd(nodes: inout [SIMD2<Float>], point: SIMD2<Float>, tolerance: Float) -> Int {
        for (i, n) in nodes.enumerated() {
            if simd_distance(n, point) <= tolerance {
                // Average in to denoise.
                nodes[i] = (n + point) / 2
                return i
            }
        }
        nodes.append(point)
        return nodes.count - 1
    }

    private static func edgeKey(_ a: Int, _ b: Int) -> UInt64 {
        let lo = UInt64(min(a, b))
        let hi = UInt64(max(a, b))
        return (hi << 32) | lo
    }

    private static func ensureCCW(_ polygon: [SIMD2<Float>]) -> [SIMD2<Float>] {
        // Signed shoelace area: positive = CCW in the y-up sense we use.
        var sum: Float = 0
        for i in 0..<polygon.count {
            let p = polygon[i]
            let q = polygon[(i + 1) % polygon.count]
            sum += (q.x - p.x) * (q.y + p.y)
        }
        // Apple's transforms put +z toward the camera in capture-world; we
        // flatten to (x, z). When that produces CW we reverse.
        if sum > 0 {
            return polygon.reversed()
        }
        return polygon
    }

    private static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        // Andrew's monotone chain. Returns CCW hull.
        let sorted = points.sorted { lhs, rhs in
            lhs.x != rhs.x ? lhs.x < rhs.x : lhs.y < rhs.y
        }
        if sorted.count <= 1 { return sorted }

        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [SIMD2<Float>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [SIMD2<Float>] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    // MARK: - Opening placement

    #if canImport(RoomPlan)
    @available(iOS 16.0, *)
    private static func placeOpening(
        _ surface: CapturedRoom.Surface,
        on polygon: [SIMD2<Float>]
    ) -> (edgeIndex: Int, offsetMeters: Double)? {
        guard polygon.count >= 3 else { return nil }
        let centre = SIMD2<Float>(surface.transform.columns.3.x, surface.transform.columns.3.z)
        var bestEdge = 0
        var bestDist = Float.greatestFiniteMagnitude
        var bestOffset: Float = 0
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let ab = b - a
            let len2 = simd_dot(ab, ab)
            guard len2 > 1e-6 else { continue }
            let t = max(0, min(1, simd_dot(centre - a, ab) / len2))
            let proj = a + t * ab
            let d = simd_distance(centre, proj)
            if d < bestDist {
                bestDist = d
                bestEdge = i
                bestOffset = t * sqrt(len2)
            }
        }
        // Drop openings that don't sit close to *any* wall — they are
        // probably interior placements (e.g. open doorway in middle of a
        // room) that the editor can't render meaningfully without holes.
        if bestDist > 0.6 { return nil }
        return (bestEdge, Double(bestOffset))
    }
    #endif

    private static func yawFromTransform(_ t: simd_float4x4) -> Float {
        // Yaw around y from the upper-3x3 rotation: angle of +x axis in XZ.
        let x = t.columns.0
        return atan2f(x.z, x.x)
    }
}
