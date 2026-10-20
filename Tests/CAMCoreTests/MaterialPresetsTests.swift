import CADCore
import Foundation
import Testing
@testable import CAMCore

@Suite struct MaterialPresetsTests {
    func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

    @Test func chipLoadScalesWithTheDiameterAndStopsAtHalfAnInch() throws {
        let hardwood = try #require(MaterialPresets.preset(named: "hardwood"))
        #expect(approx(MaterialPresets.chipLoad(hardwood, diameter: 0.25, units: .inch), 0.010))
        #expect(approx(MaterialPresets.chipLoad(hardwood, diameter: 0.125, units: .inch), 0.005))
        #expect(approx(MaterialPresets.chipLoad(hardwood, diameter: 0.5, units: .inch), 0.020))
        #expect(approx(MaterialPresets.chipLoad(hardwood, diameter: 1.0, units: .inch), 0.020))
        #expect(MaterialPresets.chipLoad(hardwood, diameter: 0, units: .inch) == 0)
    }

    @Test func millimeterToolsGetMillimeterChipLoads() throws {
        let mdf = try #require(MaterialPresets.preset(named: "MDF"))
        // A 6 mm cutter is 0.2362 in; 0.052 per inch gives 0.01228 in, which is 0.312 mm per tooth.
        let mm = MaterialPresets.chipLoad(mdf, diameter: 6, units: .millimeter)
        #expect(approx(mm, 0.052 * (6 / 25.4) * 25.4, 1e-9))
        #expect(approx(mm, 0.312, 1e-3))
    }

    @Test func theStartingPointsAreConservativeAndOrdered() {
        // Aluminum takes the smallest bite, foam the largest; wood sits between 0.009 and 0.014 at 1/4 in.
        let quarter = MaterialPresets.all.map { ($0.name, MaterialPresets.chipLoad($0, diameter: 0.25, units: .inch)) }
        let byName = Dictionary(uniqueKeysWithValues: quarter)
        #expect(byName["Aluminum"]! < byName["Acrylic"]!)
        #expect(byName["Acrylic"]! < byName["Hardwood"]!)
        #expect(byName["Hardwood"]! < byName["Softwood"]!)
        #expect(byName["MDF"]! < byName["Foam"]!)
        for name in ["Softwood", "Hardwood", "Plywood", "MDF"] {
            #expect((0.009...0.014).contains(byName[name]!), Comment(rawValue: name))
        }
        #expect(Set(MaterialPresets.all.map(\.name)).count == MaterialPresets.all.count)
    }

    @Test func aJobMaterialNameFindsItsPreset() {
        #expect(MaterialPresets.preset(matching: "3/4 Baltic birch ply")?.name == "Plywood")
        #expect(MaterialPresets.preset(matching: "Red oak")?.name == "Hardwood")
        #expect(MaterialPresets.preset(matching: "mdf 18mm")?.name == "MDF")
        #expect(MaterialPresets.preset(matching: "Cast acrylic, 6 mm")?.name == "Acrylic")
        #expect(MaterialPresets.preset(matching: "6061 aluminium")?.name == "Aluminum")
        #expect(MaterialPresets.preset(matching: "Pink XPS foam")?.name == "Foam")
        #expect(MaterialPresets.preset(matching: "Plywood")?.name == "Plywood")
        #expect(MaterialPresets.preset(matching: "Purpleheart") == nil)
        #expect(MaterialPresets.preset(matching: "") == nil)
        #expect(MaterialPresets.preset(matching: nil) == nil)
    }
}
