import AppKit
import CADCore
import Foundation
import SwiftUI
import Testing
@testable import KerfApp

@Suite struct IOVariablesTests {
    @Test func fieldStyleParsesExpressions() throws {
        var d = Document()
        d.userVariables = [DocumentVariable(name: "gap", value: 0.1)]
        let style = ExpressionNumberStyle(variables: d.variableTable, units: .inch)
        #expect(try style.parseStrategy.parse("=thickness - gap") == 0.65)
        #expect(abs(try style.parseStrategy.parse("6.35mm") - 0.25) < 1e-12)
        #expect(try style.parseStrategy.parse("0.5") == 0.5)
        #expect(style.format(0.125) == "0.125")
        #expect(throws: (any Error).self) { try style.parseStrategy.parse("=nope") }
    }

    @Test @MainActor func editorRenders() throws {
        var p = AppTestSupport.project()
        p.document.userVariables = [DocumentVariable(name: "rail", value: 2.5)]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        let host = NSHostingView(rootView: DocumentVariablesSheet(document: doc))
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 420)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
    }
}
