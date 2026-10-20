import CADCore
import Foundation

/// Job notes (io-job-notes): free text saved in the .kerf file, optionally shown when the file
/// is opened, and printed on the job sheet.
extension Document {
    /// The notes with surrounding blank lines/spaces removed ("" = none).
    var jobNotes: String {
        get { notes ?? "" }
        set {
            let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            notes = t.isEmpty ? nil : t
        }
    }

    /// Whether opening the file shows the notes.
    var showsNotesOnOpen: Bool {
        get { showNotesOnOpen ?? false }
        set { showNotesOnOpen = newValue ? true : nil }
    }

    /// True when the notes should pop up as the document window opens.
    var wantsNotesOnOpen: Bool { showsNotesOnOpen && !jobNotes.isEmpty }
}

extension KerfDocument {
    /// Called when the document window appears: shows the notes if the file asks for it.
    func showJobNotesOnOpenIfNeeded() {
        guard document.wantsNotesOnOpen else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sheet == nil else { return }
            self.sheet = .io(.jobNotes(openedWithFile: true))
        }
    }

    func setJobNotes(_ text: String, showOnOpen: Bool) {
        perform("Edit Job Notes") {
            $0.document.jobNotes = text
            $0.document.showsNotesOnOpen = showOnOpen
        }
    }
}
