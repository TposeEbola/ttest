import Foundation
import XCTest
@testable import BlueprintCore

final class PlanItemTests: XCTestCase {
    private func item(
        kind: PlanItemKind = .desk, position: PlanPoint = .init(x: 0, y: 0),
        width: Double = 1524, depth: Double = 762, rotation: Double = 0
    ) -> PlanItem {
        PlanItem(name: "Test object", kind: kind, position: position,
                 width: width, depth: depth, rotationDegrees: rotation)
    }

    func testLegacyPlanWithoutItemsPreservesExistingWallsAndOpenings() throws {
        let original = FloorPlan.example
        let encoded = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "items")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: legacyData)
        XCTAssertTrue(decoded.items.isEmpty)
        XCTAssertEqual(decoded, original)
        try decoded.validate()
    }

    func testEveryPresetSurvivesPlanRoundTripWithExactDimensions() throws {
        var plan = FloorPlan.example
        for preset in ObjectCategory.allCases.flatMap(ObjectCatalog.presets(for:)) {
            try plan.addItem(kind: preset.kind, name: preset.name, position: .init(x: 123.45, y: -67.89),
                             width: preset.width, depth: preset.depth, rotationDegrees: 22.5)
        }
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan)
        try decoded.validate()
    }

    func testCatalogHasAllCategoriesAndKindsWithStableUniqueIdentifiers() throws {
        let presets = ObjectCategory.allCases.flatMap(ObjectCatalog.presets(for:))
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
        XCTAssertEqual(Set(presets.map(\.kind)), Set(PlanItemKind.allCases))
        for category in ObjectCategory.allCases {
            let categoryPresets = ObjectCatalog.presets(for: category)
            XCTAssertGreaterThanOrEqual(categoryPresets.count, 3, category.rawValue)
            for preset in categoryPresets {
                XCTAssertEqual(preset.category, category)
                XCTAssertEqual(preset.kind.category, category)
                XCTAssertFalse(preset.id.isEmpty)
                try PlanItem(name: preset.name, kind: preset.kind, position: .init(x: 0, y: 0),
                             width: preset.width, depth: preset.depth).validate()
            }
        }
    }

    func testBedAndStairPresetsUseCommonExactImperialDimensions() throws {
        let beds = ObjectCatalog.presets(for: .bedroom)
        let queen = try XCTUnwrap(beds.first { $0.id == "bedroom.queen-bed" })
        XCTAssertEqual(queen.width, 60 * 25.4, accuracy: 0.000_001)
        XCTAssertEqual(queen.depth, 80 * 25.4, accuracy: 0.000_001)
        let twin = try XCTUnwrap(beds.first { $0.id == "bedroom.twin-bed" })
        XCTAssertEqual(twin.width, 38 * 25.4, accuracy: 0.000_001)
        XCTAssertEqual(twin.depth, 75 * 25.4, accuracy: 0.000_001)
        let stairs = try XCTUnwrap(ObjectCatalog.presets(for: .staircase).first { $0.id == "staircase.straight" })
        XCTAssertEqual(stairs.width, 36 * 25.4, accuracy: 0.000_001)
        XCTAssertEqual(stairs.depth, 10 * 304.8, accuracy: 0.000_001)
    }

    func testCornersRotateAboutCentre() {
        let rotated = item(position: .init(x: 100, y: 200), width: 2000, depth: 1000, rotation: 90)
        let expected = [
            PlanPoint(x: 600, y: -800), PlanPoint(x: 600, y: 1200),
            PlanPoint(x: -400, y: 1200), PlanPoint(x: -400, y: -800)
        ]
        for (actual, expected) in zip(rotated.corners, expected) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_001)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_001)
        }
    }

    func testVeryLargeFiniteRotationsKeepFiniteCorners() throws {
        let rotated = item(rotation: .greatestFiniteMagnitude)
        try rotated.validate()
        XCTAssertTrue(rotated.corners.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testInvalidAddIsAtomicForMalformedSizesNamesAnglesAndCoordinates() throws {
        var plan = FloorPlan.example
        let before = plan
        for size in [0, -1, Double.nan, Double.infinity, 1_000_001] {
            XCTAssertThrowsError(try plan.addItem(kind: .desk, name: "Desk", position: .init(x: 0, y: 0),
                                                width: size, depth: 500))
            XCTAssertEqual(plan, before)
        }
        for name in ["", " \n\t", String(repeating: "x", count: 101)] {
            XCTAssertThrowsError(try plan.addItem(kind: .desk, name: name, position: .init(x: 0, y: 0),
                                                width: 1000, depth: 500))
            XCTAssertEqual(plan, before)
        }
        for angle in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try plan.addItem(kind: .desk, name: "Desk", position: .init(x: 0, y: 0),
                                                width: 1000, depth: 500, rotationDegrees: angle))
            XCTAssertEqual(plan, before)
        }
        for position in [PlanPoint(x: .nan, y: 0), .init(x: 10_000_001, y: 0)] {
            XCTAssertThrowsError(try plan.addItem(kind: .desk, name: "Desk", position: position,
                                                width: 1000, depth: 500))
            XCTAssertEqual(plan, before)
        }
    }

    func testRotatedFootprintMustRemainWithinPlanBounds() throws {
        let withinBounds = item(position: .init(x: 9_999_400, y: 0), width: 1000, depth: 1000)
        try withinBounds.validate()
        var rotated = withinBounds
        rotated.rotationDegrees = 45
        XCTAssertThrowsError(try rotated.validate()) { XCTAssertEqual($0 as? PlanError, .invalidCoordinate) }
        try item(position: .init(x: 9_999_999.5, y: 0), width: 1, depth: 1).validate()
    }

    func testCircleAndSpiralStairsRequireOneDiameter() throws {
        for kind in [PlanItemKind.circle, .spiralStairs] {
            let circular = item(kind: kind, width: 1000, depth: 1000)
            XCTAssertTrue(circular.isCircular)
            try circular.validate()
            XCTAssertThrowsError(try item(kind: kind, width: 1000, depth: 999).validate()) {
                XCTAssertEqual($0 as? PlanItemError, .circularDimensions)
            }
        }
        XCTAssertFalse(item(kind: .ellipse).isCircular)
        try item(kind: .ellipse, width: 1000, depth: 600).validate()
        XCTAssertEqual(PlanItemKind.circle.category, .shapes)
    }

    func testUpdateAndRemovalPreserveIdentityAndRejectFailedEditsAtomically() throws {
        var plan = FloorPlan.empty
        let id = try plan.addItem(kind: .desk, name: " Desk ", position: .init(x: 0, y: 0),
                                  width: 1524, depth: 762)
        XCTAssertEqual(plan.items[0].name, "Desk")
        try plan.updateItem(id: id, name: " Studio desk ", position: .init(x: 200, y: 300),
                            width: 1800, depth: 800, rotationDegrees: -45)
        XCTAssertEqual(plan.items[0].id, id)
        XCTAssertEqual(plan.items[0].kind, .desk)
        XCTAssertEqual(plan.items[0].name, "Studio desk")
        XCTAssertEqual(plan.items[0].position, .init(x: 200, y: 300))
        XCTAssertEqual(plan.items[0].rotationDegrees, -45)
        let before = plan
        XCTAssertThrowsError(try plan.updateItem(id: id, name: "Bad edit", position: .init(x: 0, y: 0),
                                                width: 0, depth: 800, rotationDegrees: 0))
        XCTAssertEqual(plan, before)
        XCTAssertThrowsError(try plan.updateItem(id: UUID(), name: "Unknown", position: .init(x: 0, y: 0),
                                                width: 1000, depth: 800, rotationDegrees: 0)) {
            XCTAssertEqual($0 as? PlanItemError, .missingItem)
        }
        XCTAssertEqual(plan, before)
        plan.removeItem(id: id)
        XCTAssertTrue(plan.items.isEmpty)
        try plan.validate()
    }

    func testItemIdentifiersAreUniqueAcrossEveryEntityType() throws {
        var plan = FloorPlan.example
        let dimension = PlanDimension(start: .init(x: 0, y: 0), end: .init(x: 1000, y: 0))
        let area = PlanArea(vertices: [.init(x: 0, y: 0), .init(x: 1000, y: 0), .init(x: 0, y: 1000)])
        plan.dimensions = [dimension]
        plan.areas = [area]
        let occupied = [plan.walls[0].id, plan.openings[0].id, dimension.id, area.id]
        for id in occupied {
            var collision = item()
            collision.id = id
            plan.items = [collision]
            XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .duplicateIdentifier) }
        }
        let duplicate = item()
        plan.items = [duplicate, duplicate]
        XCTAssertThrowsError(try plan.validate()) { XCTAssertEqual($0 as? PlanError, .duplicateIdentifier) }
    }

    func testInvalidDecodedItemIsRejectedByPlanValidation() throws {
        var plan = FloorPlan.empty
        plan.items = [item(width: -200)]
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertThrowsError(try decoded.validate()) { XCTAssertEqual($0 as? PlanItemError, .invalidSize) }
    }
}
