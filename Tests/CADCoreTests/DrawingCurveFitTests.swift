import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingCurveFitTests {
    @Test func denseCircleBecomesFewArcs() {
        let pts = (0..<360).map { i -> Vec2 in
            let a = Double(i) * .pi / 180
            return Vec2(3 + 2 * cos(a), 1 + 2 * sin(a))
        }
        let fitted = CurveFit.fit(Path(points: pts, closed: true), tolerance: 0.001)
        #expect(fitted.isClosed)
        #expect(fitted.segments.count <= 4)
        #expect(fitted.segments.filter { if case .arc = $0 { return true }; return false }.count >= 2)
        #expect(abs(fitted.signedArea(tolerance: 1e-5) - .pi * 4) < 0.01)
    }

    @Test func polygonWithCollinearPointsBecomesLines() {
        var pts: [Vec2] = []
        for k in 0...10 { pts.append(Vec2(Double(k) * 0.2, 0)) }
        for k in 1...10 { pts.append(Vec2(2, Double(k) * 0.2)) }
        let fitted = CurveFit.fit(Path(points: pts, closed: false), tolerance: 0.001)
        #expect(fitted.segments == [.line(to: Vec2(2, 0)), .line(to: Vec2(2, 2))])
    }

    @Test func mixedLineAndArcStayWithinTolerance() {
        var pts = (0...20).map { Vec2(Double($0) * 0.1, 0) }
        pts += (1...90).map { i -> Vec2 in
            let a = -Double.pi / 2 + Double(i) * .pi / 180
            return Vec2(2 + cos(a), 1 + sin(a))
        }
        let original = Path(points: pts, closed: false)
        let fitted = CurveFit.fit(original, tolerance: 0.002)
        #expect(fitted.segments.count <= 4)
        for p in pts { #expect(VectorValidator.distance(p, toPolyline: fitted.flattened(tolerance: 1e-5)) < 0.003) }
    }
}
