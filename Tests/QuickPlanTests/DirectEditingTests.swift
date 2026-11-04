#if os(macOS)
import AppKit
import XCTest
import BlueprintCore
@testable import QuickPlan

final class DirectEditingTests: XCTestCase {
    func testDragPreviewsWithoutChangingDocumentThenCommitsAsOneUndoableEdit() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let original = store.document
            let wall = try XCTUnwrap(store.plan.walls.first)
            let neighbour = try XCTUnwrap(store.plan.walls.first { $0.id != wall.id && $0.start == wall.end })
            store.selectWall(wall.id)

            store.beginSelectionDrag()
            store.previewSelectionDrag(by: .init(x: 304.8, y: 152.4))

            XCTAssertTrue(store.dragPreviewActive)
            let preview = try XCTUnwrap(store.dragPreviewPlan)
            XCTAssertEqual(store.canvasPlan, preview)
            XCTAssertNotEqual(preview, store.plan)
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.isDirty)
            XCTAssertFalse(store.canUndo)
            let previewWall = try XCTUnwrap(preview.walls.first { $0.id == wall.id })
            let previewNeighbour = try XCTUnwrap(preview.walls.first { $0.id == neighbour.id })
            XCTAssertEqual(previewWall.end, previewNeighbour.start, "Dragging must retain the shared corner")
            XCTAssertEqual(previewWall.length, wall.length, accuracy: 0.000_001)

            store.commitSelectionDrag()

            XCTAssertEqual(store.plan, preview)
            XCTAssertFalse(store.dragPreviewActive)
            XCTAssertNil(store.dragPreviewPlan)
            XCTAssertEqual(store.selectedWallID, wall.id)
            XCTAssertTrue(store.isDirty)
            XCTAssertEqual(store.undoStack.count, 1)
            store.undo()
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.isDirty)
            store.redo()
            XCTAssertEqual(store.plan, preview)
        }
    }

    func testInvalidDragCannotCommitAnEarlierValidPreview() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let original = store.document
            let wall = try XCTUnwrap(store.plan.walls.first)
            store.selectWall(wall.id)
            store.beginSelectionDrag()
            store.previewSelectionDrag(by: .init(x: 100, y: 100))
            XCTAssertNotNil(store.dragPreviewPlan)

            store.previewSelectionDrag(by: .init(x: .nan, y: 100))

            XCTAssertNil(store.dragPreviewPlan)
            XCTAssertEqual(store.canvasPlan, store.plan)
            store.commitSelectionDrag()
            XCTAssertFalse(store.dragPreviewActive)
            XCTAssertEqual(store.document, original)
            XCTAssertTrue(store.undoStack.isEmpty)
            XCTAssertFalse(store.isDirty)
        }
    }

    func testLockHideAndPanToolChangesCancelUncommittedDrag() async throws {
        try await MainActor.run {
            for action in 0..<3 {
                let store = directEditingStore()
                let originalPlan = store.plan
                let wall = try XCTUnwrap(originalPlan.walls.first)
                store.selectWall(wall.id)
                store.beginSelectionDrag()
                store.previewSelectionDrag(by: .init(x: 100, y: 100))
                XCTAssertNotNil(store.dragPreviewPlan)

                switch action {
                case 0: store.setLayerLocked(id: store.activeLayer.id, locked: true)
                case 1: store.setLayerVisible(id: store.activeLayer.id, visible: false)
                default: store.chooseTool(.pan)
                }

                XCTAssertFalse(store.dragPreviewActive)
                XCTAssertNil(store.dragPreviewPlan)
                XCTAssertEqual(store.plan, originalPlan)
                store.commitSelectionDrag()
                XCTAssertEqual(store.plan, originalPlan, "A cancelled drag must never be committed later")
                if action == 2 {
                    XCTAssertEqual(store.tool, .pan)
                    XCTAssertTrue(store.undoStack.isEmpty)
                    XCTAssertFalse(store.isDirty)
                }
            }
        }
    }

    func testSwitchingFloorsCancelsDragWithoutChangingEitherFloor() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let firstFloorID = store.activeLayer.id
            store.duplicateActiveLayer()
            let originalLayers = store.document.layers
            let historyCount = store.undoStack.count
            let wall = try XCTUnwrap(store.plan.walls.first)
            store.selectWall(wall.id)
            store.beginSelectionDrag()
            store.previewSelectionDrag(by: .init(x: 100, y: 100))
            XCTAssertNotNil(store.dragPreviewPlan)

            store.selectLayer(id: firstFloorID)

            XCTAssertFalse(store.dragPreviewActive)
            XCTAssertNil(store.dragPreviewPlan)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertEqual(store.document.layers, originalLayers)
            XCTAssertEqual(store.undoStack.count, historyCount)
            store.commitSelectionDrag()
            XCTAssertEqual(store.document.layers, originalLayers)
        }
    }

    func testDoorRotationChangesSwingWhileKeepingItsWallAndOpeningFixed() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let original = store.document
            let door = try XCTUnwrap(store.plan.openings.first { $0.kind == .door })
            store.selectOpening(door.id)
            XCTAssertTrue(store.canRotateSelection)

            store.beginRotation()
            store.previewRotation(90)

            let preview = try XCTUnwrap(store.rotationPreviewPlan)
            let previewDoor = try XCTUnwrap(preview.openings.first { $0.id == door.id })
            XCTAssertEqual(previewDoor.doorSwingDegrees, 180, accuracy: 0.000_001)
            XCTAssertEqual(previewDoor.hingeAtEnd, door.hingeAtEnd)
            XCTAssertEqual(preview.walls, store.plan.walls)
            XCTAssertEqual(previewDoor.wallID, door.wallID)
            XCTAssertEqual(previewDoor.offset, door.offset)
            XCTAssertEqual(previewDoor.width, door.width)
            XCTAssertEqual(previewDoor.height, door.height)
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.canUndo)

            store.commitRotation()

            XCTAssertEqual(store.plan, preview)
            XCTAssertEqual(store.selectedOpeningID, door.id)
            XCTAssertEqual(store.undoStack.count, 1)
            store.undo()
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.isDirty)
        }
    }

    func testDoorOrientationControlsAndRotationCancelPreserveTheOpeningPosition() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let door = try XCTUnwrap(store.plan.openings.first { $0.kind == .door })
            let originalWalls = store.plan.walls
            store.selectOpening(door.id)
            store.updateDoor(id: door.id, swingDegrees: -90, hingeAtEnd: true)
            let orientedDoor = try XCTUnwrap(store.selectedOpening)
            XCTAssertEqual(orientedDoor.doorSwingDegrees, -90)
            XCTAssertTrue(orientedDoor.hingeAtEnd)
            XCTAssertEqual(orientedDoor.offset, door.offset)
            XCTAssertEqual(orientedDoor.wallID, door.wallID)
            XCTAssertEqual(store.plan.walls, originalWalls)
            let beforePreview = store.document
            let historyCount = store.undoStack.count

            store.beginRotation()
            store.previewRotation(45)
            XCTAssertNotNil(store.rotationPreviewPlan)
            store.cancelRotation()

            XCTAssertEqual(store.document, beforePreview)
            XCTAssertEqual(store.undoStack.count, historyCount)
            XCTAssertNil(store.rotationPreviewPlan)
        }
    }

    func testMeasurementsCanBeSelectedEditedSavedPerFloorAndDeletedWithUndo() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let firstFloorID = store.activeLayer.id
            let start = PlanPoint(x: 76.2, y: 1000)
            let end = PlanPoint(x: 6019.8, y: 1000)
            store.chooseTool(.measure)
            store.commitDimension(from: start, to: end)
            let dimension = try XCTUnwrap(store.selectedDimension)
            XCTAssertEqual(dimension.start, start)
            XCTAssertEqual(dimension.end, end)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertEqual(store.undoStack.count, 1)
            XCTAssertTrue(store.isDirty)
            store.selectWall(store.plan.walls[0].id)
            XCTAssertNil(store.selectedDimensionID)
            let beforeSelection = store.document
            store.selectDimension(dimension.id)
            XCTAssertEqual(store.selectedDimensionID, dimension.id)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertEqual(store.document, beforeSelection, "Selecting a measurement is not a document edit")

            let changedEnd = PlanPoint(x: 6019.8, y: 1500)
            store.updateDimension(id: dimension.id, start: start, end: changedEnd)
            let updated = try XCTUnwrap(store.selectedDimension)
            XCTAssertEqual(updated.end, changedEnd)
            XCTAssertEqual(store.undoStack.count, 2)
            let encoded = try JSONEncoder().encode(store.document)
            let loaded = try JSONDecoder().decode(PlanDocument.self, from: encoded)
            XCTAssertEqual(loaded, store.document)

            store.addLayer()
            XCTAssertTrue(store.plan.dimensions.isEmpty)
            store.commitDimension(from: .init(x: 0, y: 0), to: .init(x: 1000, y: 0))
            let secondFloorID = store.activeLayer.id
            let secondDimension = try XCTUnwrap(store.selectedDimension)
            XCTAssertNotEqual(secondDimension.id, dimension.id)
            XCTAssertEqual(store.document.layers.first { $0.id == firstFloorID }?.plan.dimensions, [updated])

            store.selectLayer(id: firstFloorID)
            XCTAssertNil(store.selectedDimensionID)
            store.selectDimension(dimension.id)
            store.deleteSelection()

            XCTAssertTrue(store.plan.dimensions.isEmpty)
            XCTAssertNil(store.selectedDimensionID)
            XCTAssertEqual(store.document.layers.first { $0.id == secondFloorID }?.plan.dimensions, [secondDimension])
            store.undo()
            XCTAssertEqual(store.plan.dimensions, [updated])
            XCTAssertEqual(store.document.layers.first { $0.id == secondFloorID }?.plan.dimensions, [secondDimension])
        }
    }

    func testLockedAndHiddenFloorsRejectNewMeasurementsMeasurementEditsAndDoorOrientation() async throws {
        try await MainActor.run {
            for locked in [true, false] {
                let store = directEditingStore()
                store.commitDimension(from: .init(x: 100, y: 100), to: .init(x: 2000, y: 100))
                let dimension = try XCTUnwrap(store.selectedDimension)
                let door = try XCTUnwrap(store.plan.openings.first { $0.kind == .door })
                if locked { store.setLayerLocked(id: store.activeLayer.id, locked: true) }
                else { store.setLayerVisible(id: store.activeLayer.id, visible: false) }
                let protected = store.document
                let undoHistory = store.undoStack
                let redoHistory = store.redoStack

                store.commitDimension(from: .init(x: 0, y: 1000), to: .init(x: 2000, y: 1000))
                store.updateDimension(id: dimension.id, start: dimension.start, end: .init(x: 3000, y: 100))
                store.updateDoor(id: door.id, swingDegrees: -90, hingeAtEnd: !door.hingeAtEnd)
                store.selectDimension(dimension.id)
                store.deleteSelection()
                store.selectOpening(door.id)
                store.beginSelectionDrag()
                store.previewSelectionDrag(by: .init(x: 100, y: 0))
                store.commitSelectionDrag()

                XCTAssertEqual(store.document, protected)
                XCTAssertEqual(store.undoStack, undoHistory)
                XCTAssertEqual(store.redoStack, redoHistory)
                XCTAssertNil(store.selectedDimensionID)
                XCTAssertTrue(store.selection.isEmpty)
                XCTAssertFalse(store.dragPreviewActive)
                XCTAssertFalse(store.canRotateSelection)
            }
        }
    }

    func testInvalidMeasurementEditsPreserveDocumentHistoryAndSelectedMeasurement() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            store.commitDimension(from: .init(x: 100, y: 100), to: .init(x: 2000, y: 100))
            let dimension = try XCTUnwrap(store.selectedDimension)
            let before = store.document
            let history = store.undoStack

            store.commitDimension(from: .init(x: 0, y: 0), to: .init(x: 0, y: 0))
            store.updateDimension(id: dimension.id, start: dimension.start, end: dimension.start)

            XCTAssertEqual(store.document, before)
            XCTAssertEqual(store.undoStack, history)
            XCTAssertEqual(store.selectedDimensionID, dimension.id)
        }
    }

    func testAreaCanBeRenamedSavedPerFloorDeletedAndRestoredWithUndo() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let firstFloorID = store.activeLayer.id
            let vertices = [PlanPoint(x: 100, y: 100), .init(x: 2100, y: 100),
                            .init(x: 2100, y: 3100), .init(x: 100, y: 3100)]
            store.chooseTool(.area)
            store.commitArea(vertices: vertices)
            let area = try XCTUnwrap(store.selectedArea)
            XCTAssertEqual(store.selectedAreaID, area.id)
            XCTAssertEqual(area.areaSquareMillimetres, 6_000_000, accuracy: 0.000_001)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertNil(store.selectedDimensionID)
            XCTAssertTrue(store.isDirty)
            XCTAssertEqual(store.undoStack.count, 1)

            let editedVertices = [PlanPoint(x: 100, y: 100), .init(x: 2600, y: 100),
                                  .init(x: 2600, y: 3100), .init(x: 100, y: 3100)]
            store.updateArea(id: area.id, name: "Kitchen", vertices: editedVertices)
            let updated = try XCTUnwrap(store.selectedArea)
            XCTAssertEqual(updated.name, "Kitchen")
            XCTAssertEqual(updated.vertices, editedVertices)
            XCTAssertEqual(updated.areaSquareMillimetres, 7_500_000, accuracy: 0.000_001)
            XCTAssertEqual(store.undoStack.count, 2)
            let decoded = try JSONDecoder().decode(PlanDocument.self, from: JSONEncoder().encode(store.document))
            XCTAssertEqual(decoded, store.document)

            store.addLayer()
            XCTAssertTrue(store.plan.areas.isEmpty)
            store.commitArea(vertices: [.init(x: 0, y: 0), .init(x: 1000, y: 0), .init(x: 0, y: 1000)])
            let secondFloorID = store.activeLayer.id
            let secondArea = try XCTUnwrap(store.selectedArea)
            XCTAssertNotEqual(secondArea.id, area.id)
            XCTAssertEqual(store.document.layers.first { $0.id == firstFloorID }?.plan.areas, [updated])

            store.selectLayer(id: firstFloorID)
            XCTAssertNil(store.selectedAreaID)
            store.selectArea(area.id)
            store.deleteSelection()
            XCTAssertTrue(store.plan.areas.isEmpty)
            XCTAssertNil(store.selectedAreaID)
            XCTAssertEqual(store.document.layers.first { $0.id == secondFloorID }?.plan.areas, [secondArea])

            store.undo()
            XCTAssertEqual(store.plan.areas, [updated])
            XCTAssertEqual(store.document.layers.first { $0.id == secondFloorID }?.plan.areas, [secondArea])
        }
    }

    func testAreaWallAndMeasurementSelectionsAreMutuallyExclusiveWithoutEditingTheDocument() async throws {
        try await MainActor.run {
            let store = directEditingStore()
            let wall = try XCTUnwrap(store.plan.walls.first)
            store.commitDimension(from: .init(x: 100, y: 100), to: .init(x: 2100, y: 100))
            let dimension = try XCTUnwrap(store.selectedDimension)
            store.commitArea(vertices: [.init(x: 100, y: 100), .init(x: 2100, y: 100), .init(x: 100, y: 2100)])
            let area = try XCTUnwrap(store.selectedArea)
            XCTAssertNil(store.selectedDimensionID)
            XCTAssertTrue(store.selection.isEmpty)
            let beforeSelection = store.document
            let history = store.undoStack

            store.selectWall(wall.id)
            XCTAssertEqual(store.selectedWallID, wall.id)
            XCTAssertNil(store.selectedAreaID)
            XCTAssertNil(store.selectedDimensionID)
            store.selectArea(area.id)
            XCTAssertEqual(store.selectedAreaID, area.id)
            XCTAssertTrue(store.selection.isEmpty)
            XCTAssertNil(store.selectedDimensionID)
            store.selectDimension(dimension.id)
            XCTAssertEqual(store.selectedDimensionID, dimension.id)
            XCTAssertNil(store.selectedAreaID)
            XCTAssertTrue(store.selection.isEmpty)
            store.selectArea(area.id)
            XCTAssertEqual(store.selectedAreaID, area.id)
            XCTAssertNil(store.selectedDimensionID)

            XCTAssertEqual(store.document, beforeSelection)
            XCTAssertEqual(store.undoStack, history)
        }
    }

    func testLockedAndHiddenFloorsRejectAreaCreationAndChangesWithoutHistoryMutation() async throws {
        try await MainActor.run {
            for locked in [true, false] {
                let store = directEditingStore()
                let vertices = [PlanPoint(x: 100, y: 100), .init(x: 2100, y: 100), .init(x: 100, y: 2100)]
                store.commitArea(vertices: vertices)
                let area = try XCTUnwrap(store.selectedArea)
                if locked { store.setLayerLocked(id: store.activeLayer.id, locked: true) }
                else { store.setLayerVisible(id: store.activeLayer.id, visible: false) }
                let protected = store.document
                let undoHistory = store.undoStack
                let redoHistory = store.redoStack

                store.commitArea(vertices: [.init(x: 0, y: 0), .init(x: 3000, y: 0), .init(x: 0, y: 3000)])
                store.updateArea(id: area.id, name: "Changed area", vertices: area.vertices)
                store.selectArea(area.id)
                store.deleteSelection()

                XCTAssertEqual(store.document, protected)
                XCTAssertEqual(store.undoStack, undoHistory)
                XCTAssertEqual(store.redoStack, redoHistory)
                XCTAssertNil(store.selectedAreaID)
                XCTAssertNil(store.selectedDimensionID)
                XCTAssertTrue(store.selection.isEmpty)
            }
        }
    }
}

@MainActor
private func directEditingStore() -> PlanStore {
    PlanStore(pasteboard: NSPasteboard(name: NSPasteboard.Name("QuickPlan.DirectEditingTests.\(UUID().uuidString)")))
}
#endif
