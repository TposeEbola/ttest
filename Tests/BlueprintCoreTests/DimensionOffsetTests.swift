import Foundation
import XCTest
@testable import BlueprintCore

final class DimensionOffsetTests: XCTestCase {
    func testHorizontalOffsetsKeepAnchorsAndMeasuredLength() {
        let start = PlanPoint(x: 100, y: 200)
        let end = PlanPoint(x: 1100, y: 200)
        for offset in [-350.0, 350.0] {
            let dimension = PlanDimension(start: start, end: end, offset: offset)
            XCTAssertEqual(dimension.start, start)
            XCTAssertEqual(dimension.end, end)
            XCTAssertEqual(dimension.lineStart, .init(x: 100, y: 200 + offset))
            XCTAssertEqual(dimension.lineEnd, .init(x: 1100, y: 200 + offset))
            XCTAssertEqual(dimension.length, 1000)
        }
    }

    func testVerticalOffsetsMoveLeftAndRight() {
        for offset in [-250.0, 250.0] {
            let dimension = PlanDimension(start: .init(x: 100, y: 200), end: .init(x: 100, y: 1200), offset: offset)
            XCTAssertEqual(dimension.lineStart, .init(x: 100 - offset, y: 200))
            XCTAssertEqual(dimension.lineEnd, .init(x: 100 - offset, y: 1200))
            XCTAssertEqual(dimension.length, 1000)
        }
    }

    func testDiagonalOffsetIsPerpendicularAndDoesNotChangeLength() {
        let dimension = PlanDimension(start: .init(x: 100, y: 200), end: .init(x: 3100, y: 4200), offset: 500)
        XCTAssertEqual(dimension.lineStart.x, -300, accuracy: 0.000_001)
        XCTAssertEqual(dimension.lineStart.y, 500, accuracy: 0.000_001)
        XCTAssertEqual(dimension.lineEnd.x, 2700, accuracy: 0.000_001)
        XCTAssertEqual(dimension.lineEnd.y, 4500, accuracy: 0.000_001)
        XCTAssertEqual(dimension.length, 5000, accuracy: 0.000_001)
        XCTAssertEqual(dimension.lineStart.distance(to: dimension.lineEnd), dimension.length, accuracy: 0.000_001)
        let dx = dimension.lineStart.x - dimension.start.x
        let dy = dimension.lineStart.y - dimension.start.y
        XCTAssertEqual(dx * 3000 + dy * 4000, 0, accuracy: 0.000_001)
        XCTAssertEqual(hypot(dx, dy), 500, accuracy: 0.000_001)
    }

    func testLegacyDimensionDecodesWithZeroOffset() throws {
        let original = PlanDimension(start: .init(x: 20, y: 30), end: .init(x: 1020, y: 30))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "offset")
        let decoded = try JSONDecoder().decode(PlanDimension.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.offset, 0)
        XCTAssertEqual(decoded.lineStart, decoded.start)
        XCTAssertEqual(decoded.lineEnd, decoded.end)
    }

    func testSavedDimensionPreservesOffsetAndAnchors() throws {
        var plan = FloorPlan.empty
        let id = try plan.addDimension(from: .init(x: 10, y: 20), to: .init(x: 3010, y: 4020), offset: -625.5)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(plan))
        try decoded.validate()
        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.dimensions.first?.id, id)
        XCTAssertEqual(decoded.dimensions.first?.offset, -625.5)
    }

    func testLabelAnglesStayReadableInEitherDirection() {
        let origin = PlanPoint(x: 0, y: 0)
        let cases: [(PlanPoint, Double)] = [
            (.init(x: 0, y: 1000), -90),
            (.init(x: 0, y: -1000), -90),
            (.init(x: 1000, y: 0), 0),
            (.init(x: -1000, y: 0), 0),
            (.init(x: 1000, y: 1000), 45),
            (.init(x: -1000, y: -1000), 45),
            (.init(x: -1000, y: 1000), -45),
            (.init(x: 1000, y: -1000), -45)
        ]
        for (end, expected) in cases {
            let dimension = PlanDimension(start: origin, end: end)
            XCTAssertEqual(dimension.labelAngleDegrees, expected, accuracy: 0.000_001)
            XCTAssertEqual(Geometry.readableDimensionAngle(from: end, to: origin), expected, accuracy: 0.000_001)
        }
    }

    func testPointerProjectionUsesOnlyPerpendicularDistance() {
        let horizontal = PlanDimension(start: .init(x: 100, y: 200), end: .init(x: 1100, y: 200))
        XCTAssertEqual(horizontal.projectedOffset(toward: .init(x: 8000, y: 550)), 350)
        XCTAssertEqual(horizontal.projectedOffset(toward: .init(x: -8000, y: -150)), -350)
        let vertical = PlanDimension(start: .init(x: 100, y: 200), end: .init(x: 100, y: 1200))
        XCTAssertEqual(vertical.projectedOffset(toward: .init(x: -150, y: 8000)), 250)
        XCTAssertEqual(vertical.projectedOffset(toward: .init(x: 350, y: -8000)), -250)
        let diagonal = PlanDimension(start: .init(x: 100, y: 200), end: .init(x: 3100, y: 4200))
        XCTAssertEqual(diagonal.projectedOffset(toward: .init(x: 300, y: 1300)), 500, accuracy: 0.000_001)
    }

    func testEditingAnchorsPreservesOffsetUnlessExplicitlyChanged() throws {
        var plan = FloorPlan.empty
        let id = try plan.addDimension(from: .init(x: 0, y: 0), to: .init(x: 1000, y: 0), offset: 250)
        try plan.updateDimension(id: id, start: .init(x: 100, y: 100), end: .init(x: 100, y: 1100))
        XCTAssertEqual(plan.dimensions[0].offset, 250)
        XCTAssertEqual(plan.dimensions[0].lineStart, .init(x: -150, y: 100))
        try plan.updateDimension(id: id, start: .init(x: 100, y: 100), end: .init(x: 100, y: 1100), offset: -300)
        XCTAssertEqual(plan.dimensions[0].offset, -300)
        XCTAssertEqual(plan.dimensions[0].lineStart, .init(x: 400, y: 100))
    }

    func testInvalidOffsetsAreRejectedWithoutMutatingPlan() throws {
        var plan = FloorPlan.empty
        for offset in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try plan.addDimension(from: .init(x: 0, y: 0), to: .init(x: 1000, y: 0), offset: offset)) {
                XCTAssertEqual($0 as? PlanError, .invalidDimensionOffset)
            }
            XCTAssertTrue(plan.dimensions.isEmpty)
        }
        let id = try plan.addDimension(from: .init(x: 0, y: 0), to: .init(x: 1000, y: 0), offset: 250)
        let before = plan
        XCTAssertThrowsError(try plan.updateDimension(id: id, start: .init(x: 0, y: 0), end: .init(x: 1000, y: 0), offset: .nan)) {
            XCTAssertEqual($0 as? PlanError, .invalidDimensionOffset)
        }
        XCTAssertEqual(plan, before)
    }

    func testOffsetLineOutsidePlanBoundsIsRejected() throws {
        var plan = FloorPlan.empty
        XCTAssertThrowsError(try plan.addDimension(from: .init(x: 0, y: 9_999_900), to: .init(x: 1000, y: 9_999_900), offset: 200)) {
            XCTAssertEqual($0 as? PlanError, .invalidCoordinate)
        }
        XCTAssertTrue(plan.dimensions.isEmpty)
    }
}
