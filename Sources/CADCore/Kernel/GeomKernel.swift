import CGeom
import Foundation

/// Swift face of the CGeom C++ wrapper (Clipper2 offsets/booleans, Boost Voronoi).
/// Polygons are flattened point loops (no repeated closing point).
public enum GeomKernel {
    public enum Join: Sendable { case round, miter(limit: Double), square, bevel }
    public enum EndType: Sendable { case closedPolygon, openButt, openSquare, openRound, openJoined }
    public enum BooleanOp: Sendable { case union, intersection, difference, xor }
    public enum FillRule: Sendable { case evenOdd, nonZero, positive, negative }

    /// Decimal places kept by Clipper (coordinates are scaled by 10^precision to int64).
    public static let defaultPrecision: Int32 = 6

    /// Offset closed polygons (positive delta grows, negative shrinks) or open polylines.
    public static func offset(_ paths: [[Vec2]], by delta: Double, join: Join = .round,
                              end: EndType = .closedPolygon, arcTolerance: Double = 0,
                              precision: Int32 = defaultPrecision) -> [[Vec2]] {
        let (xy, counts) = flatten(paths)
        var miter = 2.0
        let j: kg_join_type
        switch join {
        case .round: j = KG_JOIN_ROUND
        case .miter(let limit): j = KG_JOIN_MITER; miter = limit
        case .square: j = KG_JOIN_SQUARE
        case .bevel: j = KG_JOIN_BEVEL
        }
        let e: kg_end_type
        switch end {
        case .closedPolygon: e = KG_END_POLYGON
        case .openButt: e = KG_END_BUTT
        case .openSquare: e = KG_END_SQUARE
        case .openRound: e = KG_END_ROUND
        case .openJoined: e = KG_END_JOINED
        }
        guard let r = kg_offset(xy, counts, Int32(counts.count), delta, j, e, miter, arcTolerance, precision)
        else { return [] }
        defer { kg_paths_free(r) }
        return unflatten(r)
    }

    /// Boolean of closed `subject` polygons with closed `clip` polygons. When
    /// `subjectsOpen` is true the subjects are open polylines and the clipped
    /// polylines are returned (useful for raster clearing).
    public static func boolean(_ op: BooleanOp, subject: [[Vec2]], clip: [[Vec2]],
                               fillRule: FillRule = .nonZero, subjectsOpen: Bool = false,
                               precision: Int32 = defaultPrecision) -> [[Vec2]] {
        let (sxy, sc) = flatten(subject)
        let (cxy, cc) = flatten(clip)
        let o: kg_bool_op
        switch op {
        case .union: o = KG_OP_UNION
        case .intersection: o = KG_OP_INTERSECTION
        case .difference: o = KG_OP_DIFFERENCE
        case .xor: o = KG_OP_XOR
        }
        let f: kg_fill_rule
        switch fillRule {
        case .evenOdd: f = KG_FILL_EVENODD
        case .nonZero: f = KG_FILL_NONZERO
        case .positive: f = KG_FILL_POSITIVE
        case .negative: f = KG_FILL_NEGATIVE
        }
        guard let r = kg_boolean(o, f, sxy, sc, Int32(sc.count), subjectsOpen ? 1 : 0,
                                 cxy, cc, Int32(cc.count), precision) else { return [] }
        defer { kg_paths_free(r) }
        return unflatten(r)
    }

    /// Voronoi diagram of points and non-crossing segments.
    /// - Parameters:
    ///   - scale: integer snapping grid = 1/scale document units (10000 for inch, 1000 for mm).
    ///   - maxSampleStep: max spacing of edge samples.
    public static func voronoi(points: [Vec2] = [], segments: [(Vec2, Vec2)], scale: Double = 10000,
                               maxSampleStep: Double = 0.01) -> VoronoiDiagram {
        let p = points.flatMap { [$0.x, $0.y] }
        let s = segments.flatMap { [$0.0.x, $0.0.y, $0.1.x, $0.1.y] }
        guard let vd = kg_voronoi_build(p, Int32(points.count), s, Int32(segments.count), scale, maxSampleStep)
        else { return VoronoiDiagram(vertices: [], edges: [], samples: []) }
        defer { kg_voronoi_free(vd) }
        func pts(_ base: UnsafePointer<kg_vpoint>?, _ n: Int32) -> [VoronoiDiagram.Point] {
            guard let base else { return [] }
            return (0..<Int(n)).map { VoronoiDiagram.Point(position: Vec2(base[$0].x, base[$0].y), radius: base[$0].radius) }
        }
        let verts = pts(kg_voronoi_vertices(vd), kg_voronoi_vertex_count(vd))
        let samples = pts(kg_voronoi_samples(vd), kg_voronoi_sample_count(vd))
        var edges: [VoronoiDiagram.Edge] = []
        if let eb = kg_voronoi_edges(vd) {
            let n = Int(kg_voronoi_edge_count(vd))
            edges.reserveCapacity(n)
            for i in 0..<n {
                let e = eb[i]
                let kind = VoronoiDiagram.SiteKind(rawValue: Int(e.siteKind)) ?? .segment
                edges.append(VoronoiDiagram.Edge(
                    vertex0: e.v0 >= 0 ? Int(e.v0) : nil, vertex1: e.v1 >= 0 ? Int(e.v1) : nil,
                    twin: Int(e.twin), siteIndex: Int(e.siteIndex), siteKind: kind,
                    isPrimary: e.isPrimary != 0, isCurved: e.isCurved != 0,
                    samples: Int(e.sampleStart)..<Int(e.sampleStart + e.sampleCount)))
            }
        }
        return VoronoiDiagram(vertices: verts, edges: edges, samples: samples)
    }

    // MARK: - Marshalling

    static func flatten(_ paths: [[Vec2]]) -> ([Double], [Int32]) {
        var xy: [Double] = []
        xy.reserveCapacity(paths.reduce(0) { $0 + $1.count * 2 })
        var counts: [Int32] = []
        for p in paths {
            counts.append(Int32(p.count))
            for v in p { xy.append(v.x); xy.append(v.y) }
        }
        return (xy, counts)
    }

    static func unflatten(_ r: OpaquePointer) -> [[Vec2]] {
        (0..<kg_paths_count(r)).map { i in
            let n = Int(kg_paths_point_count(r, i))
            guard let p = kg_paths_points(r, i) else { return [] }
            return (0..<n).map { Vec2(p[2 * $0], p[2 * $0 + 1]) }
        }
    }
}

/// Result of `GeomKernel.voronoi`. Half-edge structure: each edge has a twin.
public struct VoronoiDiagram: Sendable {
    public enum SiteKind: Int, Sendable { case point = 0, segmentStart = 1, segmentEnd = 2, segment = 3 }

    public struct Point: Hashable, Sendable {
        public var position: Vec2
        /// Distance to the nearest input site (inscribed-circle radius).
        public var radius: Double
    }

    public struct Edge: Hashable, Sendable {
        public var vertex0: Int?
        public var vertex1: Int?
        public var twin: Int
        /// Index of the input point or segment whose cell this half-edge bounds.
        public var siteIndex: Int
        public var siteKind: SiteKind
        /// False for secondary edges (between a segment and its own endpoint).
        public var isPrimary: Bool
        public var isCurved: Bool
        /// Range into `samples` (empty for infinite edges). Ordered vertex0 → vertex1.
        public var samples: Range<Int>
        public var isFinite: Bool { vertex0 != nil && vertex1 != nil }
    }

    public var vertices: [Point]
    public var edges: [Edge]
    public var samples: [Point]

    public func samples(of edge: Edge) -> ArraySlice<Point> { samples[edge.samples] }
}
