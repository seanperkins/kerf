import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingTextureTests {
    let square = Path(points: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 2), Vec2(0, 2)], closed: true)

    @Test func linesFillTheBoundaryAtTheSpacing() {
        var o = VectorTexture.Options()
        o.pattern = .lines
        o.spacing = 0.5
        let lines = VectorTexture.fill([square], options: o, tolerance: 0.001)
        // Horizontal lines every 0.5 across a 2-tall box: about 4 inside.
        #expect(lines.count >= 3 && lines.count <= 5)
        for l in lines {
            let b = l.bounds()
            #expect(b.min.x >= -1e-6 && b.max.x <= 4 + 1e-6 && abs(b.width - 4) < 1e-6)
        }
    }

    @Test func wavesStayInsideAndVariationIsRepeatable() {
        var o = VectorTexture.Options()
        o.spacing = 0.3
        o.amplitude = 0.1
        o.angle = 30
        o.variation = 0.5
        let a = VectorTexture.fill([square], options: o, tolerance: 0.001)
        #expect(!a.isEmpty)
        for p in a.flatMap({ $0.flattened() }) { #expect(p.x > -1e-6 && p.x < 4 + 1e-6 && p.y > -1e-6 && p.y < 2 + 1e-6) }
        #expect(VectorTexture.fill([square], options: o, tolerance: 0.001) == a)
        o.pattern = .zigzag
        #expect(!VectorTexture.fill([square], options: o, tolerance: 0.001).isEmpty)
    }
}
