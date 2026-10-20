import CADCore
import Foundation
import Testing
@testable import KerfApp

@Suite struct DrawingQuickEntryTests {
    let layer = UUID()

    @Test func parsesValues() {
        #expect(QuickEntry.parse("3") == .one(3))
        #expect(QuickEntry.parse("3, -2.5") == .pair(3, -2.5))
        #expect(QuickEntry.parse("5<30") == .polar(length: 5, degrees: 30))
        #expect(QuickEntry.parse("1,2,3") == nil)
        #expect(QuickEntry.parse("abc") == nil)
        #expect(QuickEntry.accepts("4", buffer: ""))
        #expect(!QuickEntry.accepts(",", buffer: ""))
        #expect(QuickEntry.accepts(",", buffer: "4"))
        #expect(!QuickEntry.accepts("r", buffer: "4"))
    }

    @Test func boxAndRadialShapes() throws {
        let r = try #require(QuickEntry.pair(4, 2).shape(for: .rectangle, anchor: Vec2(1, 1), options: DrawingOptions(), layerID: layer))
        #expect(r.bounds().min == Vec2(1, 1) && r.bounds().max == Vec2(5, 3))
        let left = try #require(QuickEntry.pair(4, 2).shape(for: .rectangle, anchor: Vec2(1, 1), direction: Vec2(-1, 1),
                                                           options: DrawingOptions(), layerID: layer))
        #expect(left.bounds().min.x == -3)
        let c = try #require(QuickEntry.one(1.5).shape(for: .circle, anchor: .zero, options: DrawingOptions(), layerID: layer))
        #expect(c.origin == .circle(radius: 1.5))
        #expect(QuickEntry.polar(length: 1, degrees: 0).shape(for: .rectangle, anchor: .zero, options: DrawingOptions(), layerID: layer) == nil)
    }

    @Test func linePoints() {
        #expect(QuickEntry.pair(2, 3).nextPoint(after: nil, cursor: nil) == Vec2(2, 3))
        #expect(QuickEntry.pair(2, 3).nextPoint(after: Vec2(1, 1), cursor: nil) == Vec2(3, 4))
        let p = QuickEntry.polar(length: 2, degrees: 90).nextPoint(after: Vec2(1, 1), cursor: nil)!
        #expect(p.isApproximatelyEqual(to: Vec2(1, 3), tolerance: 1e-12))
        #expect(QuickEntry.one(5).nextPoint(after: .zero, cursor: Vec2(0, -1)) == Vec2(0, -5))
        #expect(QuickEntry.one(5).nextPoint(after: nil, cursor: Vec2(0, -1)) == nil)
    }
}
