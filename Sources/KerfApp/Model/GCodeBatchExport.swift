import CADCore
import CAMCore
import Foundation
import PostCore

/// "Save All Toolpaths": how the enabled, calculated toolpaths are split into files.
enum SaveAllMode: String, CaseIterable, Identifiable {
    /// One program, toolpaths grouped so each tool is loaded once.
    case oneFileGroupedByTool
    /// One program in toolpath-list order (a tool change wherever the tool differs).
    case oneFileInOrder
    /// One program per toolpath (operation).
    case filePerToolpath
    /// One program per tool (no tool changes inside a file).
    case filePerTool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneFileGroupedByTool: return "One file, grouped by tool"
        case .oneFileInOrder: return "One file, in toolpath order"
        case .filePerToolpath: return "One file per toolpath"
        case .filePerTool: return "One file per tool"
        }
    }

    var isSingleFile: Bool { self == .oneFileGroupedByTool || self == .oneFileInOrder }
}

/// A planned output file.
struct PlannedGCodeFile: Equatable {
    var fileName: String
    var title: String
    var toolpaths: [Toolpath]
}

enum GCodeBatchExport {
    /// Splits the enabled operations' calculated toolpaths into files. Operations without
    /// toolpaths are skipped.
    static func plan(mode: SaveAllMode, operations: [AnyOperation], results: [UUID: ToolpathResult],
                     jobName: String, profile: PostProfile) -> [PlannedGCodeFile] {
        let enabled = operations.filter(\.setup.isEnabled)
        var files: [PlannedGCodeFile] = []
        switch mode {
        case .oneFileGroupedByTool, .oneFileInOrder:
            let tps = GCodeExporter.toolpaths(scope: .all, operations: operations, results: results,
                                              groupByTool: mode == .oneFileGroupedByTool)
            if !tps.isEmpty {
                files.append(PlannedGCodeFile(
                    fileName: GCodeExporter.suggestedFileName(jobName: jobName, operationName: nil, profile: profile),
                    title: "All toolpaths", toolpaths: tps))
            }
        case .filePerToolpath:
            for op in enabled {
                let tps = results[op.id]?.toolpaths ?? []
                guard !tps.isEmpty else { continue }
                files.append(PlannedGCodeFile(
                    fileName: GCodeExporter.suggestedFileName(jobName: jobName, operationName: op.setup.name,
                                                              profile: profile),
                    title: op.setup.name, toolpaths: tps))
            }
        case .filePerTool:
            let tps = GCodeExporter.toolpaths(scope: .all, operations: operations, results: results, groupByTool: false)
            var order: [UUID] = []
            var groups: [UUID: [Toolpath]] = [:]
            for tp in tps {
                if groups[tp.tool.id] == nil { order.append(tp.tool.id) }
                groups[tp.tool.id, default: []].append(tp)
            }
            for id in order {
                guard let group = groups[id], let tool = group.first?.tool else { continue }
                files.append(PlannedGCodeFile(
                    fileName: GCodeExporter.suggestedFileName(jobName: jobName, operationName: "T\(tool.number)_\(tool.name)",
                                                              profile: profile),
                    title: JobSummary.label(tool), toolpaths: group))
            }
        }
        return uniquified(files)
    }

    /// "a.tap", "a.tap" → "a.tap", "a_2.tap".
    static func uniquified(_ files: [PlannedGCodeFile]) -> [PlannedGCodeFile] {
        var used = Set<String>()
        return files.map { f in
            var out = f
            let ext = (f.fileName as NSString).pathExtension
            let base = (f.fileName as NSString).deletingPathExtension
            var n = 2
            while used.contains(out.fileName.lowercased()) {
                out.fileName = "\(base)_\(n)" + (ext.isEmpty ? "" : ".\(ext)")
                n += 1
            }
            used.insert(out.fileName.lowercased())
            return out
        }
    }

    /// Posts every planned file (validator included).
    static func post(_ files: [PlannedGCodeFile], project: KerfProject, profile: PostProfile,
                     jobName: String) -> [(file: PlannedGCodeFile, result: GCodeExportResult)] {
        files.map { ($0, GCodeExporter.export(project: project, toolpaths: $0.toolpaths, profile: profile, jobName: jobName)) }
    }

    /// Writes every posted program into `directory`. Returns the written URLs; files whose post
    /// failed are skipped.
    @discardableResult
    static func write(_ posted: [(file: PlannedGCodeFile, result: GCodeExportResult)], to directory: URL) throws -> [URL] {
        var urls: [URL] = []
        for (file, result) in posted {
            guard let text = result.text else { continue }
            let url = directory.appendingPathComponent(file.fileName)
            try text.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
    }
}
