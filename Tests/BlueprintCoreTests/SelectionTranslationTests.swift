import XCTest
@testable import BlueprintCore

final class SelectionTranslationTests: XCTestCase {
    func testMovingWallRetainsLengthAndMovesSharedCornerAndAttachedDoor() throws {
        var plan = FloorPlan.empty
        let first = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let adjoining = try plan.addWall(from: .init(x: 4000, y: 0), to: .init(x: 4000, y: 3000))
        let door = try plan.addOpening(wallID: first, kind: .door, offset: 1000, width: 800, height: 2000)
        let oldOpening = try XCTUnwrap(plan.openings.first)

        try plan.translateSelection(PlanSelection(wallIDs: [first], openingIDs: [door]), by: .init(x: 300, y: 400))

        let moved = try XCTUnwrap(plan.walls.first { $0.id == first })
        let connected = try XCTUnwrap(plan.walls.first { $0.id == adjoining })
        XCTAssertEqual(moved.start, PlanPoint(x: 300, y: 400))
        XCTAssertEqual(moved.end, PlanPoint(x: 4300, y: 400))
        XCTAssertEqual(moved.length, 4000, accuracy: 0.000_001)
        XCTAssertEqual(connected.start, moved.end)
        XCTAssertEqual(connected.end, PlanPoint(x: 4000, y: 3000))
        XCTAssertEqual(plan.openings.first, oldOpening, "Attached openings retain their host-relative position exactly")
        XCTAssertEqual(moved.point(at: oldOpening.offset), PlanPoint(x: 1300, y: 400))
    }

    func testSelectedConnectedGroupMovesEachJunctionOnce() throws {
        var plan = FloorPlan.empty
        let a = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 3000, y: 0))
        let b = try plan.addWall(from: .init(x: 3000, y: 0), to: .init(x: 3000, y: 2000))
        let unchanged = try plan.addWall(from: .init(x: -5000, y: -5000), to: .init(x: -4000, y: -5000))
        let originalDetached = try XCTUnwrap(plan.walls.first { $0.id == unchanged })

        try plan.translateSelection(PlanSelection(wallIDs: [a, b]), by: .init(x: 500, y: -250))

        XCTAssertEqual(plan.walls[0].end, PlanPoint(x: 3500, y: -250))
        XCTAssertEqual(plan.walls[1].start, plan.walls[0].end)
        XCTAssertEqual(plan.walls[0].length, 3000, accuracy: 0.000_001)
        XCTAssertEqual(plan.walls[1].length, 2000, accuracy: 0.000_001)
        XCTAssertEqual(plan.walls.first { $0.id == unchanged }, originalDetached)
    }

    func testInvalidStretchWithOpeningRejectsWholeDrag() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 3000, y: 0))
        let connected = try plan.addWall(from: .init(x: 3000, y: 0), to: .init(x: 3000, y: 1000))
        try plan.addOpening(wallID: connected, kind: .window, offset: 500, width: 900, height: 1200)
        let before = plan

        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(wallIDs: [wall]), by: .init(x: 0, y: 800))) {
            XCTAssertEqual($0 as? PlanError, .openingOutsideWall)
        }
        XCTAssertEqual(plan, before)
    }

    func testDoorSlidesAlongWallWithoutMovingItsHost() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let opening = try plan.addOpening(wallID: wall, kind: .door, offset: 1500, width: 800, height: 2000)
        let originalWalls = plan.walls

        try plan.translateSelection(PlanSelection(openingIDs: [opening]), by: .init(x: 500, y: 1000))

        XCTAssertEqual(plan.openings[0].offset, 2000, accuracy: 0.000_001)
        XCTAssertEqual(plan.openings[0].wallID, wall)
        XCTAssertEqual(plan.walls, originalWalls)
    }

    func testDoorCanMoveToAnotherWallAtProjectedPosition() throws {
        var plan = FloorPlan.empty
        let source = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let target = try plan.addWall(from: .init(x: 6000, y: 0), to: .init(x: 6000, y: 4000))
        let door = try plan.addOpening(wallID: source, kind: .door, offset: 1500, width: 800, height: 2000)
        let originalWalls = plan.walls

        try plan.translateSelection(PlanSelection(openingIDs: [door]), by: .init(x: 4500, y: 2000), targetWallID: target)

        XCTAssertEqual(plan.openings[0].id, door)
        XCTAssertEqual(plan.openings[0].wallID, target)
        XCTAssertEqual(plan.openings[0].offset, 2000, accuracy: 0.000_001)
        XCTAssertEqual(plan.walls, originalWalls)
    }

    func testOpeningOverlapAndEndCrossingRejectAtomically() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let door = try plan.addOpening(wallID: wall, kind: .door, offset: 1500, width: 800, height: 2000)
        try plan.addOpening(wallID: wall, kind: .window, offset: 3000, width: 800, height: 1200)
        let before = plan

        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(openingIDs: [door]), by: .init(x: 1500, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .overlappingOpenings)
        }
        XCTAssertEqual(plan, before)
        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(openingIDs: [door]), by: .init(x: -1500, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .openingOutsideWall)
        }
        XCTAssertEqual(plan, before)
    }

    func testInvalidSelectionTargetAndDeltaDoNotChangePlan() throws {
        var plan = FloorPlan.example
        let before = plan
        let wall = try XCTUnwrap(plan.walls.first)
        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(), by: .init(x: 1, y: 0)))
        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(wallIDs: [UUID()]), by: .init(x: 1, y: 0)))
        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(openingIDs: [UUID()]), by: .init(x: 1, y: 0)))
        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(wallIDs: [wall.id]), by: .init(x: .nan, y: 0)))
        XCTAssertThrowsError(try plan.translateSelection(PlanSelection(wallIDs: [wall.id]), by: .init(x: 1, y: 0), targetWallID: wall.id)) {
            XCTAssertEqual($0 as? SelectionTranslationError, .ambiguousDestinationWall)
        }
        XCTAssertEqual(plan, before)
        try plan.translateSelection(PlanSelection(wallIDs: [wall.id]), by: .init(x: 0, y: 0))
        XCTAssertEqual(plan, before)
    }

    func testMovingSelectedOpeningOnStretchedUnselectedHostUsesNewHostProjection() throws {
        var plan = FloorPlan.empty
        let moving = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 3000, y: 0))
        let host = try plan.addWall(from: .init(x: 3000, y: 0), to: .init(x: 3000, y: 4000))
        let door = try plan.addOpening(wallID: host, kind: .door, offset: 1500, width: 800, height: 2000)
        let delta = PlanPoint(x: 500, y: 300)
        let expectedCenter = PlanPoint(x: 3500, y: 1800)

        try plan.translateSelection(PlanSelection(wallIDs: [moving], openingIDs: [door]), by: delta)

        let updatedHost = try XCTUnwrap(plan.walls.first { $0.id == host })
        XCTAssertEqual(plan.openings[0].offset, Geometry.projectedDistance(of: expectedCenter, onto: updatedHost), accuracy: 0.000_001)
        try plan.validate()
    }
}
