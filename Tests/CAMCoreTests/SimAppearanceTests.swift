import CADCore
import Foundation
import Testing
@testable import CAMCore

@Test func simAppearancePaintAndMachinedOverride() {
    var a = StockAppearance.preset(.maple)
    let paint = RGBColor(0.1, 0.2, 0.5), cut = RGBColor(1, 0.8, 0)
    a.paint = paint
    #expect(a.topColor(x: 1, y: 1, depth: 0, thickness: 1) == paint)
    // Carving through the paint shows material, not paint.
    #expect(a.topColor(x: 1, y: 1, depth: 0.2, thickness: 1) != paint)
    a.machinedOverride = cut
    #expect(a.topColor(x: 1, y: 1, depth: 0.2, thickness: 1) == cut)
    #expect(a.topColor(x: 1, y: 1, depth: 0, thickness: 1) == paint)
}

@Test func simAppearanceGrainAndDepthShading() {
    let plain = StockAppearance.preset(.mdf)
    #expect(plain.topColor(x: 0, y: 0, depth: 0, thickness: 1) == plain.topColor(x: 3, y: 1.7, depth: 0, thickness: 1))
    let wood = StockAppearance.preset(.oak)
    let samples = stride(from: 0.0, to: 1.0, by: 0.01).map { wood.topColor(x: 0.5, y: $0, depth: 0, thickness: 1).r }
    #expect((samples.max()! - samples.min()!) > 0.05) // visible rings across the grain
    // Grain scales with units: the same pattern at 25.4x the coordinates in mm.
    let inch = wood.topColor(x: 0.5, y: 0.37, depth: 0, thickness: 1)
    let mm = wood.topColor(x: 0.5 * 25.4, y: 0.37 * 25.4, depth: 0, thickness: 25.4, unitsPerInch: 25.4)
    #expect(abs(inch.r - mm.r) < 1e-5 && abs(inch.g - mm.g) < 1e-5)
    // Deeper cuts are darker.
    let shallow = plain.topColor(x: 0, y: 0, depth: 0.2, thickness: 1)
    let deep = plain.topColor(x: 0, y: 0, depth: 0.9, thickness: 1)
    #expect(deep.r + deep.g + deep.b < shallow.r + shallow.g + shallow.b)
}

@Test func simMeshUsesAppearance() {
    var hf = Heightfield(width: 1, height: 1, cellSize: 0.1)
    hf[5, 5] = 0.25
    var a = StockAppearance.preset(.pine)
    a.paint = RGBColor(0, 0, 1)
    a.machinedOverride = RGBColor(1, 0, 0)
    let mesh = HeightfieldMesh(heightfield: hf, thickness: 0.5, appearance: a)
    var red = 0, blue = 0
    for v in 0..<mesh.vertexCount where mesh.positions[3 * v + 2] != -0.5 {
        let c = (mesh.colors[3 * v], mesh.colors[3 * v + 1], mesh.colors[3 * v + 2])
        if c == (1, 0, 0) { red += 1 }
        if c == (0, 0, 1) { blue += 1 }
    }
    #expect(red >= 1)
    #expect(blue > red)
}
