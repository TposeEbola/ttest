import Foundation
import XCTest
@testable import BlueprintCore

final class PlanClipboardTests: XCTestCase {
    func testCopyingWallIncludesAttachedOpeningsAndKeepsOtherWallsOut() throws {
        let plan = FloorPlan.example
        let opening = try XCTUnwrap(plan.openings.first)
        let clipboard = try plan.copySelection(.init(wallIDs: [opening.wallID]))
        XCTAssertEqual(clipboard.walls.map(\.id), [opening.wallID])
        XCTAssertEqual(clipboard.openings.map(\.id), [opening.id])
        XCTAssertTrue(clipboard.sourceWalls.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(PlanClipboard.self, from: JSONEncoder().encode(clipboard)), clipboard)
    }

    func testCopyingStandaloneOpeningIncludesOnlyItsHostReference() throws {
        let plan = FloorPlan.example
        let opening = try XCTUnwrap(plan.openings.first)
        let clipboard = try plan.copySelection(.init(openingIDs: [opening.id]))
        XCTAssertTrue(clipboard.walls.isEmpty)
        XCTAssertEqual(clipboard.openings, [opening])
        XCTAssertEqual(clipboard.sourceWalls.map(\.id), [opening.wallID])
    }

    func testPastingWallGroupIntoOtherFloorRemapsIDsAndPreservesConnections() throws {
        let source = FloorPlan.example
        let clipboard = try source.copySelection(.init(wallIDs: Set(source.walls.map(\.id))))
        var destination = FloorPlan.empty
        let selection = try destination.paste(clipboard, offset: .init(x: 1000, y: -200))
        XCTAssertEqual(destination.walls.count, source.walls.count)
        XCTAssertEqual(destination.openings.count, source.openings.count)
        XCTAssertEqual(selection.wallIDs, Set(destination.walls.map(\.id)))
        XCTAssertTrue(selection.openingIDs.isEmpty, "Attached openings are implicitly selected with their wall")
        XCTAssertTrue(Set(source.walls.map(\.id)).isDisjoint(with: Set(destination.walls.map(\.id))))
        XCTAssertTrue(Set(source.openings.map(\.id)).isDisjoint(with: Set(destination.openings.map(\.id))))
        for (original, pasted) in zip(source.walls, destination.walls) {
            XCTAssertEqual(pasted.start.x, original.start.x + 1000)
            XCTAssertEqual(pasted.start.y, original.start.y - 200)
            XCTAssertEqual(pasted.length, original.length, accuracy: 0.000_001)
        }
        XCTAssertEqual(destination.walls[0].end, destination.walls[1].start)
        for (original, pasted) in zip(source.openings, destination.openings) {
            let index = try XCTUnwrap(source.walls.firstIndex { $0.id == original.wallID })
            XCTAssertEqual(pasted.wallID, destination.walls[index].id)
            XCTAssertEqual(pasted.offset, original.offset)
        }
    }

    func testStandaloneOpeningPasteProjectsOffsetOntoSelectedTargetWall() throws {
        var source = FloorPlan.empty
        let sourceWall = try source.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let opening = try source.addOpening(wallID: sourceWall, kind: .door, offset: 1000, width: 900, height: 2100)
        let clipboard = try source.copySelection(.init(openingIDs: [opening]))
        var destination = FloorPlan.empty
        let target = try destination.addWall(from: .init(x: 5000, y: 0), to: .init(x: 5000, y: 5000))
        let selection = try destination.paste(clipboard, offset: .init(x: 9999, y: 500), targetWallID: target)
        let pasted = try XCTUnwrap(destination.openings.first)
        XCTAssertEqual(pasted.wallID, target)
        XCTAssertEqual(pasted.offset, 1500)
        XCTAssertNotEqual(pasted.id, opening)
        XCTAssertEqual(selection.openingIDs, [pasted.id])
        XCTAssertTrue(selection.wallIDs.isEmpty)
    }

    func testOpeningPasteFailsAtomicallyWithoutHostOrWhenItDoesNotFitOrOverlaps() throws {
        var source = FloorPlan.empty
        let wall = try source.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let opening = try source.addOpening(wallID: wall, kind: .window, offset: 1000, width: 900, height: 1200)
        let clipboard = try source.copySelection(.init(openingIDs: [opening]))
        var empty = FloorPlan.empty
        XCTAssertThrowsError(try empty.paste(clipboard)) {
            XCTAssertEqual($0 as? PlanSelectionError, .missingHostWall)
        }
        XCTAssertEqual(empty, .empty)

        let original = source
        XCTAssertThrowsError(try source.paste(clipboard, offset: .init(x: 100, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .overlappingOpenings)
        }
        XCTAssertEqual(source, original)
        XCTAssertThrowsError(try source.paste(clipboard, offset: .init(x: 3500, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .openingOutsideWall)
        }
        XCTAssertEqual(source, original)
        let pasted = try source.paste(clipboard, offset: .init(x: 1500, y: 0))
        XCTAssertEqual(source.openings.count, 2)
        XCTAssertEqual(pasted.openingIDs.count, 1)
    }

    func testRotatingWallGroupPreservesLengthsAttachmentsAndUnselectedWalls() throws {
        var plan = FloorPlan.empty
        let first = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 3000, y: 0))
        let second = try plan.addWall(from: .init(x: 3000, y: 0), to: .init(x: 3000, y: 2000))
        let unselected = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: -1000, y: 0))
        try plan.addOpening(wallID: first, kind: .door, offset: 1000, width: 900, height: 2100)
        let opening = plan.openings[0]
        let untouched = try XCTUnwrap(plan.walls.first { $0.id == unselected })
        let selection = PlanSelection(wallIDs: [first, second])
        try plan.rotateSelection(selection, byDegrees: 90, around: .init(x: 0, y: 0))
        XCTAssertEqual(plan.walls[0].start, .init(x: 0, y: 0))
        XCTAssertEqual(plan.walls[0].end, .init(x: 0, y: 3000))
        XCTAssertEqual(plan.walls[1].start, plan.walls[0].end)
        XCTAssertEqual(plan.walls[1].end, .init(x: -2000, y: 3000))
        XCTAssertEqual(plan.walls[0].length, 3000)
        XCTAssertEqual(plan.walls[1].length, 2000)
        XCTAssertEqual(plan.walls[2], untouched)
        XCTAssertEqual(plan.openings[0], opening)
        XCTAssertEqual(plan.walls[0].point(at: opening.offset), .init(x: 0, y: 1000))
    }

    func testDefaultRotationPivotUsesSelectionBoundsCentre() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 1000, y: 2000), to: .init(x: 3000, y: 2000))
        let selection = PlanSelection(wallIDs: [wall])
        XCTAssertEqual(try plan.selectionCenter(selection), .init(x: 2000, y: 2000))
        try plan.rotateSelection(selection, byDegrees: 90)
        XCTAssertEqual(plan.walls[0].start, .init(x: 2000, y: 1000))
        XCTAssertEqual(plan.walls[0].end, .init(x: 2000, y: 3000))
    }

    func testRotatingStandaloneOpeningOrMixedUnhostedSelectionIsRejected() throws {
        var plan = FloorPlan.example
        let opening = try XCTUnwrap(plan.openings.first)
        let otherWall = try XCTUnwrap(plan.walls.first { $0.id != opening.wallID })
        let original = plan
        for selection in [PlanSelection(openingIDs: [opening.id]), .init(wallIDs: [otherWall.id], openingIDs: [opening.id])] {
            XCTAssertThrowsError(try plan.rotateSelection(selection, byDegrees: 90)) {
                XCTAssertEqual($0 as? PlanSelectionError, .selectHostWallToRotate)
            }
            XCTAssertEqual(plan, original)
        }
    }

    func testMalformedClipboardAndTransformAreRejectedWithoutChangingDestination() throws {
        var plan = FloorPlan.example
        let original = plan
        let wall = plan.walls[0]
        let duplicate = PlanClipboard(walls: [wall, wall])
        XCTAssertThrowsError(try plan.paste(duplicate))
        XCTAssertEqual(plan, original)
        var invalid = wall
        invalid.start.x = .infinity
        XCTAssertThrowsError(try plan.paste(PlanClipboard(walls: [invalid])))
        XCTAssertEqual(plan, original)
        XCTAssertThrowsError(try plan.paste(PlanClipboard(walls: [wall]), offset: .init(x: .nan, y: 0)))
        XCTAssertEqual(plan, original)
        XCTAssertThrowsError(try plan.rotateSelection(.init(wallIDs: [wall.id]), byDegrees: .infinity))
        XCTAssertEqual(plan, original)
        XCTAssertThrowsError(try plan.rotateSelection(.init(wallIDs: [wall.id]), byDegrees: 90, around: .init(x: .nan, y: 0)))
        XCTAssertEqual(plan, original)
    }

    func testEmptyOrMissingSelectionsAndMalformedClipboardDataAreRejected() throws {
        let plan = FloorPlan.example
        XCTAssertThrowsError(try plan.copySelection(.init()))
        XCTAssertThrowsError(try plan.copySelection(.init(wallIDs: [UUID()])))
        XCTAssertThrowsError(try plan.copySelection(.init(openingIDs: [UUID()])))
        let bad = Data(#"{"walls":[],"openings":[],"sourceWalls":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PlanClipboard.self, from: bad))
    }

    func testDocumentLockProtectsPasteAndRotation() throws {
        var document = PlanDocument.example
        let wall = document.activeLayer.plan.walls[0]
        let selection = PlanSelection(wallIDs: [wall.id])
        let clipboard = try document.activeLayer.plan.copySelection(selection)
        try document.setLayerLocked(id: document.activeLayerID, locked: true)
        let before = document
        XCTAssertThrowsError(try document.editActivePlan { try $0.paste(clipboard) }) {
            XCTAssertEqual($0 as? PlanDocumentError, .lockedLayer)
        }
        XCTAssertEqual(document, before)
        XCTAssertThrowsError(try document.editActivePlan { try $0.rotateSelection(selection, byDegrees: 90) }) {
            XCTAssertEqual($0 as? PlanDocumentError, .lockedLayer)
        }
        XCTAssertEqual(document, before)
    }
}
