import CADCore

/// `Shape` means the CAD vector shape throughout the app (SwiftUI also exports a `Shape`
/// protocol; module-level declarations win over imports).
typealias Shape = CADCore.Shape
/// Likewise for `Path` (SwiftUI.Path).
typealias Path = CADCore.Path
