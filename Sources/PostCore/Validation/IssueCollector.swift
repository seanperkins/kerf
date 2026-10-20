import Foundation

/// Collects issues, keeping only the first occurrence of each kind and counting repeats so a
/// systematic problem does not flood the report.
struct IssueCollector {
    private var order: [String] = []
    private var first: [String: GCodeIssue] = [:]
    private var counts: [String: Int] = [:]

    mutating func add(_ key: String, _ severity: GCodeIssue.Severity, line: Int?, _ message: String) {
        if first[key] == nil {
            order.append(key)
            first[key] = GCodeIssue(severity: severity, line: line, message: message)
        }
        counts[key, default: 0] += 1
    }

    mutating func merge(_ other: IssueCollector) {
        for key in other.order {
            guard let issue = other.first[key] else { continue }
            if first[key] == nil { order.append(key); first[key] = issue }
            counts[key, default: 0] += other.counts[key] ?? 1
        }
    }

    var issues: [GCodeIssue] {
        order.compactMap { key in
            guard var issue = first[key] else { return nil }
            let n = counts[key] ?? 1
            if n > 1 { issue.message += " (\(n - 1) more)" }
            return issue
        }
        // Errors first, stable otherwise.
        .enumerated()
        .sorted { ($0.element.severity == .error ? 0 : 1, $0.offset) < ($1.element.severity == .error ? 0 : 1, $1.offset) }
        .map(\.element)
    }
}
