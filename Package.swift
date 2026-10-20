// swift-tools-version: 6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Kerf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kerf", targets: ["KerfApp"]),
        .library(name: "CADCore", targets: ["CADCore"]),
        .library(name: "CAMCore", targets: ["CAMCore"]),
        .library(name: "PostCore", targets: ["PostCore"]),
    ],
    targets: [
        // Vendored Clipper2 (Boost Software License). Never edit — see THIRD_PARTY.md.
        .target(
            name: "Clipper2",
            path: "Vendor/Clipper2",
            exclude: ["LICENSE"],
            sources: ["src"],
            publicHeadersPath: "include",
            cxxSettings: [.unsafeFlags(["-w"])]
        ),
        // C-compatible wrapper over Clipper2 + Boost.Polygon Voronoi.
        .target(
            name: "CGeom",
            dependencies: ["Clipper2"],
            path: "Sources/CGeom",
            cxxSettings: [
                .headerSearchPath("../../Vendor/Boost/include"),
                .headerSearchPath("../../Vendor/Clipper2/include"),
            ]
        ),
        .target(name: "CADCore", dependencies: ["CGeom"], swiftSettings: swift5),
        .target(name: "CAMCore", dependencies: ["CADCore", "CGeom"], swiftSettings: swift5),
        .target(name: "PostCore", dependencies: ["CADCore", "CAMCore"], swiftSettings: swift5),
        .executableTarget(
            name: "KerfApp",
            dependencies: ["CADCore", "CAMCore", "PostCore"],
            swiftSettings: swift5
        ),
        .testTarget(name: "CGeomTests", dependencies: ["CGeom"], swiftSettings: swift5),
        .testTarget(name: "CADCoreTests", dependencies: ["CADCore"], swiftSettings: swift5),
        .testTarget(name: "CAMCoreTests", dependencies: ["CAMCore", "CADCore"], swiftSettings: swift5),
        .testTarget(name: "PostCoreTests", dependencies: ["PostCore", "CAMCore", "CADCore"], swiftSettings: swift5),
        .testTarget(name: "KerfAppTests", dependencies: ["KerfApp", "PostCore", "CAMCore", "CADCore"],
                    swiftSettings: swift5),
    ],
    cxxLanguageStandard: .cxx17
)
