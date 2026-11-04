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

    func testDoorLeafAndArcFollowSignedSwingAndHinge() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 6000, y: 0), thickness: 200)
        let door = try plan.addOpening(wallID: wall, kind: .door, offset: 1000, width: 900, height: 2100)

        try plan.updateDoor(id: door, swingDegrees: -90, hingeAtEnd: false)
        let outward = try plan.svg()
        XCTAssertTrue(outward.contains("class=\"door-leaf\" transform=\"translate(0 100)\""))
        XCTAssertTrue(outward.contains("M 0 0 L 0 -900 M 900 0 A 900 900 0 0 0 0 -900"))

        try plan.updateDoor(id: door, swingDegrees: -90, hingeAtEnd: true)
        let oppositeHinge = try plan.svg()
        XCTAssertTrue(oppositeHinge.contains("class=\"door-leaf\" transform=\"translate(900 100)\""))
        XCTAssertTrue(oppositeHinge.contains("M 0 0 L 0 900 M -900 0 A 900 900 0 0 0 0 900"))
        XCTAssertTrue(XMLParser(data: Data(oppositeHinge.utf8)).parse())

        try plan.updateDoor(id: door, swingDegrees: 0, hingeAtEnd: false)
        let closed = try plan.svg()
        XCTAssertTrue(closed.contains("d=\"M 0 0 L 900 0\""))
        XCTAssertFalse(closed.contains(" A 900 900 "), "A closed door has no visible swing arc")
    }

    func testUserMeasurementsExportExactRoomSpanAndRemainInsideViewBox() throws {
        var plan = FloorPlan.empty
        try plan.addDimension(from: .init(x: 10_000, y: 20_000), to: .init(x: 13_500, y: 20_000))
        let svg = try plan.svg()
        XCTAssertTrue(svg.contains("class=\"measurement\""))
        XCTAssertTrue(svg.contains("class=\"measurement-label\""))
        XCTAssertTrue(svg.contains("3500 mm</text>"))
        XCTAssertTrue(svg.contains("viewBox=\"9500 19500 4500 1000\""), "Measurement-only plans should frame their annotations, without pulling in the origin")
        XCTAssertTrue(svg.contains("M 10000 20000 L 13500 20000"))
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    func testAreaExportShowsInsideSquareFootageAndEscapesRoomName() throws {
        var plan = FloorPlan.empty
        try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 6096, y: 0), thickness: 152.4)
        plan.areas = [PlanArea(name: "Kitchen & Dining <East> \"A\" 'B'", vertices: [
            .init(x: 76.2, y: 76.2), .init(x: 6019.8, y: 76.2),
            .init(x: 6019.8, y: 4495.8), .init(x: 76.2, y: 4495.8)
        ])]
        let svg = try plan.svg()
        XCTAssertTrue(svg.contains("282.75 sq ft</tspan>"))
        XCTAssertTrue(svg.contains("Kitchen &amp; Dining &lt;East&gt; &quot;A&quot; &apos;B&apos;"))
        XCTAssertTrue(svg.contains("area labels: square feet (sq ft)"))
        XCTAssertTrue(svg.contains("fill-opacity=\"0.035\""))
        let areaIndex = try XCTUnwrap(svg.range(of: "class=\"area-boundary\""))
        let wallIndex = try XCTUnwrap(svg.range(of: "class=\"wall\""))
        XCTAssertLessThan(areaIndex.lowerBound, wallIndex.lowerBound, "Room fills must remain underneath walls")
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    func testAreaOnlyExportFramesPolygonAndPreservesAreaForEitherWinding() throws {
        let vertices = [
            PlanPoint(x: 10_000, y: 20_000), .init(x: 14_000, y: 20_000),
            .init(x: 14_000, y: 23_000), .init(x: 10_000, y: 23_000)
        ]
        for polygon in [vertices, Array(vertices.reversed())] {
            var plan = FloorPlan.empty
            let area = PlanArea(name: "Studio", vertices: polygon)
            plan.areas = [area]
            let svg = try plan.svg()
            XCTAssertEqual(MeasurementUnit.metric.formatArea(area.areaSquareMillimetres), "12 m²")
            XCTAssertTrue(svg.contains("viewBox=\"9500 19500 5000 4000\""))
            XCTAssertTrue(svg.contains("129.167 sq ft</tspan>"))
            XCTAssertTrue(svg.contains("class=\"area-label\" x=\"12000\" y=\"21500\""))
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
        }
    }
}
