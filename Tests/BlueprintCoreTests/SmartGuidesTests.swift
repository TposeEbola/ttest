import XCTest
@testable import BlueprintCore

final class SmartGuidesTests: XCTestCase {
    private func point(angle: Double, length: Double = 2000, from start: PlanPoint = .init(x: 0, y: 0)) -> PlanPoint {
        PlanPoint(x: start.x + cos(angle * .pi / 180) * length, y: start.y + sin(angle * .pi / 180) * length)
    }

    func testCardinalGuideHasExactAxisAndPreservesLength() {
        let start = PlanPoint(x: 123.4, y: -55)
        let result = Geometry.guidedWall(from: start, to: point(angle: 89, from: start), referenceWalls: [], lengthTolerance: 5)
        XCTAssertEqual(result.angleDegrees, 90)
        XCTAssertNil(result.matchedLength)
        XCTAssertEqual(result.end.x, start.x)
        XCTAssertEqual(result.end.y, start.y + 2000, accuracy: 0.000_001)
        XCTAssertEqual(start.distance(to: result.end), 2000, accuracy: 0.000_001)
    }

    func testGuidesNormalizeAllQuadrantsAndWrapAcrossZero() {
        for (input, expected) in [(359.0, 0.0), (-89.0, 270.0), (178.5, 180.0), (44.0, 45.0), (226.0, 225.0)] {
            let result = Geometry.guidedWall(from: .init(x: 0, y: 0), to: point(angle: input), referenceWalls: [], lengthTolerance: 0)
            XCTAssertEqual(result.angleDegrees, expected)
            XCTAssertEqual(Geometry.snappedRotation(input), expected)
        }
        XCTAssertEqual(Geometry.snappedRotation(720.5), 0)
        XCTAssertEqual(Geometry.snappedRotation(-360), 0)
    }

    func testAngleAndNearestReferenceLengthApplyTogether() {
        let references = [
            Wall(start: .init(x: 0, y: 0), end: .init(x: 2500, y: 0)),
            Wall(start: .init(x: 0, y: 0), end: .init(x: 3000, y: 0))
        ]
        let start = PlanPoint(x: 10, y: 20)
        let result = Geometry.guidedWall(from: start, to: point(angle: 89, length: 2990, from: start), referenceWalls: references, lengthTolerance: 20)
        XCTAssertEqual(result.angleDegrees, 90)
        XCTAssertEqual(result.matchedLength, 3000)
        XCTAssertEqual(result.end, PlanPoint(x: 10, y: 3020))
    }

    func testGridMeasurementFallbackAndReferencePriority() {
        let origin = PlanPoint(x: 0, y: 0)
        let proposed = point(angle: 10, length: 1233)
        let grid = Geometry.guidedWall(from: origin, to: proposed, referenceWalls: [], lengthTolerance: 40, gridStep: 100)
        XCTAssertNil(grid.angleDegrees)
        XCTAssertEqual(grid.matchedLength, 1200)
        XCTAssertEqual(origin.distance(to: grid.end), 1200, accuracy: 0.000_001)
        let reference = Wall(start: origin, end: .init(x: 1250, y: 0))
        let matching = Geometry.guidedWall(from: origin, to: proposed, referenceWalls: [reference], lengthTolerance: 40, gridStep: 100)
        XCTAssertEqual(matching.matchedLength, 1250)
        let positive = Geometry.guidedWall(from: origin, to: .init(x: 2, y: 0), referenceWalls: [], lengthTolerance: 100, gridStep: 100)
        XCTAssertEqual(positive.matchedLength, 100)
    }

    func testOutsideTolerancesRetainsOriginalEndpoint() {
        let proposed = point(angle: 10, length: 2000)
        let reference = Wall(start: .init(x: 0, y: 0), end: .init(x: 2100, y: 0))
        let result = Geometry.guidedWall(from: .init(x: 0, y: 0), to: proposed, referenceWalls: [reference], lengthTolerance: 5, gridStep: 300)
        XCTAssertEqual(result, WallGuideResult(end: proposed))
        XCTAssertNil(Geometry.snappedRotation(10))
        XCTAssertNil(Geometry.snappedRotation(0.1, toleranceDegrees: 0))
        XCTAssertEqual(Geometry.snappedRotation(90, toleranceDegrees: 0), 90)
    }

    func testInvalidAndZeroInputsAreSafeAndDoNotAdvertiseGuides() {
        let origin = PlanPoint(x: 0, y: 0)
        XCTAssertEqual(Geometry.guidedWall(from: origin, to: origin, referenceWalls: [], lengthTolerance: 10), WallGuideResult(end: origin))
        let proposed = PlanPoint(x: 100, y: 0)
        XCTAssertEqual(Geometry.guidedWall(from: origin, to: proposed, referenceWalls: [], lengthTolerance: .infinity), WallGuideResult(end: proposed))
        XCTAssertEqual(Geometry.guidedWall(from: origin, to: proposed, referenceWalls: [], angleToleranceDegrees: .nan, lengthTolerance: 10), WallGuideResult(end: proposed))
        let invalid = Geometry.guidedWall(from: origin, to: .init(x: .nan, y: 2), referenceWalls: [], lengthTolerance: 10)
        XCTAssertTrue(invalid.end.x.isNaN)
        XCTAssertNil(invalid.angleDegrees)
        XCTAssertNil(invalid.matchedLength)
        XCTAssertNil(Geometry.snappedRotation(.nan))
        XCTAssertNil(Geometry.snappedRotation(.infinity))
        XCTAssertNil(Geometry.snappedRotation(90, toleranceDegrees: -1))
    }
}
