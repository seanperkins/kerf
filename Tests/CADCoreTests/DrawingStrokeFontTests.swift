import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingStrokeFontTests {
    @Test func everyPrintableCharacterHasStrokes() {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;-_+=/!?'\"()#&"
        for c in chars {
            let g = StrokeFont.glyph(c)
            #expect(!g.strokes.isEmpty, "missing \(c)")
            for s in g.strokes { #expect(s.count >= 2) }
        }
    }

    @Test func capHeightAndOpenStrokes() {
        let paths = StrokeFont.outlines(for: "HELLO", size: 2, origin: Vec2(1, 1))
        let b = Rect2(points: paths.flatMap { $0.flattened() })
        #expect(abs(b.min.y - 1) < 1e-9 && abs(b.max.y - 3) < 1e-9)
        #expect(abs(b.min.x - 1) < 1e-9)
        #expect(paths.contains { !$0.isClosed })
        #expect(paths.contains { $0.isClosed })  // the O
        // Lowercase uses the capitals; unknown characters fall back to "?".
        #expect(StrokeFont.outlines(for: "hello", size: 2, origin: Vec2(1, 1)) == paths)
        #expect(!StrokeFont.outlines(for: "~", size: 1, origin: .zero).isEmpty)
    }

    @Test func centredAndLiveSpecRouting() throws {
        let c = StrokeFont.outlines(for: "AB", size: 1, origin: .zero, alignment: .center)
        #expect(abs(Rect2(points: c.flatMap { $0.flattened() }).center.x) < 1e-9)
        let spec = TextSpec(string: "AB", fontName: StrokeFont.name, size: 1, anchor: Vec2(5, 5))
        let s = try TextOutliner().shape(for: spec, layerID: UUID())
        #expect(s.paths.count == 4 && s.text == spec)  // two strokes each
        #expect(try TextOutliner().glyphs(for: "AB", fontName: StrokeFont.name, size: 1).count == 2)
    }
}
