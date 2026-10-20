import Foundation
import Testing
@testable import CADCore

private func mill(_ d: Double, shape: CutterShape? = nil, kind: ToolKind = .endMill) -> Tool {
    Tool(name: "T", kind: kind, diameter: d, stepdown: 0.1, stepover: 0.1, feedRate: 60, plungeRate: 20, shape: shape)
}

@Test func bullNoseOutline() throws {
    let t = mill(0.5, shape: .bullNose(cornerRadius: 0.0625))
    #expect(t.heightAboveTip(atRadius: 0) == 0)
    #expect(t.heightAboveTip(atRadius: 0.1875) == 0)          // end of the flat
    #expect(abs(try #require(t.heightAboveTip(atRadius: 0.25)) - 0.0625) < 1e-12) // corner top
    let mid = try #require(t.heightAboveTip(atRadius: 0.1875 + 0.0625 * sin(.pi / 4)))
    #expect(abs(mid - 0.0625 * (1 - cos(.pi / 4))) < 1e-12)
    #expect(t.heightAboveTip(atRadius: 0.26) == nil)
    #expect(abs(t.cutWidth(atDepth: 0.0625) - 0.5) < 1e-9)
    #expect(abs(t.cutWidth(atDepth: 0) - 0.375) < 1e-6)
    #expect(t.shapeSummary == "bull nose r0.0625")
}

@Test func taperedBallNoseOutlineIsSmooth() throws {
    let t = mill(0.25, shape: .taperedBallNose(tipRadius: 0.03125, halfAngle: 5), kind: .ballNose)
    let a = 5 * Double.pi / 180, rb = 0.03125
    let rt = rb * cos(a)
    let below = try #require(t.heightAboveTip(atRadius: rt - 1e-7))
    let above = try #require(t.heightAboveTip(atRadius: rt + 1e-7))
    #expect(abs(below - above) < 1e-5)               // continuous where the cone meets the ball
    let top = try #require(t.heightAboveTip(atRadius: 0.125))
    #expect(abs(top - ((rb - rb * sin(a)) + (0.125 - rt) / tan(a))) < 1e-12)
    #expect(t.heightAboveTip(atRadius: 0.001)! < 1e-4)
}

@Test func formToolOutlineUsesLowestReach() throws {
    // Narrow pilot, flare out, waist in, flare out again (undercut seen from below).
    let pts = [FormToolPoint(height: 0, radius: 0.1), FormToolPoint(height: 0.2, radius: 0.3),
               FormToolPoint(height: 0.3, radius: 0.2), FormToolPoint(height: 0.5, radius: 0.5)]
    let t = mill(1.0, shape: .form(points: pts))
    #expect(t.heightAboveTip(atRadius: 0.05) == 0)
    #expect(abs(try #require(t.heightAboveTip(atRadius: 0.2)) - 0.1) < 1e-12)
    // r = 0.4 is first reached on the last segment (0.2 → 0.5 between heights 0.3 and 0.5).
    let h04 = try #require(t.heightAboveTip(atRadius: 0.4))
    let want: Double = 0.3 + 0.2 * 2.0 / 3.0
    #expect(abs(h04 - want) < 1e-12)
    #expect(t.shape?.problem(toolRadius: 0.5) == nil)
    #expect(CutterShape.form(points: pts).problem(toolRadius: 0.4) != nil)
}

@Test func shapeOnlyAppliesToMatchingKindsAndValidValues() {
    #expect(mill(0.25, shape: .bullNose(cornerRadius: 0.5)).effectiveShape == nil)   // too big
    #expect(mill(0.25, shape: .taperedBallNose(tipRadius: 0.02, halfAngle: 5)).effectiveShape == nil) // end mill
    var v = mill(0.5, shape: .bullNose(cornerRadius: 0.05), kind: .vBit)
    v.angle = 90
    #expect(v.effectiveShape == nil)
    #expect(abs(v.heightAboveTip(atRadius: 0.2)! - 0.2) < 1e-12)
}

@Test func shapeSurvivesCodingAndUnitConversion() throws {
    let t = mill(0.5, shape: .bullNose(cornerRadius: 0.0625))
    let back = try JSONDecoder().decode(Tool.self, from: JSONEncoder().encode(t))
    #expect(back == t)
    #expect(t.converted(to: .millimeter).shape == .bullNose(cornerRadius: 0.0625 * 25.4))
    // Old tool JSON without the key decodes with no shape.
    var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mill(0.25))) as! [String: Any]
    obj.removeValue(forKey: "shape")
    #expect(try JSONDecoder().decode(Tool.self, from: JSONSerialization.data(withJSONObject: obj)).shape == nil)
    // CSV keeps bull-nose and tapered-ball data.
    let tools = [t, mill(0.25, shape: .taperedBallNose(tipRadius: 0.02, halfAngle: 3), kind: .ballNose)]
    let csv = try ToolLibraryExchange.decodeCSV(ToolLibraryExchange.encodeCSV(tools))
    #expect(csv.map(\.shape) == tools.map(\.shape))
}
