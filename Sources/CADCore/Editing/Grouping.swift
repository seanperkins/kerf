import Foundation

/// Groups: shapes sharing `Shape.groupID` act as one object for selection and transforms.
/// Groups nest: `groupID` is always the outermost group and `innerGroupIDs` remembers the
/// groups underneath, so Ungroup peels one level and Ungroup All Levels clears them all.
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

    /// Puts the shapes (and the groups they belong to) into one new group; existing groups
    /// become nested inside it. Returns the group ID, or nil with fewer than two shapes or when
    /// the shapes already form exactly one group.
    @discardableResult
    public mutating func group(_ ids: [UUID]) -> UUID? {
        let members = Set(expandToGroups(ids))
        guard members.count >= 2 else { return nil }
        let outer = Set(shapes.filter { members.contains($0.id) }.map(\.groupID))
        if outer.count == 1, outer.first! != nil { return nil }
        let g = UUID()
        for i in shapes.indices where members.contains(shapes[i].id) {
            if let old = shapes[i].groupID { shapes[i].innerGroupIDs = [old] + (shapes[i].innerGroupIDs ?? []) }
            shapes[i].groupID = g
        }
        return g
    }

    /// Removes one level of grouping from the selected shapes' groups: members fall back to
    /// the group they had inside it (or none).
    public mutating func ungroup(_ ids: [UUID]) {
        let groups = Set(ids.compactMap { shape(id: $0)?.groupID })
        guard !groups.isEmpty else { return }
        for i in shapes.indices where shapes[i].groupID.map(groups.contains) == true { popGroup(i) }
    }

    /// Removes every level of grouping from the selected shapes' groups.
    public mutating func ungroupAllLevels(_ ids: [UUID]) {
        let groups = Set(ids.compactMap { shape(id: $0)?.groupID })
        guard !groups.isEmpty else { return }
        for i in shapes.indices where shapes[i].groupID.map(groups.contains) == true {
            shapes[i].groupID = nil
            shapes[i].innerGroupIDs = nil
        }
    }

    /// Nesting depth of a shape's grouping (0 = ungrouped).
    public func groupDepth(of id: UUID) -> Int {
        guard let s = shape(id: id), s.groupID != nil else { return 0 }
        return 1 + (s.innerGroupIDs?.count ?? 0)
    }

    /// Clears group levels that only one shape still carries (e.g. after deleting group mates).
    public mutating func pruneSingletonGroups() {
        var changed = true
        while changed {
            changed = false
            var counts: [UUID: Int] = [:]
            for s in shapes { if let g = s.groupID { counts[g, default: 0] += 1 } }
            for i in shapes.indices where shapes[i].groupID.map({ counts[$0] == 1 }) == true {
                popGroup(i)
                changed = true
            }
        }
    }

    private mutating func popGroup(_ i: Int) {
        var inner = shapes[i].innerGroupIDs ?? []
        shapes[i].groupID = inner.isEmpty ? nil : inner.removeFirst()
        shapes[i].innerGroupIDs = inner.isEmpty ? nil : inner
    }
}
