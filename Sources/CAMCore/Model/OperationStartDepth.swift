import Foundation

// Operations whose start depth means "the material above is already gone": the flute check
// measures their cuts from there (see `ToolpathOperation.startDepth`). Moulding's start depth
// is an offset into solid material and keeps the default of 0.

extension ProfileOperation { public var startDepth: Double { params.depth.startDepth } }
extension PocketOperation { public var startDepth: Double { params.depth.startDepth } }
extension FlutingOperation { public var startDepth: Double { params.depth.startDepth } }
extension EngraveOperation { public var startDepth: Double { params.depth.startDepth } }
extension DrillOperation { public var startDepth: Double { params.startDepth } }
extension HoleMillOperation { public var startDepth: Double { params.startDepth } }
extension ChamferOperation { public var startDepth: Double { params.startDepth } }
extension VCarveOperation { public var startDepth: Double { params.startDepth } }
extension PhotoVCarveOperation { public var startDepth: Double { params.startDepth } }
