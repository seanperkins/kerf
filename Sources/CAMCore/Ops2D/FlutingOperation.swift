import CADCore
import Foundation

/// Fluting: ramped flutes along open vectors (ball nose / V-bit).
public struct FlutingOperation: ToolpathOperation {
    public static let kind = OperationKind.fluting
    public var setup: OperationSetup
    public var params: FlutingParameters

    public init(setup: OperationSetup, params: FlutingParameters = FlutingParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let shapes = context.shapes(for: setup)
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        let passes = params.depth.passDepths(toolStepdown: tool.stepdown)
        guard !passes.isEmpty else { throw CAMError.invalidParameter("Cut depth must be deeper than start depth") }
        let tol = context.tolerance
        let (closed, open) = ShapeGeometry.loops(of: shapes, tolerance: tol)
        // Flutes run along each vector once; closed vectors are walked from their start point.
        let chains = (open + closed.map { $0 + [$0[0]] }).map { Chain2D(points: $0, isClosed: false) }
            .filter { $0.length > tol }
        guard !chains.isEmpty else { throw CAMError.noGeometry }

        let symmetric = params.ramp == .both
        let coords = context.coords
        let start = coords.materialXY(fromMachine: context.document.job.home)
        let ordered = ChainOrdering.nearestNeighbour(chains, from: start, allowReverse: symmetric, tolerance: tol)
        var b = ToolpathBuilder(coords: coords, tool: tool, units: context.units, tolerance: tol)
        for chain in ordered {
            let forward = ArcLengthChain(chain)
            let backward = ArcLengthChain(chain.reversed())
            for (k, d) in passes.enumerated() {
                // A symmetric flute ends where it started (at start depth): cut back the other way.
                let c = symmetric && k % 2 == 1 ? backward : forward
                b.cutChain(stations(on: c, depth: d).map(\.cutPoint))
            }
            b.retract()
        }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .fluting, tool: tool, moves: b.finish())]
    }

    /// Depth profile along the flute for a pass at `depth`.
    func stations(on c: ArcLengthChain, depth: Double) -> [StationPoint] {
        let L = c.length
        let top = params.depth.startDepth
        let fr = min(max(params.rampFraction, 0), params.ramp == .both ? 0.5 : 1)
        let rampLen = fr * L
        let rampIn = params.ramp != .end && rampLen > 0
        let rampOut = params.ramp != .start && rampLen > 0
        let ease: (Double) -> Double = params.smoothRamp ? { (1 - cos(.pi * $0)) / 2 } : { $0 }
        var breaks: [Double] = []
        let n = params.smoothRamp ? 16 : 1
        for i in 0...n {
            let t = rampLen * Double(i) / Double(n)
            if rampIn { breaks.append(t) }
            if rampOut { breaks.append(L - t) }
        }
        return c.samples(from: 0, to: L, extraBreaks: breaks) { s in
            var f = 1.0
            if rampIn, s < rampLen { f = min(f, ease(s / rampLen)) }
            if rampOut, s > L - rampLen { f = min(f, ease((L - s) / rampLen)) }
            return top + (depth - top) * f
        }
    }
}
