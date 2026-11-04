import Foundation
import XCTest
@testable import BlueprintCore

final class PlanDocumentTests: XCTestCase {
    func testIdenticalCoordinatesOnOtherFloorsRemainIndependent() throws {
        let plan = FloorPlan.example
        let lower = FloorLayer(name: "Ground floor", plan: plan)
        let upper = FloorLayer(name: "Upper floor", plan: plan)
        var document = PlanDocument(layers: [lower, upper], activeLayerID: upper.id)
        let wall = try XCTUnwrap(plan.walls.first)
        let moved = PlanPoint(x: wall.end.x + 500, y: wall.end.y)
        try document.editActivePlan {
            try $0.updateWall(id: wall.id, start: wall.start, end: moved, thickness: wall.thickness)
        }
        XCTAssertEqual(document.layers[0].plan, lower.plan)
        XCTAssertEqual(document.layers[1].plan.walls[0].end, moved)
        XCTAssertNotEqual(document.layers[1].plan, plan)
    }

    func testLockedAndHiddenFloorsRejectContentEditsBeforeInvokingClosure() throws {
        var document = PlanDocument.example
        let id = document.activeLayerID
        try document.setLayerLocked(id: id, locked: true)
        let locked = document
        var editCalled = false
        XCTAssertThrowsError(try document.editActivePlan { _ in editCalled = true }) {
            XCTAssertEqual($0 as? PlanDocumentError, .lockedLayer)
        }
        XCTAssertFalse(editCalled)
        XCTAssertEqual(document, locked)
        try document.setLayerLocked(id: id, locked: false)
        try document.setLayerVisible(id: id, visible: false)
        let hidden = document
        XCTAssertThrowsError(try document.editActivePlan { _ in editCalled = true }) {
            XCTAssertEqual($0 as? PlanDocumentError, .hiddenLayer)
        }
        XCTAssertFalse(editCalled)
        XCTAssertEqual(document, hidden)
    }

    func testInvalidContentEditIsAtomic() throws {
        var document = PlanDocument.example
        let before = document
        XCTAssertThrowsError(try document.editActivePlan { $0.walls[0].thickness = -1 })
        XCTAssertEqual(document, before)
    }

    func testOldSingleFloorDocumentMigratesWithoutChangingGeometryIDs() throws {
        let plan = FloorPlan.example
        let oldData = try JSONEncoder().encode(plan)
        let migrated = try JSONDecoder().decode(PlanDocument.self, from: oldData)
        XCTAssertEqual(migrated.layers.count, 1)
        XCTAssertEqual(migrated.activeLayer.name, "Floor 1")
        XCTAssertEqual(migrated.activeLayer.plan, plan)
        let saved = try JSONEncoder().encode(migrated)
        let roundTrip = try JSONDecoder().decode(PlanDocument.self, from: saved)
        XCTAssertEqual(roundTrip, migrated)
    }

    func testMultiFloorSaveRoundTripPreservesOrderActiveFloorAndDisplayProperties() throws {
        var document = PlanDocument.example
        let first = document.activeLayerID
        let second = try document.addLayer(name: "Second floor")
        try document.setLayerOpacity(id: first, opacity: 0.25)
        try document.setLayerLocked(id: first, locked: true)
        try document.setLayerVisible(id: second, visible: false)
        try document.moveLayer(id: second, to: 0)
        let data = try JSONEncoder().encode(document)
        let restored = try JSONDecoder().decode(PlanDocument.self, from: data)
        XCTAssertEqual(restored, document)
        XCTAssertEqual(restored.layers.map(\.id), [second, first])
        XCTAssertEqual(restored.activeLayerID, second)
        XCTAssertEqual(restored.layers[1].opacity, 0.25)
        XCTAssertTrue(restored.layers[1].isLocked)
        XCTAssertFalse(restored.layers[0].isVisible)
    }

    func testLayerMetadataValidationDoesNotPartiallyApplyChanges() throws {
        var document = PlanDocument.example
        let id = document.activeLayerID
        let before = document
        for opacity in [-0.01, 1.01, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try document.setLayerOpacity(id: id, opacity: opacity)) {
                XCTAssertEqual($0 as? PlanDocumentError, .invalidOpacity)
            }
            XCTAssertEqual(document, before)
        }
        for name in [" \n\t", String(repeating: "a", count: 101)] {
            XCTAssertThrowsError(try document.renameLayer(id: id, name: name)) {
                XCTAssertEqual($0 as? PlanDocumentError, .invalidLayerName)
            }
            XCTAssertEqual(document, before)
        }
        try document.renameLayer(id: id, name: "  Main floor  ")
        XCTAssertEqual(document.activeLayer.name, "Main floor")
    }

    func testAddingFloorInheritsThicknessAndSelectsBlankFloor() throws {
        var document = PlanDocument.example
        let first = document.activeLayerID
        let second = try document.addLayer()
        XCTAssertEqual(document.activeLayerID, second)
        XCTAssertEqual(document.layers.map(\.name), ["Floor 1", "Floor 2"])
        XCTAssertTrue(document.activeLayer.plan.walls.isEmpty)
        XCTAssertTrue(document.activeLayer.plan.openings.isEmpty)
        XCTAssertEqual(document.activeLayer.plan.defaultWallThickness, 152.4)
        XCTAssertEqual(document.layers[0].id, first)
    }

    func testDuplicateCreatesIndependentObjectsAndRemapsAttachedOpenings() throws {
        var document = PlanDocument.example
        let original = document.activeLayer
        try document.setLayerLocked(id: original.id, locked: true)
        try document.setLayerOpacity(id: original.id, opacity: 0.4)
        let duplicateID = try document.duplicateLayer(id: original.id)
        let copy = document.activeLayer
        XCTAssertEqual(copy.id, duplicateID)
        XCTAssertEqual(copy.name, "Floor 1 copy")
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertFalse(copy.isLocked)
        XCTAssertTrue(copy.isVisible)
        XCTAssertEqual(copy.opacity, 0.4)
        XCTAssertEqual(copy.plan.walls.map(\.start), original.plan.walls.map(\.start))
        XCTAssertEqual(copy.plan.walls.map(\.end), original.plan.walls.map(\.end))
        XCTAssertTrue(Set(copy.plan.walls.map(\.id)).isDisjoint(with: Set(original.plan.walls.map(\.id))))
        XCTAssertTrue(Set(copy.plan.openings.map(\.id)).isDisjoint(with: Set(original.plan.openings.map(\.id))))
        for (source, duplicated) in zip(original.plan.openings, copy.plan.openings) {
            let originalWallIndex = try XCTUnwrap(original.plan.walls.firstIndex { $0.id == source.wallID })
            XCTAssertEqual(duplicated.wallID, copy.plan.walls[originalWallIndex].id)
            XCTAssertEqual(duplicated.width, source.width)
            XCTAssertEqual(duplicated.offset, source.offset)
        }
        try document.validate()
    }

    func testCannotDeleteLastFloorAndActiveDeletionSelectsSurvivingFloor() throws {
        var document = PlanDocument.empty
        let first = document.activeLayerID
        let before = document
        XCTAssertThrowsError(try document.removeLayer(id: first)) {
            XCTAssertEqual($0 as? PlanDocumentError, .lastLayer)
        }
        XCTAssertEqual(document, before)
        let second = try document.addLayer()
        try document.removeLayer(id: second)
        XCTAssertEqual(document.activeLayerID, first)
        try document.validate()
    }

    func testReorderingChangesStackWithoutChangingActiveFloorOrContents() throws {
        var document = PlanDocument.example
        let first = document.activeLayerID
        let second = try document.addLayer()
        let third = try document.addLayer()
        let contents = document.layers.map { ($0.id, $0.plan) }
        try document.moveLayer(id: first, to: 2)
        XCTAssertEqual(document.layers.map(\.id), [second, third, first])
        XCTAssertEqual(document.activeLayerID, third)
        for (id, plan) in contents { XCTAssertEqual(document.layers.first { $0.id == id }?.plan, plan) }
        let before = document
        XCTAssertThrowsError(try document.moveLayer(id: first, to: 3))
        XCTAssertEqual(document, before)
    }

    func testInvalidLayeredFilesDoNotFallbackToLegacyPayload() throws {
        let plan = FloorPlan.example
        let data = try JSONEncoder().encode(plan)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 1
        object["layers"] = []
        object["activeLayerID"] = UUID().uuidString
        XCTAssertThrowsError(try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: object)))
        object["version"] = 2
        XCTAssertThrowsError(try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? PlanDocumentError, .unsupportedVersion(2))
        }
        object["version"] = 1
        object.removeValue(forKey: "layers")
        XCTAssertThrowsError(try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testValidationRejectsMissingActiveFloorAndDuplicateLayerIDs() throws {
        var document = PlanDocument.example
        document.layers.append(document.layers[0])
        XCTAssertThrowsError(try document.validate()) {
            XCTAssertEqual($0 as? PlanDocumentError, .duplicateLayerIdentifier)
        }
        document = .example
        document.activeLayerID = UUID()
        XCTAssertThrowsError(try document.validate()) {
            XCTAssertEqual($0 as? PlanDocumentError, .missingLayer)
        }
    }
}
