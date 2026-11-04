import Foundation
import XCTest
@testable import BlueprintCore

final class ItemTransformTests: XCTestCase {
    func testItemOnlyClipboardRoundTripAndPastePreserveDimensionsWithFreshIDs() throws {
        let bed = PlanItem(name: "Guest bed", kind: .bed, position: .init(x: 1000, y: 2000),
                           width: 1500, depth: 2000, rotationDegrees: 30)
        let circle = PlanItem(name: "Round feature", kind: .circle, position: .init(x: 4000, y: 2000),
                              width: 800, depth: 800)
        let source = FloorPlan(items: [bed, circle])
        let selected = PlanSelection(itemIDs: [bed.id, circle.id])
        XCTAssertFalse(selected.isEmpty)
        let copied = try source.copySelection(selected)
        let clipboard = try JSONDecoder().decode(PlanClipboard.self, from: JSONEncoder().encode(copied))
        XCTAssertEqual(clipboard, copied)
        XCTAssertTrue(clipboard.walls.isEmpty)
        XCTAssertTrue(clipboard.sourceWalls.isEmpty)

        var destination = FloorPlan.empty
        let pasted = try destination.paste(clipboard, offset: .init(x: 300, y: -700))

        XCTAssertEqual(pasted.itemIDs, Set(destination.items.map(\.id)))
        XCTAssertTrue(pasted.wallIDs.isEmpty)
        XCTAssertTrue(pasted.openingIDs.isEmpty)
        XCTAssertTrue(pasted.itemIDs.isDisjoint(with: selected.itemIDs))
        for (original, copy) in zip(source.items, destination.items) {
            var expected = original
            expected.id = copy.id
            expected.position.x += 300
            expected.position.y -= 700
            XCTAssertEqual(copy, expected)
        }
    }

    func testMixedClipboardIncludesWallAttachmentsAndOnlySelectedItems() throws {
        var source = FloorPlan.empty
        let wall = try source.addWall(from: .init(x: 0, y: 0), to: .init(x: 5000, y: 0))
        try source.addOpening(wallID: wall, kind: .door, offset: 1000, width: 900, height: 2100)
        let desk = try source.addItem(kind: .desk, name: "Desk", position: .init(x: 2500, y: 1500),
                                      width: 1200, depth: 600, rotationDegrees: 270)
        try source.addItem(kind: .plant, name: "Plant", position: .init(x: 4500, y: 2000),
                           width: 400, depth: 400)
        let copied = try source.copySelection(.init(wallIDs: [wall], itemIDs: [desk]))
        var destination = FloorPlan.empty

        let pasted = try destination.paste(copied, offset: .init(x: 1000, y: 500))

        XCTAssertEqual(destination.walls.count, 1)
        XCTAssertEqual(destination.openings.count, 1)
        XCTAssertEqual(destination.items.count, 1)
        XCTAssertNotEqual(destination.walls[0].id, wall)
        XCTAssertNotEqual(destination.openings[0].id, source.openings[0].id)
        XCTAssertNotEqual(destination.items[0].id, desk)
        XCTAssertEqual(destination.openings[0].wallID, destination.walls[0].id)
        XCTAssertEqual(destination.openings[0].offset, source.openings[0].offset)
        XCTAssertEqual(destination.items[0].position, .init(x: 3500, y: 2000))
        XCTAssertEqual(destination.items[0].rotationDegrees, 270)
        XCTAssertEqual(pasted.wallIDs, [destination.walls[0].id])
        XCTAssertEqual(pasted.itemIDs, [destination.items[0].id])
        XCTAssertTrue(pasted.openingIDs.isEmpty)
    }

    func testLegacyClipboardWithoutItemsStillDecodes() throws {
        let wall = Wall(start: .init(x: 0, y: 0), end: .init(x: 3000, y: 0))
        let clipboard = PlanClipboard(walls: [wall])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clipboard)) as? [String: Any])
        legacy.removeValue(forKey: "items")

        let restored = try JSONDecoder().decode(PlanClipboard.self, from: JSONSerialization.data(withJSONObject: legacy))

        XCTAssertEqual(restored.walls, [wall])
        XCTAssertTrue(restored.items.isEmpty)
    }

    func testItemClipboardRejectsDuplicateIDsInvalidGeometryAndMissingSelections() throws {
        let item = PlanItem(name: "Table", kind: .diningTable, position: .init(x: 1000, y: 1000),
                            width: 1500, depth: 800)
        XCTAssertThrowsError(try PlanClipboard(items: [item, item]).validate()) {
            XCTAssertEqual($0 as? PlanError, .duplicateIdentifier)
        }
        var invalid = item
        invalid.width = -1
        XCTAssertThrowsError(try PlanClipboard(items: [invalid]).validate()) {
            XCTAssertEqual($0 as? PlanItemError, .invalidSize)
        }
        var destination = FloorPlan(items: [item])
        let before = destination
        let absent = PlanSelection(itemIDs: [UUID()])
        XCTAssertThrowsError(try destination.copySelection(absent)) {
            XCTAssertEqual($0 as? PlanItemError, .missingItem)
        }
        XCTAssertThrowsError(try destination.rotateSelection(absent, byDegrees: 90))
        XCTAssertThrowsError(try destination.translateSelection(absent, by: .init(x: 10, y: 20)))
        XCTAssertThrowsError(try destination.paste(PlanClipboard(items: [invalid])))
        XCTAssertEqual(destination, before)
    }

    func testItemBoundsDetermineMixedSelectionCenterAndRotateAroundIt() throws {
        let wall = Wall(start: .init(x: 0, y: 0), end: .init(x: 2000, y: 0))
        let item = PlanItem(name: "Rectangle", kind: .rectangle, position: .init(x: 3000, y: 2000),
                            width: 2000, depth: 1000, rotationDegrees: 90)
        let untouched = PlanItem(name: "Circle", kind: .circle, position: .init(x: 9000, y: 9000),
                                 width: 1000, depth: 1000)
        var plan = FloorPlan(walls: [wall], items: [item, untouched])
        let selection = PlanSelection(wallIDs: [wall.id], itemIDs: [item.id])

        let center = try plan.selectionCenter(selection)
        XCTAssertEqual(center.x, 1750, accuracy: 0.000_001)
        XCTAssertEqual(center.y, 1500, accuracy: 0.000_001)
        try plan.rotateSelection(selection, byDegrees: 90)

        XCTAssertEqual(plan.walls[0].start.x, 3250, accuracy: 0.000_001)
        XCTAssertEqual(plan.walls[0].start.y, -250, accuracy: 0.000_001)
        XCTAssertEqual(plan.items[0].position.x, 1250, accuracy: 0.000_001)
        XCTAssertEqual(plan.items[0].position.y, 2750, accuracy: 0.000_001)
        XCTAssertEqual(plan.items[0].rotationDegrees, 180)
        XCTAssertEqual(plan.items[0].width, item.width)
        XCTAssertEqual(plan.items[0].depth, item.depth)
        XCTAssertEqual(plan.items[0].name, item.name)
        XCTAssertEqual(plan.items[1], untouched)
    }

    func testItemsRotateAsGroupAndNegativeAnglesWrap() throws {
        let left = PlanItem(name: "Left desk", kind: .desk, position: .init(x: 1000, y: 1000),
                            width: 1000, depth: 600, rotationDegrees: 20)
        let right = PlanItem(name: "Right desk", kind: .desk, position: .init(x: 3000, y: 1000),
                             width: 1000, depth: 600, rotationDegrees: 350)
        var plan = FloorPlan(items: [left, right])
        let selection = PlanSelection(itemIDs: [left.id, right.id])
        let itemCenter = try plan.selectionCenter(.init(itemIDs: [left.id]))
        XCTAssertEqual(itemCenter.x, left.position.x, accuracy: 0.000_001)
        XCTAssertEqual(itemCenter.y, left.position.y, accuracy: 0.000_001)

        try plan.rotateSelection(selection, byDegrees: -450, around: .init(x: 2000, y: 1000))

        XCTAssertEqual(plan.items[0].position, .init(x: 2000, y: 2000))
        XCTAssertEqual(plan.items[1].position, .init(x: 2000, y: 0))
        XCTAssertEqual(plan.items[0].rotationDegrees, 290)
        XCTAssertEqual(plan.items[1].rotationDegrees, 260)
    }

    func testSelectingItemDoesNotAllowStandaloneOpeningToRotate() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let door = try plan.addOpening(wallID: wall, kind: .door, offset: 1000, width: 900, height: 2100)
        let item = try plan.addItem(kind: .sofa, name: "Sofa", position: .init(x: 2000, y: 2000),
                                   width: 2000, depth: 900)
        let before = plan

        XCTAssertThrowsError(try plan.rotateSelection(.init(openingIDs: [door], itemIDs: [item]), byDegrees: 90)) {
            XCTAssertEqual($0 as? PlanSelectionError, .selectHostWallToRotate)
        }
        XCTAssertEqual(plan, before)
    }

    func testMovingMixedGroupMovesItemOnceAndPreservesSharedWallJunction() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        try plan.addWall(from: .init(x: 4000, y: 0), to: .init(x: 4000, y: 3000))
        let door = try plan.addOpening(wallID: wall, kind: .door, offset: 1000, width: 900, height: 2100)
        let item = try plan.addItem(kind: .bed, name: "Bed", position: .init(x: 2000, y: 2000),
                                   width: 1500, depth: 2000, rotationDegrees: 25)
        try plan.addItem(kind: .plant, name: "Plant", position: .init(x: 5000, y: 5000), width: 300, depth: 300)
        let originalOpening = plan.openings[0]
        let untouched = plan.items[1]

        try plan.translateSelection(.init(wallIDs: [wall], openingIDs: [door], itemIDs: [item]),
                                    by: .init(x: 400, y: -200))

        XCTAssertEqual(plan.walls[0].start, .init(x: 400, y: -200))
        XCTAssertEqual(plan.walls[0].end, .init(x: 4400, y: -200))
        XCTAssertEqual(plan.walls[1].start, plan.walls[0].end)
        XCTAssertEqual(plan.walls[1].end, .init(x: 4000, y: 3000))
        XCTAssertEqual(plan.openings[0], originalOpening)
        XCTAssertEqual(plan.items[0].position, .init(x: 2400, y: 1800))
        XCTAssertEqual(plan.items[0].rotationDegrees, 25)
        XCTAssertEqual(plan.items[1], untouched)
    }

    func testItemOnlyMoveAndAmbiguousOpeningTargetAreAtomic() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 4000, y: 0))
        let target = try plan.addWall(from: .init(x: 6000, y: 0), to: .init(x: 6000, y: 4000))
        let door = try plan.addOpening(wallID: wall, kind: .door, offset: 1000, width: 900, height: 2100)
        let item = try plan.addItem(kind: .desk, name: "Desk", position: .init(x: 1500, y: 2000), width: 1200, depth: 600)
        let walls = plan.walls
        try plan.translateSelection(.init(itemIDs: [item]), by: .init(x: 200, y: 300))
        XCTAssertEqual(plan.items[0].position, .init(x: 1700, y: 2300))
        XCTAssertEqual(plan.walls, walls)
        let before = plan

        XCTAssertThrowsError(try plan.translateSelection(.init(openingIDs: [door], itemIDs: [item]),
                                                        by: .init(x: 4500, y: 1000), targetWallID: target)) {
            XCTAssertEqual($0 as? SelectionTranslationError, .ambiguousDestinationWall)
        }
        XCTAssertThrowsError(try plan.translateSelection(.init(itemIDs: [item]), by: .init(x: 10_000_000, y: 0))) {
            XCTAssertEqual($0 as? PlanError, .invalidCoordinate)
        }
        XCTAssertEqual(plan, before)
    }

    func testLockedFloorGuardsItemTransformsAndDuplicateHasIndependentItemIDs() throws {
        let item = PlanItem(name: "Upstairs sofa", kind: .sofa, position: .init(x: 1000, y: 2000),
                            width: 2200, depth: 900, rotationDegrees: 45)
        var document = PlanDocument(plan: FloorPlan(items: [item]))
        let originalID = document.activeLayerID
        try document.setLayerLocked(id: originalID, locked: true)
        let locked = document
        XCTAssertThrowsError(try document.editActivePlan {
            try $0.translateSelection(.init(itemIDs: [item.id]), by: .init(x: 100, y: 100))
        }) {
            XCTAssertEqual($0 as? PlanDocumentError, .lockedLayer)
        }
        XCTAssertEqual(document, locked)

        let duplicateID = try document.duplicateLayer(id: originalID)
        let copy = try XCTUnwrap(document.activeLayer.plan.items.first)
        XCTAssertNotEqual(copy.id, item.id)
        var expected = item
        expected.id = copy.id
        XCTAssertEqual(copy, expected)
        XCTAssertEqual(document.activeLayerID, duplicateID)
        try document.editActivePlan {
            try $0.translateSelection(.init(itemIDs: [copy.id]), by: .init(x: 500, y: -500))
        }
        XCTAssertEqual(document.layers[0].plan.items, [item])
        XCTAssertEqual(document.activeLayer.plan.items[0].position, .init(x: 1500, y: 1500))
        XCTAssertEqual(try JSONDecoder().decode(PlanDocument.self, from: JSONEncoder().encode(document)), document)
    }
}
