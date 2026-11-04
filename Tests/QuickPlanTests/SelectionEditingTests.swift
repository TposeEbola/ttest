#if os(macOS)
import AppKit
import XCTest
import BlueprintCore
@testable import QuickPlan

final class SelectionEditingTests: XCTestCase {
    func testSelectAllTargetsActiveFloorWallsAndRespectsLock() async {
        await MainActor.run {
            let store = selectionTestStore()
            store.selectAll()
            XCTAssertEqual(store.selection.wallIDs, Set(store.plan.walls.map(\.id)))
            XCTAssertTrue(store.selection.openingIDs.isEmpty, "Attached openings are included implicitly")
            XCTAssertFalse(store.isDirty)
            store.setLayerLocked(id: store.activeLayer.id, locked: true)
            store.selectAll()
            XCTAssertTrue(store.selection.isEmpty)
        }
    }
    func testShiftSelectionTogglesAndDeletesAsOneEdit() async throws {
        try await MainActor.run {
            let store = selectionTestStore()
            let original = store.plan
            let first = original.walls[0].id
            let second = original.walls[1].id
            let door = try XCTUnwrap(original.openings.first { $0.kind == .door })
            store.selectWall(first)
            store.selectWall(second, extending: true)
            XCTAssertEqual(store.selection.wallIDs, Set([first, second]))
            XCTAssertNil(store.selectedWallID)
            store.selectWall(first, extending: true)
            XCTAssertEqual(store.selectedWallID, second)
            store.selectWall(first, extending: true)
            store.selectOpening(door.id, extending: true)
            XCTAssertFalse(store.isDirty)
            XCTAssertFalse(store.canUndo)

            store.deleteSelection()
            XCTAssertEqual(store.plan.walls.count, original.walls.count - 2)
            XCTAssertTrue(store.plan.openings.isEmpty)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertEqual(store.undoStack.count, 1)
            store.undo()
            XCTAssertEqual(store.plan, original)
            XCTAssertFalse(store.isDirty)
        }
    }

    func testCopyAndRepeatedPasteCreateIndependentOffsetItems() async throws {
        try await MainActor.run {
            let store = selectionTestStore()
            let original = store.plan
            let source = original.walls[0]
            store.selectWall(source.id)
            store.copySelection()
            XCTAssertFalse(store.canUndo, "Copying must not modify document history")
            XCTAssertTrue(store.canPasteSelection)

            store.pasteSelection()
            let firstCopy = try XCTUnwrap(store.selectedWall)
            XCTAssertNotEqual(firstCopy.id, source.id)
            XCTAssertEqual(firstCopy.start.x, source.start.x + 304.8, accuracy: 0.000_001)
            XCTAssertEqual(store.plan.openings.count, original.openings.count + 1)
            let copiedOpening = try XCTUnwrap(store.plan.openings.first { $0.wallID == firstCopy.id })
            XCTAssertNotEqual(copiedOpening.id, original.openings.first { $0.wallID == source.id }?.id)

            store.pasteSelection()
            let secondCopy = try XCTUnwrap(store.selectedWall)
            XCTAssertNotEqual(secondCopy.id, firstCopy.id)
            XCTAssertEqual(secondCopy.start.x, source.start.x + 609.6, accuracy: 0.000_001)
            XCTAssertEqual(secondCopy.start.y, source.start.y + 609.6, accuracy: 0.000_001)
            XCTAssertEqual(store.undoStack.count, 2)
            store.undo()
            XCTAssertEqual(store.plan.walls.count, original.walls.count + 1)
        }
    }

    func testPasteInPlaceOntoAnotherFloorKeepsAlignmentAndNewIDs() async throws {
        try await MainActor.run {
            let store = selectionTestStore()
            let sourceFloorID = store.activeLayer.id
            let source = store.plan.walls[0]
            let originalFloor = store.plan
            store.selectWall(source.id)
            store.copySelection()
            store.addLayer()
            XCTAssertTrue(store.plan.walls.isEmpty)

            store.pasteInPlace()
            let copy = try XCTUnwrap(store.selectedWall)
            XCTAssertNotEqual(copy.id, source.id)
            XCTAssertEqual(copy.start, source.start)
            XCTAssertEqual(copy.end, source.end)
            XCTAssertEqual(store.document.layers.first { $0.id == sourceFloorID }?.plan, originalFloor)
            XCTAssertEqual(store.plan.openings.count, 1)
            store.undo()
            XCTAssertTrue(store.plan.walls.isEmpty)
            XCTAssertEqual(store.document.layers.first { $0.id == sourceFloorID }?.plan, originalFloor)
        }
    }

    func testInvalidClipboardCannotChangePlanOrHistory() async {
        await MainActor.run {
            let pasteboard = selectionTestPasteboard()
            let store = PlanStore(pasteboard: pasteboard)
            let before = store.document
            pasteboard.setData(Data("not a QuickPlan selection".utf8), forType: PlanStore.selectionPasteboardType)
            store.pasteSelection()
            XCTAssertEqual(store.document, before)
            XCTAssertFalse(store.canUndo)
            XCTAssertTrue(store.selection.isEmpty)
        }
    }

    func testRotationPreviewOnlyCreatesHistoryWhenApplied() async throws {
        try await MainActor.run {
            let store = selectionTestStore()
            let original = store.document
            let wall = store.plan.walls[0]
            store.selectWall(wall.id)
            store.beginRotation()
            store.previewRotation(30)
            XCTAssertEqual(store.document, original)
            XCTAssertNotEqual(store.rotationPreviewPlan, store.plan)
            XCTAssertFalse(store.isDirty)
            XCTAssertFalse(store.canUndo)
            XCTAssertNotNil(store.rotationPivot)

            store.previewRotation(44)
            XCTAssertEqual(store.rotationDegrees, 45, accuracy: 0.000_001)
            XCTAssertEqual(try XCTUnwrap(store.rotationGuideDegrees), 45, accuracy: 0.000_001)
            let preview = try XCTUnwrap(store.rotationPreviewPlan)
            store.commitRotation()
            XCTAssertEqual(store.plan, preview)
            XCTAssertEqual(store.selectedWallID, wall.id)
            XCTAssertEqual(store.undoStack.count, 1)
            XCTAssertFalse(store.rotationPreviewActive)
            store.undo()
            XCTAssertEqual(store.document, original)

            store.selectWall(wall.id)
            store.beginRotation()
            store.previewRotation(20)
            store.cancelRotation()
            XCTAssertEqual(store.document, original)
            XCTAssertNil(store.rotationPreviewPlan)
            XCTAssertFalse(store.canUndo)
        }
    }

    func testRotationGuidesSnapWorldBearingAndPreserveNearestTurn() async throws {
        try await MainActor.run {
            let store = selectionTestStore()
            store.commitWall(from: .init(x: 10_000, y: 10_000),
                             to: .init(x: 10_000 + 1000 * cos(.pi / 6), y: 10_500))
            store.beginRotation()
            store.previewRotation(14)
            XCTAssertEqual(store.rotationDegrees, 15, accuracy: 0.000_001)
            XCTAssertEqual(try XCTUnwrap(store.rotationGuideDegrees), 45, accuracy: 0.000_001)
            store.previewRotation(-31)
            XCTAssertEqual(store.rotationDegrees, -30, accuracy: 0.000_001)
            XCTAssertEqual(try XCTUnwrap(store.rotationGuideDegrees), 0, accuracy: 0.000_001)
        }
    }

    func testSelectionOrLayerChangeCancelsRotationWithoutCommittingIt() async {
        await MainActor.run {
            let store = selectionTestStore()
            let before = store.plan
            store.selectWall(before.walls[0].id)
            store.beginRotation()
            store.previewRotation(25)
            store.selectWall(before.walls[1].id)
            XCTAssertFalse(store.rotationPreviewActive)
            XCTAssertEqual(store.plan, before)

            store.beginRotation()
            store.previewRotation(35)
            store.addLayer()
            XCTAssertFalse(store.rotationPreviewActive)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertEqual(store.document.layers[0].plan, before)
        }
    }

    func testInvalidRotationPreviewCannotCommitPreviousValidAngle() async {
        await MainActor.run {
            let store = selectionTestStore()
            let original = store.document
            store.selectWall(store.plan.walls[0].id)
            store.beginRotation()
            store.previewRotation(30)
            XCTAssertNotNil(store.rotationPreviewPlan)
            store.previewRotation(.nan)
            XCTAssertNil(store.rotationPreviewPlan)
            XCTAssertTrue(store.rotationDegrees.isFinite)
            store.commitRotation()
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.canUndo)
        }
    }

    func testOpeningOnlySelectionCannotRotateAwayFromItsHost() async throws {
        try await MainActor.run {
            let store = selectionTestStore()
            let opening = try XCTUnwrap(store.plan.openings.first)
            let before = store.document
            store.selectOpening(opening.id)
            XCTAssertFalse(store.canRotateSelection)
            store.beginRotation()
            XCTAssertFalse(store.rotationPreviewActive)
            XCTAssertEqual(store.document, before)
            XCTAssertFalse(store.canUndo)
        }
    }
}

@MainActor
private func selectionTestPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("QuickPlan.SelectionTests.\(UUID().uuidString)"))
}

@MainActor
private func selectionTestStore() -> PlanStore { PlanStore(pasteboard: selectionTestPasteboard()) }
#endif
