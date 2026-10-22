import SwiftUI

/// Errors raised by an action inside a sheet (a file that cannot be written or read). An alert set on
/// the document sits under the sheet, where SwiftUI drops it, so the user saw nothing and the sheet
/// stayed open as if the file had been written. The sheet shows the error itself, above its buttons,
/// until the next attempt.
enum SheetError {
    /// Runs `write`; the text for the sheet to show when it fails, nil when it worked.
    static func attempt(_ title: String, _ write: () throws -> Void) -> String? {
        do { try write(); return nil } catch { return message(title, error) }
    }

    static func message(_ title: String, _ error: Error) -> String { message(title, error.localizedDescription) }

    static func message(_ title: String, _ detail: String) -> String { "\(title): \(detail)" }
}

/// The error row of a sheet: nothing when `message` is nil.
struct SheetErrorRow: View {
    var message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(Color.errorText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("sheet-error")
        }
    }
}
