import Foundation
import XCTest
@testable import BlueprintCore

final class AreaTests: XCTestCase {
    private func rectangle(x: Double = 0, y: Double = 0, width: Double = 3000, height: Double = 2000) -> [PlanPoint] {
        [.init(x: x, y: y), .init(x: x + width, y: y),
         .init(x: x + width, y: y + height), .init(x: x, y: y + height)]
    }

    func testRectangleAreaAndPerimeterAreIndependentOfWindingAndOrigin() throws {
        let vertices = rectangle(x: 9_000_000, y: 9_000_000, width: 3000.125, height: 2000.25)
        let area = PlanArea(name: "Room", vertices: vertices)
        try area.validate()
        XCTAssertEqual(area.areaSquareMillimetres, 3000.125 * 2000.25, accuracy: 0.000_001)
        XCTAssertEqual(area.perimeter, 2 * (3000.125 + 2000.25), accuracy: 0.000_001)
        let reversed = PlanArea(vertices: Array(vertices.reversed()))
        try reversed.validate()
        XCTAssertEqual(reversed.areaSquareMillimetres, area.areaSquareMillimetres)
        XCTAssertEqual(reversed.perimeter, area.perimeter)
    }

    func testConcaveAreaAndForwardCollinearCornersAreAccepted() throws {
        let lShape: [PlanPoint] = [.init(x: 0, y: 0), .init(x: 4000, y: 0), .init(x: 4000, y: 1000),
                                   .init(x: 2000, y: 1000), .init(x: 2000, y: 3000), .init(x: 0, y: 3000)]
        let area = PlanArea(vertices: lShape)
        try area.validate()
        XCTAssertEqual(area.areaSquareMillimetres, 8_000_000, accuracy: 0.000_001)
        let straightEdge: [PlanPoint] = [.init(x: 0, y: 0), .init(x: 1500, y: 0), .init(x: 3000, y: 0),
                                         .init(x: 3000, y: 2000), .init(x: 0, y: 2000)]
        let collinear = PlanArea(vertices: straightEdge)
        try collinear.validate()
        XCTAssertEqual(collinear.areaSquareMillimetres, 6_000_000)
    }

    func testAddTrimsDuplicateClosingCornerAndCreatesUniqueNames() throws {
        var plan = FloorPlan.empty
        let vertices = rectangle()
        let first = try plan.addArea(vertices: vertices + [vertices[0]])
        try plan.addArea(vertices: rectangle(x: 4000))
        XCTAssertEqual(plan.areas.map(\.name), ["Area 1", "Area 2"])
        XCTAssertEqual(plan.areas[0].vertices, vertices)
        try plan.updateArea(id: first, name: "  Living room  ", vertices: vertices + [vertices[0]])
        XCTAssertEqual(plan.areas[0].name, "Living room")
        XCTAssertEqual(plan.areas[0].vertices, vertices)
        plan.removeArea(id: first)
        XCTAssertEqual(plan.areas.count, 1)
        XCTAssertEqual(plan.areas[0].name, "Area 2")
    }

    func testAreaAndLegacyDocumentsRoundTripWithoutChangingExistingGeometry() throws {
        let original = FloorPlan.example
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "areas")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        var decoded = try JSONDecoder().decode(FloorPlan.self, from: oldData)
        try decoded.validate()
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.areas.isEmpty)
        let id = try decoded.addArea(vertices: rectangle(), name: "Ground floor")
        let saved = try JSONEncoder().encode(decoded)
        let reopened = try JSONDecoder().decode(FloorPlan.self, from: saved)
        try reopened.validate()
        XCTAssertEqual(reopened, decoded)
        XCTAssertEqual(reopened.areas[0].id, id)
        XCTAssertEqual(reopened.walls, original.walls)
        XCTAssertEqual(reopened.openings, original.openings)
    }

    func testSelfCrossingOverlappingTouchingAndDegeneratePolygonsAreRejected() throws {
        let invalid: [[PlanPoint]] = [
            // Crossing diagonals.
            [.init(x: 0, y: 0), .init(x: 2000, y: 2000), .init(x: 0, y: 2000), .init(x: 2000, y: 0)],
            // Nonadjacent edge touches a previous horizontal edge.
            [.init(x: 0, y: 0), .init(x: 3000, y: 0), .init(x: 3000, y: 3000),
             .init(x: 1500, y: 0), .init(x: 0, y: 3000)],
            // Adjacent collinear backtracking overlaps a segment.
            [.init(x: 0, y: 0), .init(x: 3000, y: 0), .init(x: 2000, y: 0),
             .init(x: 2000, y: 2000), .init(x: 0, y: 2000)],
            // Repeated nonadjacent corner.
            [.init(x: 0, y: 0), .init(x: 3000, y: 0), .init(x: 3000, y: 2000),
             .init(x: 0, y: 0), .init(x: 0, y: 2000)],
            // Entirely collinear.
            [.init(x: 0, y: 0), .init(x: 1000, y: 0), .init(x: 2000, y: 0)]
        ]
        for vertices in invalid { XCTAssertThrowsError(try PlanArea(vertices: vertices).validate()) }
        XCTAssertThrowsError(try PlanArea(vertices: rectangle(width: 0.5, height: 0.5)).validate()) {
            XCTAssertEqual($0 as? PlanAreaError, .degenerateArea)
        }
        XCTAssertThrowsError(try PlanArea(vertices: [.init(x: 0, y: 0), .init(x: 100, y: 0)]).validate()) {
            XCTAssertEqual($0 as? PlanAreaError, .tooFewVertices)
        }
    }

    func testInvalidCoordinatesNamesAndDuplicateIDsAreAtomic() throws {
        var plan = FloorPlan.example
        let before = plan
        XCTAssertThrowsError(try plan.addArea(vertices: rectangle(), name: "  "))
        XCTAssertThrowsError(try plan.addArea(vertices: rectangle(x: .infinity)))
        XCTAssertThrowsError(try plan.addArea(vertices: rectangle(x: 10_000_001)))
        XCTAssertEqual(plan, before)
        let id = try plan.addArea(vertices: rectangle())
        let saved = plan
        XCTAssertThrowsError(try plan.updateArea(id: id, name: String(repeating: "a", count: 101), vertices: rectangle()))
        XCTAssertEqual(plan, saved)
        plan.areas[0].id = plan.walls[0].id
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .duplicateIdentifier) }
        plan = saved
        plan.areas.append(plan.areas[0])
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .duplicateIdentifier) }
    }

    func testRoomBoundarySnapsToTrueInsideAndOutsideCorners() throws {
        let plan = FloorPlan.example
        let inside: [PlanPoint] = [.init(x: 76.2, y: 76.2), .init(x: 6019.8, y: 76.2),
                                   .init(x: 6019.8, y: 4495.8), .init(x: 76.2, y: 4495.8)]
        let outside: [PlanPoint] = [.init(x: -76.2, y: -76.2), .init(x: 6172.2, y: -76.2),
                                    .init(x: 6172.2, y: 4648.2), .init(x: -76.2, y: 4648.2)]
        let snappedInside = try inside.map { point in
            try XCTUnwrap(Geometry.nearestAreaBoundaryPoint(to: .init(x: point.x + 1, y: point.y - 1),
                                                          walls: plan.walls, tolerance: 5))
        }
        let snappedOutside = try outside.map { point in
            try XCTUnwrap(Geometry.nearestAreaBoundaryPoint(to: .init(x: point.x - 1, y: point.y + 1),
                                                          walls: plan.walls, tolerance: 5))
        }
        for (actual, expected) in zip(snappedInside + snappedOutside, inside + outside) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_001)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_001)
        }
        let innerArea = PlanArea(vertices: snappedInside)
        let outerArea = PlanArea(vertices: snappedOutside)
        try innerArea.validate(); try outerArea.validate()
        XCTAssertEqual(innerArea.areaSquareMillimetres / (304.8 * 304.8), 282.75, accuracy: 0.000_001)
        XCTAssertEqual(outerArea.areaSquareMillimetres / (304.8 * 304.8), 317.75, accuracy: 0.000_001)
    }

    func testAreaBoundarySnapFallsBackToFaceAndSafelyRejectsInvalidInputs() throws {
        let wall = Wall(start: .init(x: 0, y: 0), end: .init(x: 3000, y: 4000), thickness: 200)
        let face = PlanPoint(x: 1420, y: 2060)
        let snapped = try XCTUnwrap(Geometry.nearestAreaBoundaryPoint(to: .init(x: face.x + 0.8, y: face.y - 0.6),
                                                                     walls: [wall], tolerance: 2))
        XCTAssertEqual(snapped.x, face.x, accuracy: 0.000_001)
        XCTAssertEqual(snapped.y, face.y, accuracy: 0.000_001)
        XCTAssertNil(Geometry.nearestAreaBoundaryPoint(to: face, walls: [wall], tolerance: -.infinity))
        XCTAssertNil(Geometry.nearestAreaBoundaryPoint(to: .init(x: .nan, y: 0), walls: [wall], tolerance: 10))
        XCTAssertNil(Geometry.nearestAreaBoundaryPoint(to: .init(x: 8000, y: 8000), walls: [wall], tolerance: 5))
    }

    func testLockedFloorRejectsAreaEditsAndWallDeletionDoesNotMoveAreas() throws {
        var document = PlanDocument.example
        let floor = document.activeLayerID
        try document.editActivePlan { try $0.addArea(vertices: rectangle()) }
        let savedArea = document.activeLayer.plan.areas
        try document.editActivePlan { $0.removeWall(id: $0.walls[0].id) }
        XCTAssertEqual(document.activeLayer.plan.areas, savedArea)
        try document.setLayerLocked(id: floor, locked: true)
        let locked = document
        XCTAssertThrowsError(try document.editActivePlan { try $0.addArea(vertices: rectangle()) }) {
            XCTAssertEqual($0 as? PlanDocumentError, .lockedLayer)
        }
        XCTAssertEqual(document, locked)
    }
}
