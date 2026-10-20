import Foundation
@testable import CADCore

/// Fixture files live in Tests/Fixtures/CADCore (outside the target so SwiftPM ignores them).
enum IOFixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/CADCore", isDirectory: true)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

func approx(_ a: Rect2, _ b: Rect2, _ tol: Double = 1e-6) -> Bool {
    a.min.isApproximatelyEqual(to: b.min, tolerance: tol) && a.max.isApproximatelyEqual(to: b.max, tolerance: tol)
}
