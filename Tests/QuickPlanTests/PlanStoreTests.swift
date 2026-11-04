#if os(macOS)
import XCTest
import BlueprintCore
@testable import QuickPlan

final class PlanStoreTests: XCTestCase {
    func testInitialPlanIsCleanAndUndoRestoresDirtyState() async {
        await MainActor.run {
            let store = PlanStore()
            XCTAssertFalse(store.isDirty, "The saved snapshot must share the sample plan’s object IDs")
            let before = store.plan
            store.commitWall(from: .init(x: 8000, y: 0), to: .init(x: 9000, y: 0))
            XCTAssertTrue(store.isDirty)
            XCTAssertTrue(store.canUndo)
            store.undo()
            XCTAssertEqual(store.plan, before)
            XCTAssertFalse(store.isDirty)
            XCTAssertTrue(store.canRedo)
            store.redo()
            XCTAssertEqual(store.plan.walls.count, before.walls.count + 1)
            XCTAssertTrue(store.isDirty)
        }
    }

    func testInvalidEditDoesNotCreateUndoEntryOrChangePlan() async {
        await MainActor.run {
            let store = PlanStore()
            let before = store.plan
            store.setDefaultThickness(-100)
            XCTAssertEqual(store.plan, before)
            XCTAssertFalse(store.canUndo)
            XCTAssertFalse(store.isDirty)
        }
    }

    func testDeletingWallAndUndoRestoreAttachedOpening() async throws {
        try await MainActor.run {
            let store = PlanStore()
            let opening = try XCTUnwrap(store.plan.openings.first)
            let before = store.plan
            store.selectWall(opening.wallID)
            store.deleteSelection()
            XCTAssertFalse(store.plan.openings.contains { $0.id == opening.id })
            XCTAssertNil(store.selectedWallID)
            store.undo()
            XCTAssertEqual(store.plan, before)
        }
    }

    func testNewEditClearsRedoHistory() async {
        await MainActor.run {
            let store = PlanStore()
            store.setDefaultThickness(200)
            store.undo()
            XCTAssertTrue(store.canRedo)
            store.setDefaultThickness(100)
            XCTAssertFalse(store.canRedo)
        }
    }
}
#endif
