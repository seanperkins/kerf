import Foundation

/// Which Arrange commands make sense for how many shapes are selected, so a menu item is disabled
/// instead of silently doing nothing.
struct ArrangeAvailability {
    var selectionCount: Int

    /// Anything selected: mirror, rotate, offset, edit nodes.
    var any: Bool { selectionCount >= 1 }
    /// Two or more: align to each other, group, combine, boolean operations.
    var pair: Bool { selectionCount >= 2 }
    /// Three or more: distribute and equalise gaps.
    var triple: Bool { selectionCount >= 3 }

    /// Centring on the material needs one shape; every other alignment lines shapes up with each other.
    func canAlign(_ mode: AlignMode) -> Bool { mode == .materialCenter ? any : pair }
}

extension CanvasTool {
    /// "Rectangle (R)": the title with its single-key shortcut, for menus and tooltips. The key is
    /// shown in the title rather than as a menu key equivalent because an unmodified key equivalent
    /// would fire while typing in a text field.
    var titleWithKey: String { shortcut.map { "\(title) (\(String($0).uppercased()))" } ?? title }
}
