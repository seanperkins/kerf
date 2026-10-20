import CADCore
import Foundation

/// Drilling: peck drill at the centre of each selected closed vector (circles) / point.
public struct DrillOperation: ToolpathOperation {
    public static let kind = OperationKind.drill
    public var setup: OperationSetup
    public var params: DrillParameters

    public init(setup: OperationSetup, params: DrillParameters = DrillParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let shapes = context.shapes(for: setup)
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        guard params.cutDepth > params.startDepth + 1e-9 else {
            throw CAMError.invalidParameter("Cut depth must be deeper than start depth")
        }
        let tol = context.tolerance
        let holes = Self.holeCentres(shapes, tolerance: tol)
        guard !holes.isEmpty else { throw CAMError.noGeometry }

        let coords = context.coords
        let start = coords.materialXY(fromMachine: context.document.job.home)
        let ordered = ChainOrdering.nearestNeighbour(holes.map { Chain2D(points: [$0], isClosed: false) }, from: start)
            .map(\.start)

        let job = context.document.job
        // Retract plane between pecks: above the top, never above safe Z.
        let retractDepth = -min(max(params.retractHeight, 0), job.safeZ)
        // Rapid down to this gap above the bottom of the previous peck.
        let gap = min(job.safeZ, context.units == .inch ? 0.02 : 0.5)
        let pecks = Self.peckDepths(start: params.startDepth, end: params.cutDepth, peck: params.peckDepth)
        var moves: [Move] = []
        for p in ordered {
            // Build each hole as explicit moves (no canned cycles) for portability.
            moves.append(.rapid(to: coords.machineAtSafeZ(p)))
            moves.append(.rapid(to: coords.machine(p, depth: retractDepth)))
            var cleared = min(params.startDepth, 0)
            for d in pecks {
                let approach = cleared - gap
                if approach > retractDepth + 1e-9 { moves.append(.rapid(to: coords.machine(p, depth: approach))) }
                moves.append(.linear(to: coords.machine(p, depth: d), feed: tool.plungeRate))
                cleared = d
                if d < pecks.last! - 1e-12 { moves.append(.rapid(to: coords.machine(p, depth: retractDepth))) }
            }
            if params.dwellSeconds > 0 { moves.append(.dwell(seconds: params.dwellSeconds)) }
            moves.append(.rapid(to: coords.machineAtSafeZ(p)))
        }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .drill, tool: tool, moves: moves,
                         metadata: ["holes": "\(ordered.count)"])]
    }

    /// Depths of successive pecks (the last is the cut depth).
    static func peckDepths(start: Double, end: Double, peck: Double) -> [Double] {
        guard peck > 1e-9 else { return [end] }
        var out: [Double] = []
        var d = start
        while d + peck < end - 1e-9 {
            d += peck
            out.append(d)
        }
        out.append(end)
        return out
    }

    /// Exact centre when every segment is an arc around the same point (a drawn circle).
    static func arcCentre(_ path: Path) -> Vec2? {
        var centre: Vec2?
        for seg in path.segments {
            guard case .arc(_, let c, _) = seg else { return nil }
            if let e = centre, !e.isApproximatelyEqual(to: c, tolerance: 1e-9) { return nil }
            centre = c
        }
        return centre
    }

    /// One hole per closed path (centre of its bounds; exact for circles) and per point-like
    /// path (zero-length or single point), de-duplicated (concentric circles = one hole).
    static func holeCentres(_ shapes: [Shape], tolerance: Double) -> [Vec2] {
        var out: [Vec2] = []
        for s in shapes {
            for path in s.paths {
                let b = path.bounds(tolerance: tolerance)
                guard !b.isEmpty else { continue }
                let isPoint = b.width <= tolerance && b.height <= tolerance
                guard path.isClosed || isPoint else { continue }
                let c = Self.arcCentre(path) ?? b.center
                if !out.contains(where: { $0.distance(to: c) <= tolerance }) { out.append(c) }
            }
        }
        return out
    }
}
