import CADCore
import CAMCore
import Foundation

/// Expressions typed into numeric fields, waiting to be tied to the parameter they changed.
/// The field's parse strategy notes each expression that uses a variable; the next project
/// change finds the parameter(s) that took that value and links them (`VariableLinks.reconcile`).
final class ExpressionRecorder {
    /// An expression and the value it gave, in `units` (nil for a unitless field), so the value
    /// can be matched after a unit change (Job Setup lets the units change after the typing).
    struct Entry: Equatable { var text: String; var value: Double; var units: LengthUnit? }
    private(set) var pending: [Entry] = []
    /// The last noted value, until the field writes it (see `nudge`).
    private var unwritten: Double?

    func note(_ text: String, value: Double, units: LengthUnit?) {
        guard VariableLink.usesVariables(text, units: units) else { return }
        pending.append(Entry(text: text.trimmingCharacters(in: .whitespaces), value: value, units: units))
        if pending.count > 32 { pending.removeFirst() }
        unwritten = value
    }

    /// When an expression evaluates to the value the field already holds, the field writes the
    /// next representable number instead, so the change (and so the parameter) can be found;
    /// linking then restores the exact value.
    func valueToWrite(_ new: Double, current: Double) -> Double {
        defer { unwritten = nil }
        guard let u = unwritten, u == new, new == current else { return new }
        return new.nextUp
    }

    func take() -> [Entry] {
        defer { pending = [] }
        return pending
    }
}

/// Links between numeric parameters (job setup, toolpath settings) and the expressions typed
/// into them. Parameters are found by diffing their JSON encoding, so every numeric field of
/// every form takes part without the forms knowing about links.
enum VariableLinks {
    /// Updates `p.document.variableLinks` after an edit from `old` to `p`: parameters changed by
    /// hand lose their link, parameters that took a pending expression's value gain one, links
    /// of deleted toolpaths/sheets are dropped, and every link is re-evaluated (variables or the
    /// material may have changed). Returns links that could not be evaluated.
    @discardableResult
    static func reconcile(_ p: inout KerfProject, old: KerfProject, pending: [ExpressionRecorder.Entry]) -> [VariableLink] {
        var links = p.document.linkedValues
        guard !links.isEmpty || !pending.isEmpty else { return [] }
        // After a unit change every leaf is rescaled; compared with the old project converted the
        // same way (the same factor through the same scaling code, so untouched leaves are equal
        // to the bit and a field nudged by one ulp still reads as changed), only the leaves the
        // edit touched differ, so an expression typed in the new units finds its value without a
        // coincidence elsewhere. Links that already existed are still dropped: their literals
        // ("=thickness - 0.1") were written in the old units.
        let unitsChanged = p.document.units != old.document.units
        let old = unitsChanged ? old.converted(to: p.document.units) : old
        let sheetIDs = Set(p.document.allSheets.map(\.id))
        let opIDs = Set(p.operations.map(\.id))
        links.removeAll {
            switch $0.target {
            case .job(let s): return !sheetIDs.contains(s)
            case .operation(let id): return !opIDs.contains(id)
            }
        }
        // Job fields linked in a cycle (`=thickness/2` typed into Thickness; Safe Z from the
        // thickness and the thickness from Safe Z) would move every time the links are re-evaluated;
        // such links are never made and never kept.
        links = withoutCycles(links, in: p)
        var targets = Set(links.map(\.target))
        if !pending.isEmpty {
            targets.formUnion(p.document.allSheets.map { VariableLink.Target.job(sheetID: $0.id) })
            targets.formUnion(p.operations.map { VariableLink.Target.operation($0.id) })
        }
        for t in targets {
            guard let newTree = tree(of: t, in: p) else { continue }
            let oldTree = tree(of: t, in: old)
            // Hand edits (and unit conversion, whose literals no longer match) unlink.
            links.removeAll { l in
                guard l.target == t else { return false }
                if unitsChanged { return true }
                guard let o = oldTree else { return false }
                return number(at: l.path, in: o) != number(at: l.path, in: newTree)
            }
            guard !pending.isEmpty else { continue }
            var newLeaves: [[String]: Double] = [:]
            leaves(newTree, prefix: [], into: &newLeaves)
            for (path, v) in newLeaves.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) {
                if let o = oldTree, number(at: path, in: o) == v { continue }
                // A value typed in other units than the project now has (the form's units were
                // switched after the typing) is matched after the same conversion.
                func matches(_ e: ExpressionRecorder.Entry) -> Bool {
                    let value = e.units.map { $0 != p.document.units ? e.value * $0.factor(to: p.document.units) : e.value } ?? e.value
                    return abs(value - v) <= 1e-9 * max(1, abs(value))
                }
                guard let e = pending.last(where: matches) else { continue }
                let link = VariableLink(target: t, path: path, expression: e.text)
                let others = links.filter { !($0.target == t && $0.path == path) }
                guard !closesCycle(link, among: others, in: p) else { continue }
                links = others + [link]
            }
        }
        p.document.linkedValues = links
        return apply(&p)
    }

    /// Re-evaluates every link and writes the results (three passes, so a linked material
    /// thickness feeds toolpath links that use `thickness`). Returns links that failed.
    @discardableResult
    static func apply(_ p: inout KerfProject) -> [VariableLink] {
        var failed: [VariableLink] = []
        for _ in 0..<3 {
            failed = []
            var changed = false
            for l in p.document.linkedValues {
                guard let value = evaluate(l, in: p) else { failed.append(l); continue }
                guard let t = tree(of: l.target, in: p), let cur = number(at: l.path, in: t) else {
                    failed.append(l); continue
                }
                if cur == value { continue }
                guard let updated = setting(value, at: l.path, in: t), write(updated, to: l.target, in: &p) else {
                    failed.append(l); continue
                }
                changed = true
            }
            if !changed { break }
        }
        return failed
    }

    /// The job fields an expression can name.
    static let jobFields = ["width", "height", "thickness", "safez"]

    /// The job fields (lower-cased) a job link's expression uses on its own sheet. A user variable
    /// that shares a field's name counts as the field here, which errs towards refusing a link.
    static func jobFieldsUsed(by l: VariableLink, in p: KerfProject) -> Set<String> {
        guard case .job(let sheet) = l.target else { return [] }
        let table = p.document.variableTable(forSheet: sheet)
        return Set(jobFields.filter { VariableLink.references($0, in: l.expression, variables: table, units: p.document.units) })
    }

    /// True when `link` on a job field, with the other job links of its sheet, leads back to its
    /// own field: `=thickness/2` in Thickness, or Safe Z from the thickness and the thickness from
    /// Safe Z. Followed through the job links only; operation links cannot feed a job field.
    static func closesCycle(_ link: VariableLink, among links: [VariableLink], in p: KerfProject) -> Bool {
        guard case .job(let sheet) = link.target, let field = link.path.last?.lowercased() else { return false }
        var uses: [String: Set<String>] = [:]
        for l in links + [link] {
            guard case .job(let s) = l.target, s == sheet, let f = l.path.last?.lowercased() else { continue }
            uses[f] = jobFieldsUsed(by: l, in: p)
        }
        var seen: Set<String> = []
        var stack = Array(uses[field] ?? [])
        while let f = stack.popLast() {
            if f == field { return true }
            guard seen.insert(f).inserted else { continue }
            stack += uses[f] ?? []
        }
        return false
    }

    /// `links` without the job links that are part of a cycle.
    static func withoutCycles(_ links: [VariableLink], in p: KerfProject) -> [VariableLink] {
        links.filter { l in
            guard case .job = l.target else { return true }
            return !closesCycle(l, among: links.filter { $0 != l }, in: p)
        }
    }

    static func evaluate(_ l: VariableLink, in p: KerfProject) -> Double? {
        let sheet: UUID
        switch l.target {
        case .job(let s): sheet = s
        case .operation(let id):
            guard let op = p.operations.first(where: { $0.id == id }) else { return nil }
            sheet = p.sheetID(of: op) ?? p.document.currentSheetID
        }
        return try? ExpressionEvaluator.evaluate(l.expression, variables: p.document.variableTable(forSheet: sheet),
                                                 units: p.document.units)
    }

    /// "Profile 1 › Cut depth" style label for the variables sheet.
    static func describe(_ l: VariableLink, in p: KerfProject) -> String {
        let owner: String
        switch l.target {
        case .job(let s):
            owner = p.document.isMultiSheet
                ? "Job Setup (\(p.document.allSheets.first { $0.id == s }?.name ?? "sheet"))" : "Job Setup"
        case .operation(let id): owner = p.operations.first { $0.id == id }?.setup.name ?? "Toolpath"
        }
        let parts = l.path.filter { $0 != "_0" && Int($0) == nil }.suffix(2).map(humanize)
        return ([owner] + parts).joined(separator: " › ")
    }

    static func humanize(_ key: String) -> String {
        var out = ""
        for c in key {
            if c.isUppercase, !out.isEmpty { out += " " + c.lowercased() } else { out.append(c) }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // MARK: JSON trees

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }()

    static func tree<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func decode<T: Decodable>(_ type: T.Type, from tree: Any) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: tree, options: [.fragmentsAllowed]) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func tree(of t: VariableLink.Target, in p: KerfProject) -> Any? {
        switch t {
        case .job(let s): return p.document.job(ofSheet: s).flatMap { tree($0) }
        case .operation(let id): return p.operations.first { $0.id == id }.flatMap { tree($0) }
        }
    }

    static func write(_ tree: Any, to t: VariableLink.Target, in p: inout KerfProject) -> Bool {
        switch t {
        case .job(let s):
            guard let job = decode(JobSetup.self, from: tree) else { return false }
            if s == p.document.currentSheetID {
                p.document.job = job
            } else if let i = p.document.otherSheets?.firstIndex(where: { $0.id == s }) {
                p.document.otherSheets![i].job = job
            } else { return false }
        case .operation(let id):
            guard let op = decode(AnyOperation.self, from: tree), op.id == id,
                  let i = p.operations.firstIndex(where: { $0.id == id }) else { return false }
            p.operations[i] = op
        }
        return true
    }

    static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    /// Numeric (non-boolean) leaves by path.
    static func leaves(_ node: Any, prefix: [String], into out: inout [[String]: Double]) {
        if let d = node as? [String: Any] {
            for (k, v) in d { leaves(v, prefix: prefix + [k], into: &out) }
        } else if let a = node as? [Any] {
            for (i, v) in a.enumerated() { leaves(v, prefix: prefix + [String(i)], into: &out) }
        } else if let n = node as? NSNumber, !isBool(n) {
            out[prefix] = n.doubleValue
        }
    }

    static func number(at path: [String], in node: Any) -> Double? {
        var cur: Any = node
        for k in path {
            if let d = cur as? [String: Any], let next = d[k] {
                cur = next
            } else if let a = cur as? [Any], let i = Int(k), a.indices.contains(i) {
                cur = a[i]
            } else { return nil }
        }
        guard let n = cur as? NSNumber, !isBool(n) else { return nil }
        return n.doubleValue
    }

    static func setting(_ value: Double, at path: [String], in node: Any) -> Any? {
        guard let k = path.first else { return NSNumber(value: value) }
        let rest = Array(path.dropFirst())
        if var d = node as? [String: Any], let child = d[k] {
            guard let updated = setting(value, at: rest, in: child) else { return nil }
            d[k] = updated
            return d
        }
        if var a = node as? [Any], let i = Int(k), a.indices.contains(i) {
            guard let updated = setting(value, at: rest, in: a[i]) else { return nil }
            a[i] = updated
            return a
        }
        return nil
    }
}
