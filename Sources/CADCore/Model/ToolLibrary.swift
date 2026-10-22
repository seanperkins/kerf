import Foundation

/// The tool database. Persisted as JSON by `ToolLibraryStore`.
public struct ToolLibrary: Codable, Hashable, Sendable {
    public var tools: [Tool]

    public init(tools: [Tool] = []) { self.tools = tools }

    public func tool(id: UUID) -> Tool? { tools.first { $0.id == id } }

    public mutating func upsert(_ tool: Tool) {
        if let i = tools.firstIndex(where: { $0.id == tool.id }) { tools[i] = tool } else { tools.append(tool) }
    }

    public mutating func remove(id: UUID) { tools.removeAll { $0.id == id } }

    /// True when toolpaths calculated from `old` could differ from ones calculated from this
    /// library: a tool was added or removed, or one changed in more than its name, notes or folder.
    public func changesToolpaths(from old: ToolLibrary) -> Bool {
        guard tools.count == old.tools.count else { return true }
        return tools.contains { t in old.tool(id: t.id).map { !t.cutsSameToolpaths(as: $0) } ?? true }
    }

    /// Seed library: conservative feeds/speeds for hardwood / softwood / plastics on a
    /// 2.2 kW router spindle. Tool numbers are unique. Inch units.
    public static var seeded: ToolLibrary {
        // Fixed UUIDs so documents referencing seeded tools stay valid across launches.
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
        return ToolLibrary(tools: [
            Tool(id: id(1), name: "1/4\" End Mill (2 flute)", kind: .endMill, number: 1, diameter: 0.25,
                 flutes: 2, fluteLength: 1.0, stepdown: 0.125, stepover: 0.1, spindleRPM: 18000,
                 feedRate: 100, plungeRate: 30),
            Tool(id: id(2), name: "1/8\" End Mill (2 flute)", kind: .endMill, number: 2, diameter: 0.125,
                 flutes: 2, fluteLength: 0.5, stepdown: 0.0625, stepover: 0.05, spindleRPM: 18000,
                 feedRate: 60, plungeRate: 20),
            Tool(id: id(3), name: "1/2\" End Mill (2 flute)", kind: .endMill, number: 3, diameter: 0.5,
                 flutes: 2, fluteLength: 1.25, stepdown: 0.2, stepover: 0.2, spindleRPM: 16000,
                 feedRate: 150, plungeRate: 40),
            Tool(id: id(4), name: "1/4\" Ball Nose", kind: .ballNose, number: 4, diameter: 0.25, flutes: 2,
                 stepdown: 0.1, stepover: 0.025, spindleRPM: 18000, feedRate: 100, plungeRate: 30),
            Tool(id: id(5), name: "1/8\" Ball Nose", kind: .ballNose, number: 5, diameter: 0.125, flutes: 2,
                 stepdown: 0.05, stepover: 0.0125, spindleRPM: 18000, feedRate: 60, plungeRate: 20),
            Tool(id: id(6), name: "60° V-Bit 1/2\"", kind: .vBit, number: 6, diameter: 0.5, flutes: 2,
                 angle: 60, stepdown: 0.1, stepover: 0.02, spindleRPM: 18000, feedRate: 80,
                 plungeRate: 30),
            Tool(id: id(7), name: "90° V-Bit 1/2\"", kind: .vBit, number: 7, diameter: 0.5, flutes: 2,
                 angle: 90, stepdown: 0.1, stepover: 0.02, spindleRPM: 18000, feedRate: 80,
                 plungeRate: 30),
            Tool(id: id(8), name: "30° Engraving 0.01\" tip", kind: .engraving, number: 8, diameter: 0.125,
                 flutes: 1, angle: 30, tipDiameter: 0.01, stepdown: 0.02, stepover: 0.005,
                 spindleRPM: 20000, feedRate: 40, plungeRate: 15),
            Tool(id: id(9), name: "1/4\" Drill", kind: .drill, number: 9, diameter: 0.25, flutes: 2,
                 stepdown: 0.125, stepover: 0, spindleRPM: 12000, feedRate: 30, plungeRate: 20),
        ])
    }
}
