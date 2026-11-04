import Foundation
import XCTest
@testable import BlueprintCore

final class FloorPlanTests: XCTestCase {
    func testConnectedEndpointsMoveTogether() throws {
        var plan = FloorPlan.empty
        let corner = PlanPoint(x: 3000, y: 0)
        let first = try plan.addWall(from: .init(x: 0, y: 0), to: corner)
        try plan.addWall(from: corner, to: .init(x: 3000, y: 4000))
        let moved = PlanPoint(x: 3500, y: 500)
        try plan.updateWall(id: first, start: .init(x: 0, y: 0), end: moved, thickness: 200)
        XCTAssertEqual(plan.walls[0].end, moved)
        XCTAssertEqual(plan.walls[1].start, moved)
        XCTAssertEqual(plan.walls[0].thickness, 200)
        XCTAssertEqual(plan.walls[1].thickness, 150)
    }

    func testInvalidConnectedEditIsAtomic() throws {
        var plan = FloorPlan.empty
        let first = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 3000, y: 0))
        try plan.addWall(from: .init(x: 3000, y: 0), to: .init(x: 3000, y: 1000))
        try plan.addOpening(wallID: plan.walls[1].id, kind: .window, offset: 500, width: 900, height: 1200)
        let before = plan
        XCTAssertThrowsError(try plan.updateWall(
            id: first, start: .init(x: 0, y: 0), end: .init(x: 3000, y: 800), thickness: 150
        )) { XCTAssertEqual($0 as? PlanError, .openingOutsideWall) }
        XCTAssertEqual(plan, before)
    }

    func testOpeningFitAndOverlapAreEnforcedAtomically() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        try plan.addOpening(wallID: wall, kind: .door, offset: 1000, width: 900, height: 2100)
        let before = plan
        XCTAssertThrowsError(try plan.addOpening(wallID: wall, kind: .window, offset: 1200, width: 1000, height: 1200)) {
            XCTAssertEqual($0 as? PlanError, .overlappingOpenings)
        }
        XCTAssertEqual(plan, before)
        XCTAssertThrowsError(try plan.addOpening(wallID: wall, kind: .window, offset: 100, width: 1200, height: 1200)) {
            XCTAssertEqual($0 as? PlanError, .openingOutsideWall)
        }
        XCTAssertEqual(plan, before)
        try plan.addOpening(wallID: wall, kind: .window, offset: 1950, width: 1000, height: 1200)
        XCTAssertEqual(plan.openings.count, 2, "Adjacent openings may share a boundary without overlapping")
    }

    func testOpeningResizeFailureLeavesOriginalUntouched() throws {
        var plan = FloorPlan.example
        let opening = try XCTUnwrap(plan.openings.first)
        let before = plan
        XCTAssertThrowsError(try plan.updateOpening(id: opening.id, offset: opening.offset, width: 10_000, height: 2100))
        XCTAssertEqual(plan, before)
    }

    func testDeletingWallDeletesItsOpeningsOnly() throws {
        var plan = FloorPlan.example
        let target = try XCTUnwrap(plan.walls.first)
        let preserved = plan.openings.filter { $0.wallID != target.id }
        plan.removeWall(id: target.id)
        XCTAssertEqual(plan.openings, preserved)
        XCTAssertFalse(plan.walls.contains { $0.id == target.id })
        try plan.validate()
    }

    func testDocumentRoundTripPreservesPreciseMeasurements() throws {
        var plan = FloorPlan.empty
        try plan.addWall(from: .init(x: -10.125, y: 30.25), to: .init(x: 3690.875, y: 30.25), thickness: 114.3)
        let data = try JSONEncoder().encode(plan)
        let loaded = try JSONDecoder().decode(FloorPlan.self, from: data)
        try loaded.validate()
        XCTAssertEqual(loaded, plan)
        XCTAssertEqual(loaded.walls[0].length, 3701, accuracy: 0.000_001)
    }

    func testMalformedDocumentsAreRejected() throws {
        var plan = FloorPlan.example
        plan.walls[0].end.x = .infinity
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .invalidCoordinate) }
        plan = .example
        plan.walls.append(plan.walls[0])
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .duplicateIdentifier) }
        plan = .example
        plan.openings[0].wallID = UUID()
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .missingWall) }
    }

    func testInvalidWallDimensionsRejected() throws {
        var plan = FloorPlan.empty
        XCTAssertThrowsError(try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 0, y: 0)))
        XCTAssertThrowsError(try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 1000, y: 0), thickness: -.infinity))
        XCTAssertEqual(plan, .empty)
    }

    func testSnappingPrefersJunctionOverGrid() {
        let junction = PlanPoint(x: 1013, y: 997)
        XCTAssertEqual(
            Geometry.snap(point: .init(x: 1000, y: 1000), to: [junction], grid: 100, tolerance: 20), junction
        )
        XCTAssertEqual(
            Geometry.snap(point: .init(x: 1251, y: -151), to: [junction], grid: 100, tolerance: 20),
            PlanPoint(x: 1300, y: -200)
        )
    }

    func testProjectionClampsToWallSegment() {
        let wall = Wall(start: .init(x: 0, y: 0), end: .init(x: 3000, y: 4000))
        XCTAssertEqual(Geometry.projectedDistance(of: .init(x: 3000, y: 4000), onto: wall), 5000, accuracy: 0.000_001)
        XCTAssertEqual(Geometry.distance(from: .init(x: 6000, y: 8000), to: wall), 5000, accuracy: 0.000_001)
        XCTAssertEqual(Geometry.projectedDistance(of: .init(x: -3, y: -4), onto: wall), 0)
    }
}
