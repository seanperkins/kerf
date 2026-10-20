import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func square(_ x: Double, _ y: Double, _ s: Double = 1) -> [Vec2] {
    [Vec2(x, y), Vec2(x + s, y), Vec2(x + s, y + s), Vec2(x, y + s)]
}

/// Lower-left corners of the squares, in cut order (holes reported with their part).
private func corners(_ chains: [Chain2D]) -> [Vec2] {
    chains.map { c in let b = Rect2(points: c.points); return Vec2(b.min.x.rounded(), b.min.y.rounded()) }
}

private let grid = [square(5, 5), square(1, 1), square(5, 1), square(1, 5)].map { Chain2D(points: $0, isClosed: true) }

@Test func ops2DProfileOrderLeftToRightAndBottomToTop() {
    let lr = ProfileOrdering.ordered(grid, by: .leftToRight, from: .zero, shapeLoops: [], allowReverse: true, tolerance: 1e-4)
    #expect(corners(lr).map(\.x) == [1, 1, 5, 5])
    let bt = ProfileOrdering.ordered(grid, by: .bottomToTop, from: .zero, shapeLoops: [], allowReverse: true, tolerance: 1e-4)
    #expect(corners(bt).map(\.y) == [1, 1, 5, 5])
}

@Test func ops2DProfileOrderGridIsRowsFromTheBottom() {
    let g = ProfileOrdering.ordered(grid, by: .grid, from: .zero, shapeLoops: [], allowReverse: true, tolerance: 1e-4)
    #expect(corners(g) == [Vec2(1, 1), Vec2(5, 1), Vec2(1, 5), Vec2(5, 5)])
}

@Test func ops2DProfileOrderSelectionOrderKeepsHolesWithTheirPart() {
    // Part at (5,5) has a hole; selection order: (5,5) part, then (1,1), then (5,1), then (1,5).
    let hole = Chain2D(points: square(5.3, 5.3, 0.4), isClosed: true)
    let chains = grid + [hole]
    let loops = [[square(5, 5), square(5.3, 5.3, 0.4)], [square(1, 1)], [square(5, 1)], [square(1, 5)]]
    let s = ProfileOrdering.ordered(chains, by: .selection, from: .zero, shapeLoops: loops, allowReverse: true, tolerance: 1e-4)
    #expect(corners(s) == [Vec2(5, 5), Vec2(5, 5), Vec2(1, 1), Vec2(5, 1), Vec2(1, 5)])
    // The hole (smaller) comes first.
    #expect(Rect2(points: s[0].points).width < 1)
}

@Test func ops2DProfileOperationFollowsSelectionOrder() throws {
    let paths = [F.rect(6, 1, 1, 1), F.rect(1, 1, 1, 1), F.rect(3, 1, 1, 1)]
    let (ctx, ids) = F.document(paths)
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.1))
    p.order = .selection
    let tp = try ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
        .generate(in: ctx)[0]
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    var seq: [Double] = []
    for q in F.densePoints(tp.moves) where q.z < -1e-9 {
        let x = [6.5, 1.5, 3.5].min { abs($0 - q.xy.x) < abs($1 - q.xy.x) }!
        if seq.last != x { seq.append(x) }
    }
    #expect(seq == [6.5, 1.5, 3.5])
}
