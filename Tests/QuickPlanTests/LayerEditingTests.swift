#if os(macOS)
import AppKit
import XCTest
import BlueprintCore
@testable import QuickPlan

final class LayerEditingTests: XCTestCase {
    func testLockedAndHiddenFloorsRejectGeometryEditsWithoutHistoryChanges() async throws {
        try await MainActor.run {
            for locked in [true, false] {
                let pasteboard = NSPasteboard(name: .init("QuickPlan-layer-tests-\(UUID())"))
                defer { pasteboard.clearContents() }
                let store = PlanStore(pasteboard: pasteboard)
                let wall = try XCTUnwrap(store.plan.walls.first)
                let opening = try XCTUnwrap(store.plan.openings.first)
                let copied = try store.plan.copySelection(PlanSelection(wallIDs: [wall.id]))
                pasteboard.setData(try JSONEncoder().encode(copied), forType: PlanStore.selectionPasteboardType)
                if locked { store.setLayerLocked(id: store.activeLayer.id, locked: true) }
                else { store.setLayerVisible(id: store.activeLayer.id, visible: false) }

                let protected = store.document
                let history = store.undoStack
                let redo = store.redoStack
                XCTAssertFalse(store.canEditActiveLayer)
                store.commitWall(from: .init(x: 8000, y: 0), to: .init(x: 10000, y: 0))
                store.updateWall(id: wall.id, start: wall.start, end: .init(x: wall.end.x + 100, y: wall.end.y), thickness: 250)
                store.updateOpening(id: opening.id, offset: opening.offset, width: opening.width + 10, height: opening.height)
                store.setDefaultThickness(250)
                store.pasteSelection()
                store.pasteInPlace()
                store.selectWall(wall.id)
                store.deleteSelection()
                let changed = store.change("Attempt to bypass floor protection") { $0.walls.removeAll(); $0.openings.removeAll() }

                XCTAssertFalse(changed)
                XCTAssertEqual(store.document, protected)
                XCTAssertEqual(store.undoStack, history)
                XCTAssertEqual(store.redoStack, redo)
                XCTAssertTrue(store.selection.isEmpty)
                XCTAssertFalse(store.canPasteSelection)
            }
        }
    }

    func testSelectingFloorsDoesNotDirtyCleanDocumentOrCreateUndoEntry() async throws {
        try await MainActor.run {
            var document = PlanDocument.example
            let first = document.activeLayerID
            let second = try document.addLayer()
            try document.setActiveLayer(id: first)
            let store = try Self.loadCleanDocument(document)

            store.selectLayer(id: second)
            XCTAssertEqual(store.activeLayer.id, second)
            XCTAssertFalse(store.isDirty)
            XCTAssertTrue(store.undoStack.isEmpty)
            XCTAssertTrue(store.redoStack.isEmpty)
            store.selectLayer(id: first)
            XCTAssertEqual(store.document.layers, document.layers)
            XCTAssertFalse(store.isDirty)
            XCTAssertFalse(store.canUndo)
        }
    }

    func testOpacityGestureCreatesOneUndoEntryAndRestoresWholeGesture() async {
        await MainActor.run {
            let store = PlanStore()
            let original = store.document
            let id = store.activeLayer.id

            store.beginLayerOpacityEdit()
            store.setLayerOpacity(id: id, opacity: 0.8)
            store.setLayerOpacity(id: id, opacity: 0.4)
            store.setLayerOpacity(id: id, opacity: 0.2)
            XCTAssertTrue(store.canUndo)
            XCTAssertTrue(store.undoStack.isEmpty, "Intermediate slider positions must not fill the undo history")
            store.endLayerOpacityEdit()
            XCTAssertEqual(store.undoStack.count, 1)
            XCTAssertEqual(store.activeLayer.opacity, 0.2, accuracy: 0.000_001)

            store.undo()
            XCTAssertEqual(store.document, original)
            XCTAssertFalse(store.isDirty)
            store.redo()
            XCTAssertEqual(store.activeLayer.opacity, 0.2, accuracy: 0.000_001)
        }
    }

    func testLockingOrHidingActiveFloorClearsSelectionAndRotationPreview() async throws {
        try await MainActor.run {
            for locked in [true, false] {
                let store = PlanStore()
                let wall = try XCTUnwrap(store.plan.walls.first)
                store.selectWall(wall.id)
                store.beginRotation()
                store.previewRotation(45)
                XCTAssertFalse(store.selection.isEmpty)
                XCTAssertTrue(store.rotationPreviewActive)
                XCTAssertNotNil(store.rotationPreviewPlan)

                if locked { store.setLayerLocked(id: store.activeLayer.id, locked: true) }
                else { store.setLayerVisible(id: store.activeLayer.id, visible: false) }

                XCTAssertTrue(store.selection.isEmpty)
                XCTAssertFalse(store.rotationPreviewActive)
                XCTAssertNil(store.rotationPreviewPlan)
                XCTAssertNil(store.rotationPivot)
                XCTAssertNil(store.rotationGuideDegrees)
            }
        }
    }

    func testRejectedLastFloorDeletionPreservesDrawingAndSelection() async throws {
        try await MainActor.run {
            let store = PlanStore()
            let wall = try XCTUnwrap(store.plan.walls.first)
            store.selectWall(wall.id)
            let original = store.document
            let selection = store.selection

            store.removeLayer(id: store.activeLayer.id)

            XCTAssertEqual(store.document, original)
            XCTAssertEqual(store.selection, selection)
            XCTAssertFalse(store.canUndo)
            XCTAssertFalse(store.isDirty)
        }
    }

    @MainActor
    private static func loadCleanDocument(_ document: PlanDocument) throws -> PlanStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickPlan-layer-tests-\(UUID()).quickplan")
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PlanStore(pasteboard: NSPasteboard(name: .init("QuickPlan-layer-tests-\(UUID())")))
        store.open(url: url)
        return store
    }
}
#endif
