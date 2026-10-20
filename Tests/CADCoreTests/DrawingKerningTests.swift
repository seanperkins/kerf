import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingKerningTests {
    func box(_ p: [Path]) -> Rect2 { Rect2(points: p.flatMap { $0.flattened() }) }

    @Test func zeroAdjustmentMatchesNormalLayout() throws {
        for font in ["Helvetica", StrokeFont.name] {
            var spec = TextSpec(string: "AV\nTo", fontName: font, size: 1, alignment: .center, anchor: Vec2(3, 3))
            let plain = try TextOutliner().outlines(for: spec)
            spec.letterAdjustments = [TextSpec.LetterAdjustment(index: 0)]
            let kerned = try TextOutliner().outlines(for: spec)
            let a = box(plain), b = box(kerned)
            #expect(a.min.isApproximatelyEqual(to: b.min, tolerance: 1e-6) && a.max.isApproximatelyEqual(to: b.max, tolerance: 1e-6))
            #expect(try TextKerning.letterCount(spec) == 4)
        }
    }

    @Test func moveAndRotateOneLetter() throws {
        var spec = TextSpec(string: "AB", fontName: "Helvetica", size: 1)
        let base = try TextOutliner().outlines(for: spec)
        spec.letterAdjustments = [TextSpec.LetterAdjustment(index: 1, offset: Vec2(0, 2))]
        let moved = try TextOutliner().outlines(for: spec)
        #expect(abs(box(moved).max.y - box(base).max.y - 2) < 1e-6)
        spec.letterAdjustments = [TextSpec.LetterAdjustment(index: 0, rotation: 90)]
        let turned = try TextOutliner().outlines(for: spec)
        #expect(box(turned) != box(base))
        // Old specs without adjustments still decode.
        let json = try JSONEncoder().encode(TextSpec(string: "A", fontName: "Helvetica", size: 1))
        #expect(!String(decoding: json, as: UTF8.self).contains("letterAdjustments"))
    }
}
