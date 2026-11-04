import XCTest
import FoundationXML
@testable import BlueprintCore

final class SVGExportTests: XCTestCase {
    func testExportPreservesGeometryAndStatesPrintScale() throws {
        var plan = FloorPlan.empty
        try plan.addWall(from: PlanPoint(x: -1000, y: 0), to: PlanPoint(x: 3000, y: 0), thickness: 150)
        let svg = try plan.svg()
        XCTAssertTrue(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(svg.contains("drawing scale: 1:50"))
        XCTAssertTrue(svg.contains("width=\"103mm\""))
        XCTAssertTrue(svg.contains("x1=\"-1000\""))
        XCTAssertTrue(svg.contains("x2=\"3000\""))
        XCTAssertTrue(svg.contains("stroke-width=\"150\""))
        XCTAssertTrue(svg.contains("4000 mm</text>"))
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    func testOpeningCarvesWallAndIncludesDoorAndWindowSymbols() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 6000, y: 0), thickness: 200)
        try plan.addOpening(wallID: wall, kind: .door, offset: 1000, width: 900, height: 2100)
        try plan.addOpening(wallID: wall, kind: .window, offset: 3500, width: 1200, height: 1200)
        let svg = try plan.svg()
        XCTAssertEqual(svg.components(separatedBy: "class=\"opening-cutout\"").count - 1, 2)
        XCTAssertTrue(svg.contains("class=\"door\""))
        XCTAssertTrue(svg.contains("class=\"window\""))
        XCTAssertTrue(svg.contains("A 900 900 0 0 1 0 900"))
        XCTAssertTrue(svg.contains("stroke-width=\"202\""))
        let wallIndex = try XCTUnwrap(svg.range(of: "class=\"wall\""))
        let cutIndex = try XCTUnwrap(svg.range(of: "class=\"opening-cutout\""))
        XCTAssertLessThan(wallIndex.lowerBound, cutIndex.lowerBound)
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    func testEmptyPlanExportsNonzeroBlankPage() throws {
        let svg = try FloorPlan.empty.svg()
        XCTAssertTrue(svg.contains("width=\"20mm\""))
        XCTAssertTrue(svg.contains("viewBox=\"-500 -500 1000 1000\""))
        XCTAssertFalse(svg.contains("class=\"wall\""))
        XCTAssertFalse(svg.contains("nan"))
        XCTAssertFalse(svg.contains("inf"))
    }

    func testExportRejectsInvalidCoordinatesInsteadOfEmittingInvalidXML() throws {
        var plan = FloorPlan.empty
        try plan.addWall(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 3000, y: 0), thickness: 150)
        plan.walls[0].start.x = .infinity
        XCTAssertThrowsError(try plan.svg())
    }
}
