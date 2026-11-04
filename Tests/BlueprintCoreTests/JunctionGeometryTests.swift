import XCTest
@testable import BlueprintCore

final class JunctionGeometryTests: XCTestCase {
    func testRightAngleFillsOnlyMissingExteriorQuadrant() throws {
        let origin = PlanPoint(x: 0, y: 0)
        let walls = [
            Wall(start: origin, end: .init(x: 1000, y: 0), thickness: 200),
            Wall(start: origin, end: .init(x: 0, y: 1000), thickness: 200)
        ]
        let patch = try XCTUnwrap(Geometry.junctionPatches(for: walls).first)
        XCTAssertEqual(patch, [origin, .init(x: 0, y: -100), .init(x: -100, y: -100), .init(x: -100, y: 0)])
        XCTAssertEqual(Geometry.junctionPatches(for: walls).count, 1)
    }

    func testUnequalThicknessAndReversedWallEndpoints() throws {
        let origin = PlanPoint(x: 500, y: 300)
        let walls = [
            Wall(start: .init(x: 1500, y: 300), end: origin, thickness: 100),
            Wall(start: .init(x: 500, y: 1300), end: origin, thickness: 300)
        ]
        let patch = try XCTUnwrap(Geometry.junctionPatches(for: walls).first)
        XCTAssertEqual(patch, [origin, .init(x: 500, y: 250), .init(x: 350, y: 250), .init(x: 350, y: 300)])
        XCTAssertEqual(patch.map(\.x).min(), 350)
        XCTAssertEqual(patch.map(\.y).min(), 250)
    }

    func testCollinearAndStandaloneWallsNeedNoPatches() {
        let origin = PlanPoint(x: 0, y: 0)
        let left = Wall(start: .init(x: -1000, y: 0), end: origin)
        let right = Wall(start: origin, end: .init(x: 1000, y: 0))
        XCTAssertTrue(Geometry.junctionPatches(for: [left]).isEmpty)
        XCTAssertTrue(Geometry.junctionPatches(for: [left, right]).isEmpty)
    }

    func testNearParallelJunctionUsesFiniteBoundedBevel() throws {
        let origin = PlanPoint(x: 0, y: 0)
        let walls = [
            Wall(start: origin, end: .init(x: 1000, y: 0), thickness: 200),
            Wall(start: origin, end: .init(x: 1000, y: 0.01), thickness: 200)
        ]
        let patch = try XCTUnwrap(Geometry.junctionPatches(for: walls).first)
        XCTAssertEqual(patch.count, 3)
        XCTAssertTrue(patch.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.distance(to: origin) <= 100.000_001 })
    }

    func testMultipleBranchesDoNotGenerateExteriorPatches() {
        let origin = PlanPoint(x: 0, y: 0)
        let walls = [
            Wall(start: origin, end: .init(x: 1000, y: 0)),
            Wall(start: origin, end: .init(x: 0, y: 1000)),
            Wall(start: origin, end: .init(x: -1000, y: 0))
        ]
        XCTAssertTrue(Geometry.junctionPatches(for: walls).isEmpty)
    }
}
