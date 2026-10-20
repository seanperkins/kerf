import Foundation

/// SVG import: path/rect/circle/ellipse/line/polyline/polygon, nested transforms, `<use>`,
/// viewBox + physical units → document units. Top-level groups (and Inkscape layers) become
/// layers. Output is in the document frame: Y up, the SVG page's lower-left corner at (0,0).
public struct SVGImporter: VectorImporter {
    public static let fileExtensions = ["svg"]

    /// Size of one user unit when the file has no physical width/height (CSS: 96 px per inch).
    public var pixelsPerInch: Double

    public init(pixelsPerInch: Double = 96) { self.pixelsPerInch = pixelsPerInch }

    public func importVectors(from data: Data, targetUnits: LengthUnit) throws -> ImportResult {
        let root = try SVGNode.parse(data)
        var ctx = Context(units: targetUnits)
        ctx.indexIDs(root)
        let pageToDoc = viewportTransform(root, units: targetUnits, warnings: &ctx.warnings)

        let defaultLayer = Layer(name: "SVG Import", colorHex: Self.palette[0])
        for child in root.children {
            if child.name == "g", !Self.hiddenContainers.contains(child.name), isRendered(child) {
                let layer = Layer(name: child["inkscape:label"] ?? child.id ?? "Group \(ctx.layers.count + 1)",
                                  colorHex: Self.palette[(ctx.layers.count + 1) % Self.palette.count])
                let before = ctx.shapes.count
                ctx.walk(child, ctm: pageToDoc, layerID: layer.id)
                if ctx.shapes.count > before { ctx.layers.append(layer) }
            } else {
                ctx.walk(child, ctm: pageToDoc, layerID: defaultLayer.id)
            }
        }
        if ctx.shapes.contains(where: { $0.layerID == defaultLayer.id }) { ctx.layers.insert(defaultLayer, at: 0) }
        return ImportResult(layers: ctx.layers, shapes: ctx.shapes, warnings: ctx.warnings, images: ctx.images)
    }

    /// Maps root user space → document units with Y flipped (page bottom at y = 0).
    func viewportTransform(_ root: SVGNode, units: LengthUnit, warnings: inout [String]) -> Transform2D {
        let pxToUnit = LengthUnit.inch.convert(1 / pixelsPerInch, to: units)
        let vb = root["viewBox"].map(SVGNumberScanner.numbers(in:)) ?? []
        let hasVB = vb.count == 4 && vb[2] > 0 && vb[3] > 0
        // Viewport size in px (width/height attributes; default to the viewBox size).
        let wPx = SVGAttributes.pixels(root["width"], percentOf: hasVB ? vb[2] : 0) ?? (hasVB ? vb[2] : 0)
        let hPx = SVGAttributes.pixels(root["height"], percentOf: hasVB ? vb[3] : 0) ?? (hasVB ? vb[3] : 0)
        var userToPx = Transform2D.identity
        if hasVB {
            var sx = wPx / vb[2], sy = hPx / vb[3]
            var tx = -vb[0] * sx, ty = -vb[1] * sy
            let par = root["preserveAspectRatio"]?.trimmingCharacters(in: .whitespaces) ?? "xMidYMid meet"
            if !par.hasPrefix("none") {
                let s = par.contains("slice") ? max(sx, sy) : min(sx, sy)
                let extraX = wPx - vb[2] * s, extraY = hPx - vb[3] * s
                let fx = par.contains("xMin") ? 0.0 : par.contains("xMax") ? 1.0 : 0.5
                let fy = par.contains("YMin") ? 0.0 : par.contains("YMax") ? 1.0 : 0.5
                sx = s; sy = s
                tx = -vb[0] * s + extraX * fx
                ty = -vb[1] * s + extraY * fy
            }
            userToPx = Transform2D(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty)
        } else if root["width"] == nil {
            warnings.append("SVG has no viewBox or size; assuming \(Int(pixelsPerInch)) user units per inch.")
        }
        let flip = Transform2D(a: pxToUnit, b: 0, c: 0, d: -pxToUnit, tx: 0, ty: hPx * pxToUnit)
        return userToPx.concatenating(flip)
    }

    static let palette = ["#1E90FF", "#E5484D", "#30A46C", "#F76B15", "#8E4EC6", "#12A594", "#D6409F", "#3E63DD"]
    static let hiddenContainers: Set<String> = ["defs", "clipPath", "mask", "symbol", "pattern", "marker",
                                                 "metadata", "title", "desc", "style", "script", "linearGradient",
                                                 "radialGradient", "filter", "namedview"]

    func isRendered(_ n: SVGNode) -> Bool {
        n.property("display") != "none" && n.property("visibility") != "hidden"
    }

    // MARK: - Walk

    struct Context {
        let units: LengthUnit
        var layers: [Layer] = []
        var shapes: [Shape] = []
        var warnings: [String] = []
        var images: [ImportedImage] = []
        var ids: [String: SVGNode] = [:]
        private var warned: Set<String> = []
        private var useDepth = 0

        init(units: LengthUnit) { self.units = units }

        mutating func indexIDs(_ root: SVGNode) {
            var map: [String: SVGNode] = [:]
            root.forEach { if let id = $0.id { map[id] = $0 } }
            ids = map
        }

        mutating func warnOnce(_ msg: String) {
            if warned.insert(msg).inserted { warnings.append(msg) }
        }

        mutating func walk(_ n: SVGNode, ctm parent: Transform2D, layerID: UUID) {
            guard !SVGImporter.hiddenContainers.contains(n.name),
                  n.property("display") != "none", n.property("visibility") != "hidden" else { return }
            let ctm = (n["transform"].map(SVGAttributes.transform) ?? .identity).concatenating(parent)
            switch n.name {
            case "g", "a", "switch":
                for c in n.children { walk(c, ctm: ctm, layerID: layerID) }
            case "svg":
                // Nested viewport: honour x/y offset only.
                let off = Transform2D.translation(Vec2(SVGAttributes.pixels(n["x"]) ?? 0, SVGAttributes.pixels(n["y"]) ?? 0))
                for c in n.children { walk(c, ctm: off.concatenating(ctm), layerID: layerID) }
            case "use":
                let ref = (n["xlink:href"] ?? n["href"]).map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
                guard let ref, let target = ids[ref], useDepth < 16 else {
                    warnOnce("Ignored <use> with a missing reference."); return
                }
                let off = Transform2D.translation(Vec2(SVGAttributes.pixels(n["x"]) ?? 0, SVGAttributes.pixels(n["y"]) ?? 0))
                useDepth += 1
                if target.name == "symbol" {
                    for c in target.children { walk(c, ctm: off.concatenating(ctm), layerID: layerID) }
                } else {
                    walk(target, ctm: off.concatenating(ctm), layerID: layerID)
                }
                useDepth -= 1
            case "text":
                addText(n, ctm: ctm, layerID: layerID)
            case "image":
                addImage(n, ctm: ctm)
            default:
                if let paths = SVGImporter.geometry(of: n), !paths.isEmpty {
                    // A subpath that returns to its start without "Z" is still a closed vector.
                    let doc = PathGeometry.closeNearlyClosed(paths.map { $0.transformed(ctm) },
                                                             tolerance: units == .inch ? 0.0005 : 0.01)
                    shapes.append(Shape(name: n.id ?? n.name, layerID: layerID, paths: doc,
                                        origin: .imported(format: "svg")))
                }
            }
        }
    }

    // MARK: - Element geometry (raw user space)

    /// Installed font for a CSS `font-family` list (generic families map to macOS fonts);
    /// bold weights prefer the family's "Bold" face. nil when none of them is installed.
    static func resolveFont(family: String?, weight: String?) -> String? {
        let generic = ["sans-serif": "Helvetica", "serif": "Times New Roman", "monospace": "Menlo",
                       "cursive": "Apple Chancery", "fantasy": "Papyrus", "system-ui": "Helvetica"]
        let names = (family ?? "sans-serif").split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        }.filter { !$0.isEmpty }
        let bold = weight.map { $0 == "bold" || $0 == "bolder" || (Int($0) ?? 400) >= 600 } ?? false
        for raw in names {
            let name = generic[raw.lowercased()] ?? raw
            let tries = bold ? ["\(name) Bold", "\(name)-Bold", name] : [name]
            for t in tries where (try? TextOutliner().advance(of: "H", fontName: t, pointSize: 10)) != nil { return t }
        }
        return nil
    }

    static func geometry(of n: SVGNode) -> [Path]? {
        func num(_ k: String, _ ref: Double = 0) -> Double { SVGAttributes.pixels(n[k], percentOf: ref) ?? 0 }
        switch n.name {
        case "path":
            return SVGPathParser.parse(n["d"] ?? "")
        case "rect":
            let w = num("width"), h = num("height")
            guard w > 0, h > 0 else { return nil }
            var rx = SVGAttributes.pixels(n["rx"]), ry = SVGAttributes.pixels(n["ry"])
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            let r = Rect2(x: num("x"), y: num("y"), width: w, height: h)
            return [roundedRect(r, rx: min(rx ?? 0, w / 2), ry: min(ry ?? 0, h / 2))]
        case "circle":
            let r = num("r")
            guard r > 0 else { return nil }
            return [ShapeFactory.circle(center: Vec2(num("cx"), num("cy")), radius: r)]
        case "ellipse":
            let rx = num("rx"), ry = num("ry")
            guard rx > 0, ry > 0 else { return nil }
            let c = Vec2(num("cx"), num("cy"))
            return [abs(rx - ry) < 1e-12 ? ShapeFactory.circle(center: c, radius: rx)
                                         : ShapeFactory.ellipse(center: c, rx: rx, ry: ry)]
        case "line":
            return [Path(points: [Vec2(num("x1"), num("y1")), Vec2(num("x2"), num("y2"))], closed: false)]
        case "polyline", "polygon":
            let v = SVGNumberScanner.numbers(in: n["points"] ?? "")
            let pts = stride(from: 0, to: v.count - 1, by: 2).map { Vec2(v[$0], v[$0 + 1]) }
            guard pts.count > 1 else { return nil }
            return [Path(points: pts, closed: n.name == "polygon")]
        default:
            return nil
        }
    }

    /// Rectangle with elliptical corners (rx, ry); arcs when circular.
    static func roundedRect(_ r: Rect2, rx: Double, ry: Double) -> Path {
        if rx <= 0 || ry <= 0 { return ShapeFactory.rectangle(r) }
        if abs(rx - ry) < 1e-12 { return ShapeFactory.rectangle(r, cornerRadius: rx) }
        let k = 0.5522847498307936
        let (x0, y0, x1, y1) = (r.min.x, r.min.y, r.max.x, r.max.y)
        func corner(_ from: Vec2, _ to: Vec2, _ c: Vec2) -> PathSegment {
            .cubic(to: to, control1: from + (c - from) * k, control2: to + (c - to) * k)
        }
        return Path(start: Vec2(x0 + rx, y0), segments: [
            .line(to: Vec2(x1 - rx, y0)),
            corner(Vec2(x1 - rx, y0), Vec2(x1, y0 + ry), Vec2(x1, y0)),
            .line(to: Vec2(x1, y1 - ry)),
            corner(Vec2(x1, y1 - ry), Vec2(x1 - rx, y1), Vec2(x1, y1)),
            .line(to: Vec2(x0 + rx, y1)),
            corner(Vec2(x0 + rx, y1), Vec2(x0, y1 - ry), Vec2(x0, y1)),
            .line(to: Vec2(x0, y0 + ry)),
            corner(Vec2(x0, y0 + ry), Vec2(x0 + rx, y0), Vec2(x0, y0)),
        ], isClosed: true)
    }
}

// MARK: - Text and images

extension SVGImporter.Context {
    /// `<text>` (with `<tspan>` runs) → outline shape. Fonts come from the installed system fonts.
    mutating func addText(_ n: SVGNode, ctm: Transform2D, layerID: UUID) {
        var paths: [Path] = []
        var label = ""
        var cursor = Vec2(SVGAttributes.pixels(n["x"]) ?? 0, SVGAttributes.pixels(n["y"]) ?? 0)
        var atStart = true

        func run(_ node: SVGNode) {
            for c in node.children {
                if c.name == "#text" {
                    var s = c.data.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
                    while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
                    if atStart { s = String(s.drop { $0 == " " }) }
                    guard !s.isEmpty else { continue }
                    atStart = false
                    emit(s, style: node)
                } else if c.name == "tspan" || c.name == "textPath" {
                    if c.property("display") == "none" { continue }
                    if let x = SVGAttributes.pixels(c["x"]) { cursor.x = x }
                    if let y = SVGAttributes.pixels(c["y"]) { cursor.y = y }
                    cursor.x += SVGAttributes.pixels(c["dx"]) ?? 0
                    cursor.y += SVGAttributes.pixels(c["dy"]) ?? 0
                    run(c)
                }
            }
        }

        func emit(_ s: String, style: SVGNode) {
            let size = SVGAttributes.pixels(style.inherited("font-size"), percentOf: 16) ?? 16
            let family = style.inherited("font-family")
            guard let font = SVGImporter.resolveFont(family: family, weight: style.inherited("font-weight")) ?? {
                warnOnce("Font \(family ?? "?") is not installed; Helvetica was used.")
                return "Helvetica"
            }() else { return }
            let anchor = style.inherited("text-anchor")
            let align: TextAlignment = anchor == "middle" ? .center : anchor == "end" ? .right : .left
            let outliner = TextOutliner()
            guard let outline = try? outliner.outlines(for: s, fontName: font, pointSize: size, origin: .zero,
                                                       alignment: align) else { return }
            // Glyphs are Y-up; SVG user space is Y-down with the baseline at the cursor.
            let place = Transform2D(a: 1, b: 0, c: 0, d: -1, tx: cursor.x, ty: cursor.y).concatenating(ctm)
            paths += outline.map { $0.transformed(place) }
            label += s
            if align == .left { cursor.x += (try? outliner.advance(of: s, fontName: font, pointSize: size)) ?? 0 }
        }

        run(n)
        guard !paths.isEmpty else { return }
        let name = label.trimmingCharacters(in: .whitespaces)
        shapes.append(Shape(name: name.isEmpty ? "Text" : String(name.prefix(40)), layerID: layerID, paths: paths,
                            origin: .imported(format: "svg")))
    }

    /// `<image>` with an embedded (data: URI) picture → tracing image; linked files are skipped.
    mutating func addImage(_ n: SVGNode, ctm: Transform2D) {
        let x = SVGAttributes.pixels(n["x"]) ?? 0, y = SVGAttributes.pixels(n["y"]) ?? 0
        guard let w = SVGAttributes.pixels(n["width"]), let h = SVGAttributes.pixels(n["height"]), w > 0, h > 0 else {
            warnOnce("An <image> without a width and height was skipped.")
            return
        }
        guard let href = n["xlink:href"] ?? n["href"], href.hasPrefix("data:"), let comma = href.firstIndex(of: ",") else {
            warnOnce("Linked (not embedded) images were skipped; import the picture file itself.")
            return
        }
        let header = href[..<comma], payload = String(href[href.index(after: comma)...])
        let raw: Data? = header.contains(";base64")
            ? Data(base64Encoded: payload.filter { !$0.isWhitespace })
            : payload.removingPercentEncoding.map { Data($0.utf8) }
        guard let raw, let png = RasterCodec.png(fromEncoded: raw) else {
            warnOnce("An embedded image could not be decoded.")
            return
        }
        let corners = [Vec2(x, y), Vec2(x + w, y), Vec2(x, y + h), Vec2(x + w, y + h)].map { ctm.apply($0) }
        images.append(ImportedImage(rect: Rect2(points: corners), png: png))
    }
}
