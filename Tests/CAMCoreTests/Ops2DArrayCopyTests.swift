import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func arrayed(_ array: ArrayCopySettings?, origin: XYOrigin = .lowerLeft) throws -> (Toolpath, Toolpath, CAMContext) {
    let (ctx, ids) = F.document([ShapeFactory.circle(center: Vec2(2, 2), radius: 0.5)], origin: origin)
    var setup = OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids)
    let base = try AnyOperation.profile(ProfileOperation(setup: setup, params: ProfileParameters(depth: DepthSettings(cutDepth: 0.2))))
        .generate(in: ctx)[0]
    setup.arrayCopy = array
    let tp = try AnyOperation.profile(ProfileOperation(setup: setup, params: ProfileParameters(depth: DepthSettings(cutDepth: 0.2))))
        .generate(in: ctx)[0]
    return (base, tp, ctx)
}

@Test(arguments: [XYOrigin.lowerLeft, .center])
func ops2DArrayCopyRepeatsTheToolpathOnAGrid(origin: XYOrigin) throws {
    let (base, tp, ctx) = try arrayed(ArrayCopySettings(columns: 3, rows: 2, spacingX: 4, spacingY: 3), origin: origin)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(tp.moves.count == base.moves.count * 6)
    #expect(tp.metadata["copies"] == "6 (3 × 2)")
    #expect(tp.metadata["warning"] == nil)
    // Arc centres of the copies sit on the grid (material frame).
    let centres = Set(tp.moves.compactMap { m -> Vec2? in
        switch m {
        case .arcCW(_, let c, _), .arcCCW(_, let c, _):
            let p = ctx.coords.materialXY(fromMachine: c)
            return Vec2((p.x * 1000).rounded() / 1000, (p.y * 1000).rounded() / 1000)
        default: return nil
        }
    })
    #expect(centres == Set([Vec2(2, 2), Vec2(6, 2), Vec2(10, 2), Vec2(2, 5), Vec2(6, 5), Vec2(10, 5)]))
    // Serpentine: the second row starts at the right.
    #expect(ArrayCopySettings(columns: 3, rows: 2, spacingX: 4, spacingY: 3).offsets.map(\.x) == [0, 4, 8, 8, 4, 0])
}

@Test func ops2DArrayCopyWarnsWhenCopiesLeaveTheMaterial() throws {
    // The default job is 24 x 18 in.
    let (_, tp, _) = try arrayed(ArrayCopySettings(columns: 2, rows: 1, spacingX: 30, spacingY: 0))
    #expect(tp.metadata["warning"]?.contains("off the material") == true)
    let (base, single, _) = try arrayed(ArrayCopySettings(columns: 1, rows: 1))
    #expect(single.moves == base.moves)
}
