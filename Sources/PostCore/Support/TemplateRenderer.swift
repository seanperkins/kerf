import Foundation

/// Substitutes `{NAME}` placeholders in profile template lines.
struct TemplateRenderer {
    var values: [String: String]

    func render(_ template: String) -> String {
        var out = template
        for (key, value) in values {
            out = out.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return out
    }

    func render(_ templates: [String]) -> [String] { templates.map(render) }

    /// Text safe to drop inside a parenthesised comment.
    static func commentSafe(_ text: String) -> String {
        PostProfile.asciiOnly(text).replacingOccurrences(of: "(", with: "[").replacingOccurrences(of: ")", with: "]")
    }
}
