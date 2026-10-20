import CADCore
import Foundation
import Testing

@Suite struct LayoutProductionPlateTests {
    @Test func parsesHeaderAndRecords() {
        let t = CSVTable.parse("Name, Room\nAda Lovelace, 101\nAlan Turing,202\n")
        #expect(t.headers == ["Name", "Room"])
        #expect(t.rows == [["Ada Lovelace", "101"], ["Alan Turing", "202"]])
        #expect(t.record(1) == ["Name": "Alan Turing", "Room": "202"])
    }

    @Test func handlesQuotesNewlinesCRLFAndBOM() {
        let t = CSVTable.parse("\u{FEFF}Name,Title\r\n\"Smith, J\",\"Says \"\"hi\"\"\"\r\n\r\n\"Two\nLines\",x\r\n")
        #expect(t.headers == ["Name", "Title"])
        #expect(t.rows.count == 2)
        #expect(t.rows[0] == ["Smith, J", "Says \"hi\""])
        #expect(t.rows[1] == ["Two\nLines", "x"])
    }

    @Test func detectsSemicolonAndTabDelimiters() {
        #expect(CSVTable.parse("A;B\n1,5;2\n").rows == [["1,5", "2"]])
        #expect(CSVTable.parse("A\tB\n1\t2").rows == [["1", "2"]])
    }

    @Test func shortRowsGiveEmptyFieldsAndEmptyTextGivesNoTable() {
        let t = CSVTable.parse("A,B,C\n1\n")
        #expect(t.record(0) == ["A": "1", "B": "", "C": ""])
        #expect(CSVTable.parse("").headers.isEmpty)
        #expect(CSVTable.parse("\n\n").rows.isEmpty)
    }

    @Test func fillsPlaceholdersCaseInsensitively() {
        let r = ProductionPlates.fill("Room {room}\n{ Name }", record: ["Name": "Ada", "Room": "101"])
        #expect(r.text == "Room 101\nAda")
        #expect(r.missing.isEmpty)
        #expect(ProductionPlates.fields(in: "{A} and {B} and {A}") == ["A", "B"])
    }

    @Test func leavesUnknownAndMalformedPlaceholdersAlone() {
        let r = ProductionPlates.fill("{Nope} {} {open {Name}", record: ["Name": "Ada"])
        #expect(r.text == "{Nope} {} {open Ada")
        #expect(r.missing == ["Nope"])
    }

    @Test func gridFillsAcrossThenDown() {
        let p = ProductionPlates.pitch(size: Vec2(4, 2), gap: Vec2(0.5, 0.25))
        #expect(p == Vec2(4.5, 2.25))
        #expect(ProductionPlates.offset(index: 0, columns: 3, pitch: p) == Vec2(0, 0))
        #expect(ProductionPlates.offset(index: 2, columns: 3, pitch: p) == Vec2(9, 0))
        #expect(ProductionPlates.offset(index: 4, columns: 3, pitch: p) == Vec2(4.5, -2.25))
        #expect(ProductionPlates.offset(index: 3, columns: 3, pitch: p, rowsDown: false) == Vec2(0, 2.25))
    }

    @Test func columnsThatFitTheMaterial() {
        let material = Rect2(x: 0, y: 0, width: 24, height: 12)
        let plate = Rect2(x: 1, y: 8, width: 5, height: 3)
        // Plates at x = 1, 6.5, 12, 17.5 (ends 22.5); a fifth would end at 28.
        #expect(ProductionPlates.columnsThatFit(template: plate, gapX: 0.5, material: material) == 4)
        #expect(ProductionPlates.columnsThatFit(template: Rect2(x: 0, y: 0, width: 30, height: 1), gapX: 0, material: material) == 1)
    }
}
