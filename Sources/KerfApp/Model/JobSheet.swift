import AppKit
import CADCore
import CAMCore
import Foundation
import PostCore

/// Printable job (setup) sheet for the operator at the machine: material, origin, Z zero,
/// heights, tools, toolpath list with times, and a preview picture. Pure data + HTML text;
/// the app saves it as an .html file the browser can print.
struct JobSheet: Equatable {
    struct ToolpathRow: Equatable {
        var name: String
        var kind: String
        var tool: String
        var toolNumber: Int
        var diameter: String
        var spindle: String
        var feeds: String
        /// Deepest cut below the material top, or nil when not calculated.
        var maxDepth: String?
        var time: String?
        var enabled: Bool
    }

    struct ToolRow: Equatable {
        var number: Int
        var name: String
        var diameter: String
        var toolpaths: [String]
    }

    var title: String
    var date: String
    var units: String
    var material: String
    var thickness: String
    var zZero: String
    var xyOrigin: String
    var safeZ: String
    var homeZ: String
    var home: String
    var post: String
    var totalTime: String
    var toolChanges: Int
    var toolpaths: [ToolpathRow]
    var tools: [ToolRow]
    var warnings: [String]
    var notes: String

    static func make(project: KerfProject, results: [UUID: ToolpathResult], library: ToolLibrary,
                     profile: PostProfile, groupByTool: Bool, jobName: String, date: Date = Date(),
                     notes: String = "") -> JobSheet {
        let doc = project.document, job = doc.job
        let u = doc.units.abbreviation
        func len(_ v: Double) -> String { "\(RulerTicks.label((v * 10000).rounded() / 10000)) \(u)" }
        let coords = MachineCoordinates(job: job)
        let lib = project.mergedTools(with: library)

        var rows: [ToolpathRow] = []
        var warnings: [String] = []
        for op in project.operations {
            let r = results[op.id]
            let tps = r?.toolpaths ?? []
            let tool = tps.first?.tool ?? lib.tool(id: op.setup.toolID)?.converted(to: doc.units)
            let depth = tps.compactMap(\.minZ).min().map { coords.depth(ofMachineZ: $0) }
            let ok = r.map { $0.error == nil } ?? false
            if op.setup.isEnabled {
                if r == nil { warnings.append("\(op.setup.name) is not calculated.") }
                else if let e = r?.error { warnings.append("\(op.setup.name): \(e)") }
            }
            let unitMin = "\(u)/min"
            rows.append(ToolpathRow(
                name: op.setup.name, kind: op.kind.displayName,
                tool: tool.map { $0.name } ?? "—", toolNumber: tool?.number ?? 0,
                diameter: tool.map { len($0.diameter) } ?? "—",
                spindle: tps.first.map { "\(Int($0.spindleRPM)) rpm" } ?? tool.map { "\(Int($0.spindleRPM)) rpm" } ?? "—",
                feeds: tool.map { "\(fmt($0.feedRate)) / \(fmt($0.plungeRate)) \(unitMin)" } ?? "—",
                maxDepth: depth.map(len), time: ok ? r.map { ToolpathCalculator.formatDuration($0.estimatedSeconds) } : nil,
                enabled: op.setup.isEnabled))
        }

        let summary = JobSummary.make(operations: project.operations, results: results, groupByTool: groupByTool)
        let ordered = GCodeExporter.toolpaths(scope: .all, operations: project.operations, results: results,
                                              groupByTool: groupByTool)
        var tools: [ToolRow] = []
        var seen: [UUID: Int] = [:]
        for tp in ordered {
            if let i = seen[tp.tool.id] {
                if !tools[i].toolpaths.contains(tp.name) { tools[i].toolpaths.append(tp.name) }
            } else {
                seen[tp.tool.id] = tools.count
                tools.append(ToolRow(number: tp.tool.number, name: tp.tool.name, diameter: len(tp.tool.diameter),
                                     toolpaths: [tp.name]))
            }
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return JobSheet(
            title: jobName.isEmpty ? doc.name : jobName, date: df.string(from: date), units: doc.units.displayName,
            material: "\(len(job.width)) × \(len(job.height))", thickness: len(job.thickness),
            zZero: job.zZero.displayName, xyOrigin: job.xyOrigin.displayName,
            safeZ: len(job.safeZ) + " above material", homeZ: len(job.homeZ) + " above material",
            home: "X \(len(job.home.x))  Y \(len(job.home.y))", post: profile.name,
            totalTime: ToolpathCalculator.formatDuration(summary.totalSeconds),
            toolChanges: summary.toolChanges, toolpaths: rows, tools: tools, warnings: warnings, notes: notes)
    }

    private static func fmt(_ v: Double) -> String { RulerTicks.label((v * 100).rounded() / 100) }

    static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Self-contained HTML page (inline CSS, preview embedded as a data URI).
    func html(previewPNG: Data?) -> String {
        let e = Self.escape
        var h = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <title>\(e(title)) — Job Sheet</title>
        <style>
        body{font:13px -apple-system,Helvetica,Arial,sans-serif;color:#111;margin:24px;}
        h1{font-size:20px;margin:0 0 2px} .sub{color:#555;margin-bottom:14px}
        h2{font-size:15px;margin:18px 0 6px;border-bottom:1px solid #999}
        table{border-collapse:collapse;width:100%} td,th{border:1px solid #bbb;padding:4px 6px;text-align:left;vertical-align:top}
        th{background:#eee} .grid{display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap}
        .grid table{width:auto;min-width:320px} img{max-width:100%;border:1px solid #999}
        .off{color:#888} .warn{color:#a40} .check{width:1.2em}
        @media print{body{margin:0} h2{break-after:avoid} tr{break-inside:avoid}}
        </style></head><body>
        <h1>\(e(title))</h1>
        <div class="sub">Job sheet · \(e(date)) · \(e(post))</div>
        <div class="grid"><table>
        <tr><th colspan="2">Material</th></tr>
        <tr><td>Size (X × Y)</td><td>\(e(material))</td></tr>
        <tr><td>Thickness (Z)</td><td>\(e(thickness))</td></tr>
        <tr><td>Units</td><td>\(e(units))</td></tr>
        <tr><td>Z zero</td><td>\(e(zZero))</td></tr>
        <tr><td>XY origin</td><td>\(e(xyOrigin))</td></tr>
        <tr><td>Safe Z</td><td>\(e(safeZ))</td></tr>
        <tr><td>Home</td><td>\(e(home)), Z \(e(homeZ))</td></tr>
        <tr><td>Estimated time</td><td>\(e(totalTime))</td></tr>
        <tr><td>Tool changes</td><td>\(toolChanges)</td></tr>
        </table>
        """
        if let png = previewPNG {
            h += "<div><img alt=\"Preview\" src=\"data:image/png;base64,\(png.base64EncodedString())\"></div>"
        }
        h += "</div>\n<h2>Tools (in program order)</h2>\n<table><tr><th class=\"check\">✓</th><th>Tool #</th><th>Name</th><th>Diameter</th><th>Toolpaths</th></tr>\n"
        if tools.isEmpty { h += "<tr><td colspan=\"5\" class=\"off\">No calculated toolpaths.</td></tr>\n" }
        for t in tools {
            h += "<tr><td></td><td>T\(t.number)</td><td>\(e(t.name))</td><td>\(e(t.diameter))</td><td>\(e(t.toolpaths.joined(separator: ", ")))</td></tr>\n"
        }
        h += "</table>\n<h2>Toolpaths</h2>\n<table><tr><th>#</th><th>Toolpath</th><th>Type</th><th>Tool</th><th>Diameter</th><th>Spindle</th><th>Feed / plunge</th><th>Max depth</th><th>Time</th></tr>\n"
        for (i, r) in toolpaths.enumerated() {
            let cls = r.enabled ? "" : " class=\"off\""
            h += "<tr\(cls)><td>\(i + 1)</td><td>\(e(r.name))\(r.enabled ? "" : " (disabled)")</td><td>\(e(r.kind))</td><td>T\(r.toolNumber) \(e(r.tool))</td><td>\(e(r.diameter))</td><td>\(e(r.spindle))</td><td>\(e(r.feeds))</td><td>\(e(r.maxDepth ?? "—"))</td><td>\(e(r.time ?? "—"))</td></tr>\n"
        }
        h += "</table>\n"
        if !warnings.isEmpty {
            h += "<h2>Warnings</h2>\n<ul class=\"warn\">" + warnings.map { "<li>\(e($0))</li>" }.joined() + "</ul>\n"
        }
        if !notes.isEmpty {
            h += "<h2>Notes</h2>\n<p>" + e(notes).replacingOccurrences(of: "\n", with: "<br>") + "</p>\n"
        }
        h += "</body></html>\n"
        return h
    }
}

/// Offscreen picture of the material, design vectors and toolpaths (job sheet / print).
enum DesignSnapshot {
    static func cgImage(document: Document, toolpaths: [Toolpath], size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Bitmap contexts are y-up: flip so fitTransform (which targets y-down) works unchanged.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        draw(document: document, toolpaths: toolpaths, in: ctx, size: size)
        return ctx.makeImage()
    }

    static func png(document: Document, toolpaths: [Toolpath], size: CGSize) -> Data? {
        guard let img = cgImage(document: document, toolpaths: toolpaths, size: size) else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }

    /// Draws into a y-down context of `size`.
    static func draw(document: Document, toolpaths: [Toolpath], in cg: CGContext, size: CGSize, margin: CGFloat = 16) {
        cg.setFillColor(CGColor(gray: 1, alpha: 1))
        cg.fill(CGRect(origin: .zero, size: size))
        let bounds = document.job.materialBounds.union(document.bounds)
        let t = ToolpathOverlayRenderer.fitTransform(bounds: bounds, in: size, margin: margin)
        let m = document.job.materialBounds
        let r = CGRect(x: m.min.x, y: m.min.y, width: m.width, height: m.height).applying(t)
        cg.setFillColor(CGColor(red: 0.97, green: 0.93, blue: 0.85, alpha: 1))
        cg.fill(r)
        cg.setStrokeColor(CGColor(gray: 0.35, alpha: 1))
        cg.setLineWidth(1)
        cg.stroke(r)
        PlacedImageRenderer.drawAll(document, in: cg, transform: t)
        let hidden = Set(document.layers.filter { !$0.isVisible }.map(\.id))
        cg.setStrokeColor(CGColor(gray: 0.1, alpha: 0.8))
        cg.setLineWidth(0.8)
        for shape in document.shapes where !hidden.contains(shape.layerID) {
            var tt = t
            if let p = CanvasPaths.cgPath(for: shape).copy(using: &tt) {
                cg.addPath(p)
                cg.strokePath()
            }
        }
        if !toolpaths.isEmpty {
            var style = ToolpathOverlayStyle()
            style.cutLineWidth = 1
            style.rapidLineWidth = 0.5
            style.plungeRadius = 2
            ToolpathOverlayRenderer.draw(ToolpathOverlay(toolpaths: toolpaths, coords: MachineCoordinates(job: document.job)),
                                         in: cg, transform: t, style: style)
        }
        // Origin marker.
        let o = document.job.originInMaterialFrame
        let c = CGPoint(x: o.x, y: o.y).applying(t)
        cg.setStrokeColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        cg.setLineWidth(1.5)
        cg.strokeEllipse(in: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
    }
}
