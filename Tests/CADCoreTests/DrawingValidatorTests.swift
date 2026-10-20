import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingValidatorTests {
    let layer = UUID()
    let tol = 0.001

    func shape(_ paths: [Path]) -> Shape { Shape(layerID: layer, paths: paths) }
    func square(_ x: Double = 0, _ s: Double = 1) -> Path {
        Path(points: [Vec2(x, 0), Vec2(x + s, 0), Vec2(x + s, s), Vec2(x, s)], closed: true)
    }
    func kinds(_ shapes: [Shape]) -> [VectorIssue.Kind] { VectorValidator.check(shapes, tolerance: tol).map(\.kind) }

    @Test func cleanSquareHasNoIssues() {
        #expect(kinds([shape([square()])]).isEmpty)
    }

    @Test func detectsOpenAndNearlyClosed() {
        let open = Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)], closed: false)
        let nearly = Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 0.005)], closed: false)
        #expect(kinds([shape([open])]) == [.open])
        #expect(kinds([shape([nearly])]) == [.nearlyClosed])
        #expect(VectorValidator.check([shape([open])], tolerance: tol, includeOpen: false).isEmpty)
        let ns = shape([nearly]); let fixed = VectorValidator.fix([ns], issues: VectorValidator.check([ns], tolerance: tol), tolerance: tol)
        #expect(fixed[0].paths[0].isClosed)
        #expect(kinds(fixed).isEmpty)
    }

    @Test func detectsAndRemovesZeroLength() {
        let dot = Path(points: [Vec2(1, 1), Vec2(1, 1)], closed: false)
        let stutter = Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)], closed: true)
        let shapes = [shape([dot]), shape([stutter]), shape([])]
        let issues = VectorValidator.check(shapes, tolerance: tol)
        #expect(Set(issues.map(\.kind)) == [.zeroLength, .zeroLengthSegments])
        let fixed = VectorValidator.fix(shapes, issues: issues, tolerance: tol)
        #expect(fixed.count == 1)
        #expect(fixed[0].paths[0].segments.count == 3)
        #expect(kinds(fixed).isEmpty)
    }

    @Test func detectsSelfIntersectionAndSplitsIt() {
        let bowtie = Path(points: [Vec2(0, 0), Vec2(2, 2), Vec2(2, 0), Vec2(0, 2)], closed: true)
        let bs = shape([bowtie]); let issues = VectorValidator.check([bs], tolerance: tol)
        #expect(issues.map(\.kind) == [.selfIntersecting])
        #expect(issues[0].location!.isApproximatelyEqual(to: Vec2(1, 1), tolerance: 1e-9))
        let fixed = VectorValidator.fix([bs], issues: issues, tolerance: tol)
        #expect(fixed[0].paths.count == 2)
        #expect(kinds(fixed).isEmpty)
    }

    @Test func detectsDuplicatesAndOverlaps() {
        let a = shape([square()])
        let b = shape([square().reversed()])                  // same outline, other direction
        let edge = shape([Path(points: [Vec2(0.2, 0), Vec2(0.8, 0)], closed: false)])  // lies on a's bottom edge
        let other = shape([square(3)])
        let issues = VectorValidator.duplicates([a, b, edge, other], tolerance: tol)
        #expect(issues.count == 2)
        #expect(Set(issues.map(\.shapeID)) == [b.id, edge.id])
        let fixed = VectorValidator.fix([a, b, edge, other], issues: issues, tolerance: tol)
        #expect(fixed.map(\.id) == [a.id, other.id])
    }

    @Test func adjacentButSeparateShapesAreNotDuplicates() {
        #expect(VectorValidator.duplicates([shape([square(0)]), shape([square(1)])], tolerance: tol).isEmpty)
    }
}
