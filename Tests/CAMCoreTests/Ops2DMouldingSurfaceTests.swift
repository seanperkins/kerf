import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// Section: a 45° chamfer 0.3 wide and 0.3 deep, then flat at 0.3 for another 0.2.
private let sectionPath = Path(points: [Vec2(20, 10), Vec2(20.3, 9.7), Vec2(20.5, 9.7)], closed: false)
private func sectionDepth(_ t: Double) -> Double { t <= 0 ? 0 : (t >= 0.3 ? 0.3 : t) }

private func ballNose() -> Tool { ToolLibrary.seeded.tools[3] } // 1/4" ball nose

/// Checks every cut point against the true swept surface around it (2D, sampled disk).
private func maxGouge(_ tp: Toolpath, ctx: CAMContext, tool: Tool, surface: (Vec2) -> Double) -> Double {
    var worst = 0.0
    let r = tool.radius
    for p in F.densePoints(tp.moves) {
        let xy = ctx.coords.materialXY(fromMachine: p.xy)
        let tip = ctx.coords.depth(ofMachineZ: p.z)
        guard tip > 1e-9 else { continue }
        for ring in 0...6 {
            let rr = r * Double(ring) / 6
            for k in 0..<24 {
                let a = Double(k) / 24 * 2 * .pi
                let q = xy + Vec2(cos(a), sin(a)) * rr
                let cutDepth = tip - tool.heightAboveTip(atRadius: rr)!
                worst = max(worst, cutDepth - surface(q))
            }
        }
    }
    return worst
}

@Test func ops2DMouldingCurvedClosedRailDoesNotGouge() throws {
    let center = Vec2(5, 5), radius = 2.0
    let rail = ShapeFactory.circle(center: center, radius: radius)
    let (ctx, ids) = F.document([rail, sectionPath])
    let tool = ballNose()
    let p = MouldingParameters(sectionShapeID: ids[1], stepover: 0.03, roughing: false)
    let tp = try MouldingOperation(setup: OperationSetup(name: "M", toolID: tool.id, shapeIDs: ids), params: p)
        .generate(in: ctx)[0]
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let surface: (Vec2) -> Double = { q in
        let t = radius - q.distance(to: center)
        return sectionDepth(t)
    }
    #expect(maxGouge(tp, ctx: ctx, tool: tool, surface: surface) < 0.003)
    // Reaches close to the flat at 0.3 (a ball leaves a little at the chamfer foot).
    let deepest = ctx.coords.depth(ofMachineZ: tp.minZ!)
    #expect(deepest > 0.28 && deepest <= 0.3 + 1e-9)
}

@Test func ops2DMouldingCurvedOpenRailOnTheInsideOfTheBend() throws {
    // Quarter-circle-ish polyline rail, moulding on its left (the inside of a left turn).
    let c = Vec2(5, 1), radius = 1.5
    let pts = (0...24).map { k -> Vec2 in
        let a = -Double.pi / 2 + Double(k) / 24 * (Double.pi / 2)
        return c + Vec2(cos(a), sin(a)) * radius
    }.map { $0 + Vec2(0, 2) }
    let rail = Path(points: pts, closed: false)
    let (ctx, ids) = F.document([rail, sectionPath])
    let tool = ballNose()
    let tp = try MouldingOperation(setup: OperationSetup(name: "M", toolID: tool.id, shapeIDs: ids),
                                   params: MouldingParameters(sectionShapeID: ids[1], side: .left, stepover: 0.03,
                                                              roughing: true))
        .generate(in: ctx)[0]
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let cc = c + Vec2(0, 2)
    let surface: (Vec2) -> Double = { q in
        let d = q.distance(to: cc)
        // Inside the bend (left of the counter-clockwise arc) t = radius − d; outside: flat at 0.
        let ang = atan2(q.y - cc.y, q.x - cc.x)
        guard ang >= -Double.pi / 2 - 0.2, ang <= 0.2 else { return 1 } // beyond the rail ends: unconstrained here
        return d <= radius ? sectionDepth(radius - d) : 0
    }
    #expect(maxGouge(tp, ctx: ctx, tool: tool, surface: surface) < 0.003)
}
