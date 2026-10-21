import Foundation

/// Substitutes `{NAME}` placeholders in profile template lines.
struct TemplateRenderer {
    var values: [String: String]

    /// One left-to-right pass: a value is never re-scanned, so a tool named "Bit {S}" renders
    /// the same every time and a value cannot pull in another placeholder.
    func render(_ template: String) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}"),
                  let value = values[String(rest[afterOpen..<close])] else {
                out.append("{")
                rest = rest[afterOpen...]
                continue
            }
            out += value
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    func render(_ templates: [String]) -> [String] { templates.map(render) }

    /// Text safe to drop inside a parenthesised comment.
    static func commentSafe(_ text: String) -> String {
        PostProfile.asciiOnly(text).replacingOccurrences(of: "(", with: "[").replacingOccurrences(of: ")", with: "]")
    }
}
