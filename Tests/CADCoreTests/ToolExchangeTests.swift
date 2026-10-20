import Foundation
import Testing
@testable import CADCore

@Test func toolExchangeJSONRoundTripKeepsEverything() throws {
    var tools = ToolLibrary.seeded.tools
    tools[0].group = "Shop/Favourites"
    tools[0].materials = [MaterialCuttingData(material: "MDF", from: tools[0])]
    let data = try ToolLibraryExchange.encodeJSON(tools)
    #expect(try ToolLibraryExchange.decodeJSON(data) == tools)
}

@Test func toolExchangeAcceptsPlainToolsJSON() throws {
    let data = try JSONEncoder().encode(ToolLibrary.seeded)
    #expect(try ToolLibraryExchange.decodeJSON(data).count == ToolLibrary.seeded.tools.count)
}

@Test func toolExchangeRejectsNewerFormatAndJunk() {
    let newer = Data(#"{"formatVersion": 99, "tools": []}"#.utf8)
    #expect(throws: ToolLibraryExchange.ExchangeError.newerFormat(99)) { try ToolLibraryExchange.decodeJSON(newer) }
    #expect(throws: (any Error).self) { try ToolLibraryExchange.decodeJSON(Data("hello".utf8)) }
}

@Test func toolExchangeCSVRoundTrip() throws {
    var tools = ToolLibrary.seeded.tools
    tools[1].notes = "Has, a comma and \"quotes\"\nand a newline"
    tools[2].group = "Big"
    let back = try ToolLibraryExchange.decodeCSV(ToolLibraryExchange.encodeCSV(tools))
    #expect(back.count == tools.count)
    for (a, b) in zip(tools, back) {
        #expect(a.id == b.id && a.name == b.name && a.kind == b.kind && a.number == b.number)
        #expect(a.diameter == b.diameter && a.angle == b.angle && a.feedRate == b.feedRate)
        #expect(a.notes == b.notes && a.group == b.group && a.units == b.units)
    }
}

@Test func toolExchangeCSVFromSpreadsheet() throws {
    let csv = "Name,Type,Diameter,Units,Feed\r\n1/4 Upcut,End Mill,0.25,in,120\r\n6mm ball,ball nose,6,mm,\r\n"
    let tools = try ToolLibraryExchange.decodeCSV(csv)
    #expect(tools.count == 2)
    #expect(tools[0].kind == .endMill && tools[0].feedRate == 120)
    #expect(tools[1].kind == .ballNose && tools[1].units == .millimeter && tools[1].diameter == 6)
    #expect(throws: (any Error).self) { try ToolLibraryExchange.decodeCSV("Name,Type,Diameter\nx,laser,1\n") }
    #expect(throws: (any Error).self) { try ToolLibraryExchange.decodeCSV("Name,Type\nx,drill\n") }
}

@Test func toolImportMergePolicies() {
    let base = ToolLibrary.seeded
    var changed = base.tools[0]
    changed.feedRate = 999
    let fresh = Tool(name: "New", kind: .endMill, number: 2, diameter: 0.1, stepdown: 0.05, stepover: 0.04,
                     feedRate: 50, plungeRate: 10) // T2 clashes with a seeded tool
    let incoming = [base.tools[1], changed, fresh]
    #expect(base.conflicts(with: incoming).map(\.id) == [changed.id])

    var lib = base
    var r = lib.merge(incoming, policy: .replace)
    #expect(r.added == 1 && r.replaced == 1 && r.skipped == 1)
    #expect(lib.tool(id: changed.id)?.feedRate == 999)
    #expect(Set(lib.tools.map(\.number)).count == lib.tools.count)
    #expect(r.renumbered.count == 1)

    lib = base
    r = lib.merge(incoming, policy: .skip)
    #expect(r.added == 1 && r.skipped == 2 && lib.tool(id: changed.id)?.feedRate == base.tools[0].feedRate)

    lib = base
    r = lib.merge(incoming, policy: .keepBoth)
    #expect(r.added == 2 && lib.tools.count == base.tools.count + 2)
    #expect(lib.tools.contains { $0.name.hasSuffix("(imported)") && $0.feedRate == 999 })
    #expect(Set(lib.tools.map(\.id)).count == lib.tools.count)
    #expect(Set(lib.tools.map(\.number)).count == lib.tools.count)
}
