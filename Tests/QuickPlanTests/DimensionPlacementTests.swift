#if os(macOS)
import AppKit
import XCTest
import BlueprintCore
@testable import QuickPlan

final class DimensionPlacementTests: XCTestCase {
    func testOffsetPlacementKeepsMeasuredAnchorsAndCommitsOneUndoableEdit() async throws {
        try await MainActor.run {
            let store = dimensionPlacementStore()
            let original = store.document
            let start = PlanPoint(x: 100, y: 200)
            let end = PlanPoint(x: 3100, y: 200)

            store.commitDimension(from: start, to: end, offset: -600)

            let dimension = try XCTUnwrap(store.selectedDimension)
            XCTAssertEqual(dimension.start, start)
            XCTAssertEqual(dimension.end, end)
            XCTAssertEqual(dimension.length, 3000, accuracy: 0.000_001)
            XCTAssertEqual(dimension.offset, -600)
            XCTAssertEqual(dimension.lineStart, PlanPoint(x: 100, y: -400))
            XCTAssertEqual(dimension.lineEnd, PlanPoint(x: 3100, y: -400))
            XCTAssertEqual(store.plan.walls, original.activeLayer.plan.walls)
            XCTAssertEqual(store.plan.openings, original.activeLayer.plan.openings)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertEqual(store.undoStack.count, 1)
            XCTAssertTrue(store.isDirty)

            let placed = store.document
            store.undo()
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.isDirty)
            XCTAssertFalse(store.canUndo)
            store.redo()
            XCTAssertEqual(store.document, placed)
            XCTAssertEqual(store.plan.dimensions.first { $0.id == dimension.id }, dimension)
        }
    }

    func testChangingOnlyOffsetMovesDimensionLineWithoutRemeasuring() async throws {
        try await MainActor.run {
            let store = dimensionPlacementStore()
            store.commitDimension(from: .init(x: 500, y: 100), to: .init(x: 500, y: 4100), offset: 300)
            let original = try XCTUnwrap(store.selectedDimension)
            let beforeUpdate = store.document

            store.updateDimension(id: original.id, start: original.start, end: original.end, offset: -450)

            let updated = try XCTUnwrap(store.selectedDimension)
            XCTAssertEqual(updated.start, original.start)
            XCTAssertEqual(updated.end, original.end)
            XCTAssertEqual(updated.length, original.length)
            XCTAssertEqual(updated.offset, -450)
            XCTAssertEqual(updated.lineStart, PlanPoint(x: 950, y: 100))
            XCTAssertEqual(updated.lineEnd, PlanPoint(x: 950, y: 4100))
            XCTAssertEqual(updated.labelAngleDegrees, -90)
            XCTAssertEqual(store.undoStack.count, 2)
            store.undo()
            XCTAssertEqual(store.document, beforeUpdate)
            XCTAssertEqual(store.plan.dimensions.first { $0.id == original.id }, original)
        }
    }

    func testOmittedOffsetDefaultsToZeroOnCreationAndPreservesOffsetOnUpdate() async throws {
        try await MainActor.run {
            let store = dimensionPlacementStore()
            store.commitDimension(from: .init(x: 100, y: 100), to: .init(x: 1100, y: 100))
            let created = try XCTUnwrap(store.selectedDimension)
            XCTAssertEqual(created.offset, 0)
            XCTAssertEqual(created.lineStart, created.start)
            XCTAssertEqual(created.lineEnd, created.end)

            store.updateDimension(id: created.id, start: created.start, end: created.end, offset: 400)
            let movedStart = PlanPoint(x: 100, y: 500)
            let movedEnd = PlanPoint(x: 1100, y: 500)
            store.updateDimension(id: created.id, start: movedStart, end: movedEnd)

            let updated = try XCTUnwrap(store.selectedDimension)
            XCTAssertEqual(updated.start, movedStart)
            XCTAssertEqual(updated.end, movedEnd)
            XCTAssertEqual(updated.offset, 400, "Editing anchors through the existing API must retain the placed line's offset")
            XCTAssertEqual(updated.length, 1000, accuracy: 0.000_001)
            XCTAssertEqual(updated.lineStart, PlanPoint(x: 100, y: 900))
            XCTAssertEqual(updated.lineEnd, PlanPoint(x: 1100, y: 900))
        }
    }

    func testInvalidOffsetsAndProtectedFloorsRejectEditsWithoutDocumentHistoryOrSelectionChanges() async throws {
        try await MainActor.run {
            let store = dimensionPlacementStore()
            store.commitDimension(from: .init(x: 100, y: 200), to: .init(x: 3100, y: 200), offset: 250)
            let dimension = try XCTUnwrap(store.selectedDimension)
            store.setDefaultThickness(200)
            store.undo()
            store.selectWall(try XCTUnwrap(store.plan.walls.first).id)
            let before = store.document
            let undoBefore = store.undoStack
            let redoBefore = store.redoStack
            let selectionBefore = store.selection
            let selectedDimensionBefore = store.selectedDimensionID
            let selectedAreaBefore = store.selectedAreaID
            XCTAssertFalse(redoBefore.isEmpty, "A rejected edit must also retain existing redo history")

            for invalidOffset in [Double.nan, .infinity, -.infinity] {
                store.commitDimension(from: dimension.start, to: dimension.end, offset: invalidOffset)
                store.updateDimension(id: dimension.id, start: dimension.start, end: dimension.end, offset: invalidOffset)
                XCTAssertEqual(store.document, before)
                XCTAssertEqual(store.undoStack, undoBefore)
                XCTAssertEqual(store.redoStack, redoBefore)
                XCTAssertEqual(store.selection, selectionBefore)
                XCTAssertEqual(store.selectedDimensionID, selectedDimensionBefore)
                XCTAssertEqual(store.selectedAreaID, selectedAreaBefore)
            }

            for hideInsteadOfLock in [false, true] {
                let protectedStore = dimensionPlacementStore()
                protectedStore.commitDimension(from: dimension.start, to: dimension.end, offset: 250)
                let protectedDimension = try XCTUnwrap(protectedStore.selectedDimension)
                if hideInsteadOfLock {
                    protectedStore.setLayerVisible(id: protectedStore.activeLayer.id, visible: false)
                } else {
                    protectedStore.setLayerLocked(id: protectedStore.activeLayer.id, locked: true)
                }
                let protectedDocument = protectedStore.document
                let protectedUndo = protectedStore.undoStack
                let protectedRedo = protectedStore.redoStack
                let protectedSelection = protectedStore.selection
                let protectedDimensionID = protectedStore.selectedDimensionID
                let protectedAreaID = protectedStore.selectedAreaID

                protectedStore.commitDimension(from: dimension.start, to: dimension.end, offset: -500)
                protectedStore.updateDimension(id: protectedDimension.id, start: dimension.start, end: dimension.end, offset: -500)

                XCTAssertEqual(protectedStore.document, protectedDocument)
                XCTAssertEqual(protectedStore.undoStack, protectedUndo)
                XCTAssertEqual(protectedStore.redoStack, protectedRedo)
                XCTAssertEqual(protectedStore.selection, protectedSelection)
                XCTAssertEqual(protectedStore.selectedDimensionID, protectedDimensionID)
                XCTAssertEqual(protectedStore.selectedAreaID, protectedAreaID)
            }
        }
    }
}

@MainActor
private func dimensionPlacementStore() -> PlanStore {
    PlanStore(pasteboard: NSPasteboard(name: .init("QuickPlan.dimension-placement.\(UUID().uuidString)")))
}
#endif
