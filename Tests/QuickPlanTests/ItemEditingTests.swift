#if os(macOS)
import AppKit
import XCTest
import BlueprintCore
@testable import QuickPlan

final class ItemEditingTests: XCTestCase {
    func testPresetStampUsesMeasuredFootprintAndIsOneUndoableEdit() async throws {
        try await MainActor.run {
            let store = itemEditingStore()
            let preset = try XCTUnwrap(ObjectCatalog.presets(for: .bedroom).first)
            let original = store.document

            store.choosePreset(preset)
            XCTAssertEqual(store.tool, .object)
            XCTAssertEqual(store.selectedPreset, preset)
            XCTAssertEqual(store.itemWidth, preset.width)
            XCTAssertEqual(store.itemDepth, preset.depth)
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.canUndo)

            let centre = PlanPoint(x: 2500, y: 1800)
            store.placeItem(at: centre)

            let item = try XCTUnwrap(store.selectedItem)
            XCTAssertEqual(item.kind, preset.kind)
            XCTAssertEqual(item.name, preset.name)
            XCTAssertEqual(item.position, centre)
            XCTAssertEqual(item.width, preset.width)
            XCTAssertEqual(item.depth, preset.depth)
            XCTAssertEqual(store.plan.dimensions, original.activeLayer.plan.dimensions,
                           "Placement previews must not create persistent measurement annotations")
            XCTAssertEqual(store.plan.walls, original.activeLayer.plan.walls)
            XCTAssertEqual(store.undoStack.count, 1)
            let placed = store.document

            store.undo()
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.isDirty)
            store.redo()
            XCTAssertEqual(store.document, placed)
        }
    }

    func testInvalidShapeAndResizeLeaveDocumentSelectionAndRedoIntact() async throws {
        try await MainActor.run {
            let store = itemEditingStore()
            store.commitShape(kind: .circle, position: .init(x: 1000, y: 1500), width: 800, depth: 800)
            let circle = try XCTUnwrap(store.selectedItem)
            store.commitShape(kind: .ellipse, position: .init(x: 2000, y: 1500), width: 900, depth: 600)
            store.undo()
            store.selectItem(circle.id)
            let original = store.document
            let originalUndo = store.undoStack
            let originalRedo = store.redoStack
            let originalSelection = store.selection
            XCTAssertFalse(originalRedo.isEmpty)

            store.commitShape(kind: .rectangle, position: .init(x: 500, y: 500), width: 0, depth: 400)
            store.commitShape(kind: .circle, position: .init(x: 500, y: 500), width: 800, depth: 500)
            store.commitShape(kind: .triangle, position: .init(x: .nan, y: 500), width: 800, depth: 500)
            store.updateItem(id: circle.id, name: circle.name, position: circle.position,
                             width: 1200, depth: 800, rotationDegrees: 0)
            store.updateItem(id: circle.id, name: circle.name, position: circle.position,
                             width: 800, depth: 800, rotationDegrees: .infinity)

            XCTAssertEqual(store.document, original)
            XCTAssertEqual(store.undoStack, originalUndo)
            XCTAssertEqual(store.redoStack, originalRedo)
            XCTAssertEqual(store.selection, originalSelection)
            XCTAssertEqual(store.selectedItem, circle)

            store.updateItem(id: circle.id, name: "Round table", position: circle.position,
                             width: 1200, depth: 1200, rotationDegrees: 15)
            let resized = try XCTUnwrap(store.selectedItem)
            XCTAssertEqual(resized.name, "Round table")
            XCTAssertEqual(resized.width, 1200)
            XCTAssertEqual(resized.depth, resized.width)
            XCTAssertEqual(store.undoStack.count, originalUndo.count + 1)
            store.undo()
            XCTAssertEqual(store.document, original)
        }
    }

    func testObjectDragAndClipboardCopiesPreserveIndependentGeometry() async throws {
        try await MainActor.run {
            let store = itemEditingStore()
            let preset = try XCTUnwrap(ObjectCatalog.presets(for: .office).first)
            store.choosePreset(preset)
            store.itemWidth = 1600
            store.itemDepth = 750
            store.placeItem(at: .init(x: 1000, y: 2000))
            let source = try XCTUnwrap(store.selectedItem)
            let beforeDrag = store.document
            let undoCount = store.undoStack.count

            store.beginSelectionDrag()
            store.previewSelectionDrag(by: .init(x: 500, y: 250))
            XCTAssertEqual(store.document, beforeDrag)
            let preview = try XCTUnwrap(store.dragPreviewPlan?.items.first { $0.id == source.id })
            XCTAssertEqual(preview.position, PlanPoint(x: 1500, y: 2250))
            store.commitSelectionDrag()
            let moved = try XCTUnwrap(store.selectedItem)
            XCTAssertEqual(moved.position, preview.position)
            XCTAssertEqual(store.undoStack.count, undoCount + 1)

            store.copySelection()
            XCTAssertEqual(store.undoStack.count, undoCount + 1)
            store.pasteSelection()
            let copy = try XCTUnwrap(store.selectedItem)
            XCTAssertNotEqual(copy.id, source.id)
            XCTAssertEqual(copy.position.x, moved.position.x + 304.8, accuracy: 0.000_001)
            XCTAssertEqual(copy.position.y, moved.position.y + 304.8, accuracy: 0.000_001)
            XCTAssertEqual(copy.name, moved.name)
            XCTAssertEqual(copy.width, 1600)
            XCTAssertEqual(copy.depth, 750)

            store.updateItem(id: copy.id, name: "Second desk", position: copy.position,
                             width: 1400, depth: 700, rotationDegrees: 30)
            XCTAssertEqual(store.plan.items.first { $0.id == source.id }, moved)
            store.undo()
            XCTAssertEqual(store.plan.items.first { $0.id == copy.id }, copy)

            store.addLayer()
            store.pasteInPlace()
            let otherFloorCopy = try XCTUnwrap(store.selectedItem)
            XCTAssertNotEqual(otherFloorCopy.id, source.id)
            XCTAssertNotEqual(otherFloorCopy.id, copy.id)
            XCTAssertEqual(otherFloorCopy.position, moved.position)
            XCTAssertEqual(otherFloorCopy.width, moved.width)
            XCTAssertEqual(otherFloorCopy.depth, moved.depth)
        }
    }

    func testObjectOnlyRotationPreviewsCancelsAndCommitsAsOneEdit() async throws {
        try await MainActor.run {
            let store = itemEditingStore()
            store.smartGuides = false
            store.commitShape(kind: .rectangle, position: .init(x: 0, y: 0), width: 400, depth: 200)
            let firstID = try XCTUnwrap(store.selectedItemID)
            store.commitShape(kind: .triangle, position: .init(x: 2000, y: 0), width: 400, depth: 200)
            let secondID = try XCTUnwrap(store.selectedItemID)
            store.selectItem(firstID)
            store.selectItem(secondID, extending: true)
            XCTAssertTrue(store.canRotateSelection)
            XCTAssertNil(store.selectedItemID, "A multi-object selection must not expose a single-item inspector")
            let original = store.document
            let undoCount = store.undoStack.count

            store.beginRotation()
            store.previewRotation(90)
            XCTAssertEqual(store.document, original)
            let firstPreview = try XCTUnwrap(store.rotationPreviewPlan?.items.first { $0.id == firstID })
            let secondPreview = try XCTUnwrap(store.rotationPreviewPlan?.items.first { $0.id == secondID })
            XCTAssertEqual(firstPreview.position.x, 1000, accuracy: 0.000_001)
            XCTAssertEqual(firstPreview.position.y, -1000, accuracy: 0.000_001)
            XCTAssertEqual(secondPreview.position.x, 1000, accuracy: 0.000_001)
            XCTAssertEqual(secondPreview.position.y, 1000, accuracy: 0.000_001)
            XCTAssertEqual(firstPreview.rotationDegrees, 90, accuracy: 0.000_001)
            store.cancelRotation()
            XCTAssertEqual(store.document, original)
            XCTAssertEqual(store.undoStack.count, undoCount)

            store.beginRotation()
            store.previewRotation(90)
            store.commitRotation()
            XCTAssertEqual(store.plan.items.first { $0.id == firstID }, firstPreview)
            XCTAssertEqual(store.plan.items.first { $0.id == secondID }, secondPreview)
            XCTAssertEqual(store.undoStack.count, undoCount + 1)
            store.undo()
            XCTAssertEqual(store.document, original)
        }
    }

    func testLockedAndHiddenFloorsRejectAllObjectContentEdits() async throws {
        try await MainActor.run {
            for hideInsteadOfLock in [false, true] {
                let store = itemEditingStore()
                let preset = try XCTUnwrap(ObjectCatalog.presets(for: .kitchen).first)
                store.choosePreset(preset)
                store.placeItem(at: .init(x: 1200, y: 1800))
                let item = try XCTUnwrap(store.selectedItem)
                store.copySelection()
                if hideInsteadOfLock {
                    store.setLayerVisible(id: store.activeLayer.id, visible: false)
                } else {
                    store.setLayerLocked(id: store.activeLayer.id, locked: true)
                }
                let original = store.document
                let originalUndo = store.undoStack
                let originalRedo = store.redoStack
                let originalSelection = store.selection

                store.placeItem(at: .init(x: 2200, y: 1800))
                store.commitShape(kind: .rectangle, position: .init(x: 2000, y: 2000), width: 800, depth: 600)
                store.updateItem(id: item.id, name: "Changed", position: .init(x: 0, y: 0),
                                 width: 1000, depth: 500, rotationDegrees: 45)
                store.selectItem(item.id)
                store.beginSelectionDrag()
                store.previewSelectionDrag(by: .init(x: 500, y: 250))
                store.commitSelectionDrag()
                store.beginRotation()
                store.previewRotation(90)
                store.commitRotation()
                store.pasteSelection()
                store.deleteSelection()

                XCTAssertEqual(store.document, original)
                XCTAssertEqual(store.undoStack, originalUndo)
                XCTAssertEqual(store.redoStack, originalRedo)
                XCTAssertEqual(store.selection, originalSelection)
                XCTAssertNil(store.dragPreviewPlan)
                XCTAssertNil(store.rotationPreviewPlan)
            }
        }
    }

    func testSavingMultipleFloorsPreservesCustomObjectsAndShapes() async throws {
        try await MainActor.run {
            let store = itemEditingStore()
            let preset = try XCTUnwrap(ObjectCatalog.presets(for: .livingRoom).first)
            store.choosePreset(preset)
            store.placeItem(at: .init(x: 3200, y: 2400))
            let sofa = try XCTUnwrap(store.selectedItem)
            store.updateItem(id: sofa.id, name: "Reading sofa", position: sofa.position,
                             width: 2200, depth: 950, rotationDegrees: -30)
            let firstFloorID = store.activeLayer.id
            let firstFloor = store.plan
            store.addLayer()
            let stair = try XCTUnwrap(ObjectCatalog.presets(for: .staircase).first)
            store.choosePreset(stair)
            store.placeItem(at: .init(x: 1500, y: 1500))
            store.commitShape(kind: .circle, position: .init(x: 4000, y: 3000), width: 1200, depth: 1200)
            store.commitShape(kind: .line, position: .init(x: 3000, y: 1200), width: 1800, depth: 1, rotationDegrees: 60)

            let data = try JSONEncoder().encode(store.document)
            let reopened = try JSONDecoder().decode(PlanDocument.self, from: data)
            try reopened.validate()
            XCTAssertEqual(reopened, store.document)
            XCTAssertEqual(reopened.layers.first { $0.id == firstFloorID }?.plan, firstFloor)
            XCTAssertEqual(reopened.activeLayer.plan.items.count, 3)
            XCTAssertEqual(reopened.activeLayer.plan.items.map(\.kind), [stair.kind, .circle, .line])
            XCTAssertEqual(reopened.activeLayerID, store.activeLayer.id)
        }
    }
}

@MainActor
private func itemEditingStore() -> PlanStore {
    PlanStore(pasteboard: NSPasteboard(name: .init("QuickPlan.item-editing.\(UUID().uuidString)")))
}
#endif
