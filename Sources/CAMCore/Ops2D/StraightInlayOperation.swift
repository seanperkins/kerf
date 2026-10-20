import CADCore
import Foundation

/// Straight-wall inlay with an end mill. An end mill leaves inside corners of a pocket rounded
/// to its radius r and cannot cut the inside corners of a plug's outline sharper than r either.
/// So both parts are cut from the same matched outline M = close(open(S, r), r): convex corners
/// rounded (as the pocket gets them) and concave corners rounded (as the plug gets them). The
/// pocket clears M; the plug is an outside profile of M shrunk by the clearance.
public struct StraightInlayOperation: ToolpathOperation {
    public static let kind = OperationKind.straightInlay
    public var setup: OperationSetup
    public var params: StraightInlayParameters

    public init(setup: OperationSetup, params: StraightInlayParameters = StraightInlayParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let shapes = context.shapes(for: setup)
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        let tol = context.tolerance
        let closed = ShapeGeometry.loops(of: shapes, tolerance: tol).closed
        guard !closed.isEmpty else { throw CAMError.invalidGeometry("Inlays need closed vectors") }
        let matched = Self.matchedOutline(Polygon2D.region(fromLoops: closed), radius: tool.radius, tolerance: tol)
        guard !matched.isEmpty else { throw CAMError.invalidGeometry("The shape is too narrow for the tool") }

        var out: [Toolpath] = []
        if params.part != .male {
            let doc = Self.document(context.document, loops: matched)
            let pocket = PocketOperation(setup: OperationSetup(id: setup.id, name: setup.name, toolID: setup.toolID,
                                                               shapeIDs: doc.shapes.map(\.id)),
                                         params: PocketParameters(depth: DepthSettings(cutDepth: params.pocketDepth,
                                                                                       passDepth: params.passDepth)))
            var ctx = context
            ctx.document = doc
            for var tp in try pocket.generate(in: ctx) {
                tp.kind = .inlay
                tp.name = "\(setup.name) (pocket)"
                tp.metadata["part"] = "female"
                out.append(tp)
            }
        }
        if params.part != .female {
            var plug = params.clearance > 0
                ? GeomKernel.offset(matched, by: -params.clearance, join: .round, arcTolerance: tol)
                : matched
            guard !plug.isEmpty else { throw CAMError.invalidGeometry("The clearance is larger than the shape") }
            if params.mirrorPlug {
                let b = Rect2(points: matched.flatMap { $0 })
                let cx = (b.min.x + b.max.x) / 2
                plug = plug.map { loop in loop.map { Vec2(2 * cx - $0.x, $0.y) }.reversed() }
            }
            let doc = Self.document(context.document, loops: plug)
            let profile = ProfileOperation(setup: OperationSetup(id: setup.id, name: setup.name, toolID: setup.toolID,
                                                                 shapeIDs: doc.shapes.map(\.id)),
                                           params: ProfileParameters(depth: DepthSettings(cutDepth: params.plugDepth,
                                                                                          passDepth: params.passDepth),
                                                                     side: .outside))
            var ctx = context
            ctx.document = doc
            for var tp in try profile.generate(in: ctx) {
                tp.kind = .inlay
                tp.name = "\(setup.name) (plug)"
                tp.metadata["part"] = "male"
                out.append(tp)
            }
        }
        return out
    }

    /// close(open(S, r), r): the outline both parts can be cut to exactly with radius r.
    public static func matchedOutline(_ region: [[Vec2]], radius r: Double, tolerance: Double) -> [[Vec2]] {
        guard r > 0 else { return region }
        func off(_ p: [[Vec2]], _ d: Double) -> [[Vec2]] {
            GeomKernel.offset(p, by: d, join: .round, arcTolerance: tolerance)
        }
        let opened = off(off(region, -r), r)
        return off(off(opened, r), -r).filter { $0.count > 2 }
    }

    /// The job's document with its shapes replaced by one shape of `loops` (closed polylines).
    static func document(_ base: Document, loops: [[Vec2]]) -> Document {
        var d = base
        d.shapes = [Shape(name: "Inlay", layerID: base.defaultLayerID,
                          paths: loops.map { Path(points: $0, closed: true) })]
        return d
    }
}
