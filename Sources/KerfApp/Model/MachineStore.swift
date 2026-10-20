import CADCore
import CAMCore
import Combine
import Foundation
import PostCore

/// Built-in machines plus user machines stored as JSON in
/// ~/Library/Application Support/Kerf/machines/*.json (a user file with a built-in's id overrides it).
struct MachineStore {
    var directory: URL

    init(directory: URL = ToolLibraryStore.supportDirectory.appendingPathComponent("machines", isDirectory: true)) {
        self.directory = directory
    }

    func userMachines() -> [MachineDefinition] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? MachineDefinition.fromJSON(Data(contentsOf: $0)) }
    }

    func allMachines() -> [MachineDefinition] {
        let user = userMachines()
        let userIDs = Set(user.map(\.id))
        return BuiltInMachines.all.filter { !userIDs.contains($0.id) } + user
    }

    func fileURL(for id: String) -> URL { directory.appendingPathComponent(id).appendingPathExtension("json") }

    @discardableResult
    func save(_ machine: MachineDefinition) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: machine.id)
        try machine.toJSON().write(to: url, options: .atomic)
        return url
    }

    func delete(id: String) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// True when `id` is stored as a user file (editable/deletable).
    func isUserMachine(_ id: String) -> Bool { FileManager.default.fileExists(atPath: fileURL(for: id).path) }
}

/// Which machine a project uses, and the post profile with that machine's limits applied. Pure.
enum MachineResolver {
    /// The project's chosen machine; else the first machine that lists the project's post; else nil
    /// (the post's own limits apply, as in files saved before machines existed).
    static func machine(for project: KerfProject, machines: [MachineDefinition]) -> MachineDefinition? {
        if let id = project.machineID, let m = machines.first(where: { $0.id == id }) { return m }
        let post = project.postProfileID ?? PostProfileStore.defaultID(for: project.document.units)
        return machines.first { $0.supports(postID: post) }
    }

    static func effectiveProfile(_ profile: PostProfile, machine: MachineDefinition?) -> PostProfile {
        machine?.applied(to: profile) ?? profile
    }

    /// Sets the machine and, if the current post does not drive it, switches to its default post.
    static func select(machine: MachineDefinition, in project: inout KerfProject, profiles: [PostProfile]) {
        project.machineID = machine.id
        let current = project.postProfileID ?? PostProfileStore.defaultID(for: project.document.units)
        if !machine.supports(postID: current),
           let post = machine.defaultPostID(for: project.document.units, available: profiles) {
            project.postProfileID = post
        }
    }

    /// Posts for a picker: the machine's own posts first, then the rest.
    static func orderedPosts(_ profiles: [PostProfile], machine: MachineDefinition?) -> (compatible: [PostProfile], other: [PostProfile]) {
        guard let machine else { return (profiles, []) }
        let compatible = machine.postIDs.compactMap { id in profiles.first { $0.id == id } }
        let ids = Set(compatible.map(\.id))
        return (compatible, profiles.filter { !ids.contains($0.id) })
    }

    /// Problems with fitting `job` on the machine bed (empty = fits).
    static func fitProblems(job: JobSetup, units: LengthUnit, machine: MachineDefinition?) -> [String] {
        guard let m = machine else { return [] }
        let f = m.units.factor(to: units)
        var out: [String] = []
        let x = m.limits.xTravel * f, y = m.limits.yTravel * f, z = m.limits.zTravel * f
        let eps = 1e-6
        if job.width > x + eps || job.height > y + eps {
            out.append("The material (\(RulerTicks.label(job.width)) x \(RulerTicks.label(job.height)) \(units.abbreviation)) is larger than the \(m.name) bed (\(RulerTicks.label(x)) x \(RulerTicks.label(y)) \(units.abbreviation)).")
        }
        if job.thickness > z + eps {
            out.append("The material is thicker than the machine's Z travel (\(RulerTicks.label(z)) \(units.abbreviation)).")
        }
        return out
    }
}

/// App-wide list of machines (built-ins + user JSON). `reload()` re-reads the folder.
final class MachineCatalog: ObservableObject {
    static let shared = MachineCatalog()
    @Published private(set) var machines: [MachineDefinition]
    let store: MachineStore

    init(store: MachineStore = MachineStore()) {
        self.store = store
        machines = store.allMachines()
    }

    func reload() { machines = store.allMachines() }

    func machine(id: String?) -> MachineDefinition? { machines.first { $0.id == id } }

    func machine(for project: KerfProject) -> MachineDefinition? {
        MachineResolver.machine(for: project, machines: machines)
    }

    func save(_ machine: MachineDefinition) throws {
        try store.save(machine)
        reload()
    }

    func delete(id: String) throws {
        try store.delete(id: id)
        reload()
    }

    /// A fresh, unique id for a copy of `base`.
    func newID(from base: String) -> String {
        let ids = Set(machines.map(\.id))
        var n = 1
        while ids.contains("\(base)-custom-\(n)") { n += 1 }
        return "\(base)-custom-\(n)"
    }
}
