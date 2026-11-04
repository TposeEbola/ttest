import Foundation
import XCTest
@testable import BlueprintCore

final class EditingModelTests: XCTestCase {
    func testLegacyFloorAndDoorDecodeWithoutNewFields() throws {
        let original = FloorPlan.example
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "dimensions")
        var openings = try XCTUnwrap(object["openings"] as? [[String: Any]])
        for index in openings.indices {
            openings[index].removeValue(forKey: "doorSwingDegrees")
            openings[index].removeValue(forKey: "hingeAtEnd")
        }
        object["openings"] = openings
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: JSONSerialization.data(withJSONObject: object))
        try decoded.validate()
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.dimensions.isEmpty)
        XCTAssertEqual(decoded.openings[0].doorSwingDegrees, 90)
        XCTAssertFalse(decoded.openings[0].hingeAtEnd)
    }

    func testSavedMeasurementAndDoorOrientationRoundTrip() throws {
        var plan = FloorPlan.example
        let door = try XCTUnwrap(plan.openings.first { $0.kind == .door })
        try plan.updateDoor(id: door.id, swingDegrees: -65.5, hingeAtEnd: true)
        let id = try plan.addDimension(from: .init(x: 76.2, y: 123.125), to: .init(x: 6019.8, y: 123.125))
        let saved = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: saved)
        try decoded.validate()
        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.dimensions.first?.id, id)
        XCTAssertEqual(try XCTUnwrap(decoded.dimensions.first).length, 5943.6, accuracy: 0.000_001)
        let decodedDoor = try XCTUnwrap(decoded.openings.first { $0.id == door.id })
        XCTAssertEqual(decodedDoor.doorSwingDegrees, -65.5)
        XCTAssertTrue(decodedDoor.hingeAtEnd)
        XCTAssertEqual(decodedDoor.wallID, door.wallID)
        XCTAssertEqual(decodedDoor.offset, door.offset)
    }

    func testMeasurementEditsAreAtomicAndIndependentOfWallDeletion() throws {
        var plan = FloorPlan.example
        let id = try plan.addDimension(from: .init(x: 20, y: 30), to: .init(x: 1020, y: 30))
        let before = plan
        XCTAssertThrowsError(try plan.updateDimension(id: id, start: .init(x: 0, y: 0), end: .init(x: 0, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .invalidDimensionLength)
        }
        XCTAssertEqual(plan, before)
        plan.removeWall(id: plan.walls[0].id)
        XCTAssertEqual(plan.dimensions, before.dimensions)
        try plan.updateDimension(id: id, start: .init(x: 100, y: 100), end: .init(x: 1100, y: 100))
        XCTAssertEqual(plan.dimensions[0].start, .init(x: 100, y: 100))
        plan.removeDimension(id: id)
        XCTAssertTrue(plan.dimensions.isEmpty)
    }

    func testInvalidMeasurementsAndDuplicateIdentifiersAreRejected() throws {
        var plan = FloorPlan.empty
        XCTAssertThrowsError(try plan.addDimension(from: .init(x: .infinity, y: 0), to: .init(x: 100, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .invalidCoordinate)
        }
        XCTAssertThrowsError(try plan.addDimension(from: .init(x: 0, y: 0), to: .init(x: 0.5, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .invalidDimensionLength)
        }
        XCTAssertThrowsError(try plan.addDimension(from: .init(x: 10_000_001, y: 0), to: .init(x: 0, y: 0)))
        XCTAssertTrue(plan.dimensions.isEmpty)
        let wallID = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 1000, y: 0))
        plan.dimensions = [.init(id: wallID, start: .init(x: 0, y: 10), end: .init(x: 1000, y: 10))]
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .duplicateIdentifier) }
        let repeatedID = UUID()
        plan.dimensions = [
            .init(id: repeatedID, start: .init(x: 0, y: 10), end: .init(x: 1000, y: 10)),
            .init(id: repeatedID, start: .init(x: 0, y: 20), end: .init(x: 1000, y: 20))
        ]
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .duplicateIdentifier) }
    }

    func testDoorRotationIsAtomicAndDoesNotMoveOpeningOrWall() throws {
        var plan = FloorPlan.example
        let door = try XCTUnwrap(plan.openings.first { $0.kind == .door })
        let walls = plan.walls
        try plan.updateDoor(id: door.id, swingDegrees: -180, hingeAtEnd: true)
        let rotated = try XCTUnwrap(plan.openings.first { $0.id == door.id })
        XCTAssertEqual(rotated.offset, door.offset)
        XCTAssertEqual(rotated.width, door.width)
        XCTAssertEqual(rotated.wallID, door.wallID)
        XCTAssertEqual(plan.walls, walls)
        let before = plan
        for invalid in [Double.nan, .infinity, 180.01, -180.01] {
            XCTAssertThrowsError(try plan.updateDoor(id: door.id, swingDegrees: invalid, hingeAtEnd: false)) {
                XCTAssertEqual($0 as? PlanError, .invalidDoorAngle)
            }
            XCTAssertEqual(plan, before)
        }
        let window = try XCTUnwrap(plan.openings.first { $0.kind == .window })
        XCTAssertThrowsError(try plan.updateDoor(id: window.id, swingDegrees: 45, hingeAtEnd: false)) {
            XCTAssertEqual($0 as? PlanError, .notADoor)
        }
        XCTAssertEqual(plan, before)
    }

    func testRoomMeasurementsSnapToInnerWallFaces() throws {
        let walls = [
            Wall(start: .init(x: 0, y: 0), end: .init(x: 0, y: 5000), thickness: 200),
            Wall(start: .init(x: 4000, y: 0), end: .init(x: 4000, y: 5000), thickness: 300)
        ]
        let left = try XCTUnwrap(Geometry.nearestWallFace(to: .init(x: 104, y: 2500), walls: walls, tolerance: 10))
        let right = try XCTUnwrap(Geometry.nearestWallFace(to: .init(x: 3846, y: 2500), walls: walls, tolerance: 10))
        XCTAssertEqual(left, .init(x: 100, y: 2500))
        XCTAssertEqual(right, .init(x: 3850, y: 2500))
        XCTAssertEqual(left.distance(to: right), 3750, accuracy: 0.000_001)
        XCTAssertNil(Geometry.nearestWallFace(to: .init(x: 2000, y: 2500), walls: walls, tolerance: 10))
    }

    func testWallFaceSnappingSupportsAngledWallsAndInvalidInputs() throws {
        let wall = Wall(start: .init(x: 0, y: 0), end: .init(x: 3000, y: 4000), thickness: 200)
        let facePoint = PlanPoint(x: 1500 - 80, y: 2000 + 60)
        let snapped = try XCTUnwrap(Geometry.nearestWallFace(to: .init(x: facePoint.x + 0.8, y: facePoint.y - 0.6), walls: [wall], tolerance: 2))
        XCTAssertEqual(snapped.x, facePoint.x, accuracy: 0.000_001)
        XCTAssertEqual(snapped.y, facePoint.y, accuracy: 0.000_001)
        XCTAssertNil(Geometry.nearestWallFace(to: .init(x: .nan, y: 0), walls: [wall], tolerance: 2))
        XCTAssertNil(Geometry.nearestWallFace(to: facePoint, walls: [wall], tolerance: -.infinity))
        XCTAssertNil(Geometry.nearestWallFace(to: facePoint, walls: [], tolerance: 10))
        let degenerate = Wall(start: .init(x: 0, y: 0), end: .init(x: 0, y: 0))
        XCTAssertNil(Geometry.nearestWallFace(to: .init(x: 0, y: 0), walls: [degenerate], tolerance: 10))
    }
}
