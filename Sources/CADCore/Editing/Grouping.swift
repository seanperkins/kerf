import Foundation

/// Groups: shapes sharing `Shape.groupID` act as one object for selection and transforms.
extension Document {
    /// IDs of every shape in the same group as `id` (just `[id]` when ungrouped).
    public func groupMembers(of id: UUID) -> [UUID] {
        guard let g = shape(id: id)?.groupID else { return [id] }
        return shapes.filter { $0.groupID == g }.map(\.id)
    }

    /// `ids` plus all their group mates, keeping the given order first.
    public func expandToGroups(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var out: [UUID] = []
        for id in ids {
            for m in [id] + groupMembers(of: id) where seen.insert(m).inserted { out.append(m) }
        }
        return out
    }

    /// Puts the shapes (and the groups they belong to) into one new group. Nested groups are
    /// flattened. Returns the group ID, or nil with fewer than two shapes.
    @discardableResult
    public mutating func group(_ ids: [UUID]) -> UUID? {
        let members = Set(expandToGroups(ids))
        guard members.count >= 2 else { return nil }
        let g = UUID()
        for i in shapes.indices where members.contains(shapes[i].id) { shapes[i].groupID = g }
        return g
    }

    /// Removes the selected shapes' groups entirely (every member becomes ungrouped).
    public mutating func ungroup(_ ids: [UUID]) {
        let groups = Set(ids.compactMap { shape(id: $0)?.groupID })
        guard !groups.isEmpty else { return }
        for i in shapes.indices where shapes[i].groupID.map(groups.contains) == true { shapes[i].groupID = nil }
    }

    /// Clears group IDs that only one shape still carries (e.g. after deleting group mates).
    public mutating func pruneSingletonGroups() {
        var counts: [UUID: Int] = [:]
        for s in shapes { if let g = s.groupID { counts[g, default: 0] += 1 } }
        for i in shapes.indices where shapes[i].groupID.map({ counts[$0] == 1 }) == true { shapes[i].groupID = nil }
    }
}
