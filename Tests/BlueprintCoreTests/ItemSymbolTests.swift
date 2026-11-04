import XCTest
import FoundationXML
@testable import BlueprintCore

final class ItemSymbolTests: XCTestCase {
    func testEveryCatalogKindHasFiniteGeometryInsideItsMeasuredFootprint() {
        for kind in PlanItemKind.allCases {
            let primitives = ItemSymbols.primitives(for: kind)
            XCTAssertFalse(primitives.isEmpty, "\(kind) needs a visible symbol")
            for primitive in primitives {
                switch primitive {
                case let .polyline(points, closed):
                    XCTAssertGreaterThanOrEqual(points.count, closed ? 3 : 2, "\(kind)")
                    for point in points {
                        assertWithinFootprint(point, kind: kind)
                    }
                case let .ellipse(center, width, depth):
                    XCTAssertTrue(width.isFinite && width > 0, "\(kind)")
                    XCTAssertTrue(depth.isFinite && depth > 0, "\(kind)")
                    assertWithinFootprint(.init(x: center.x - width / 2, y: center.y - depth / 2), kind: kind)
                    assertWithinFootprint(.init(x: center.x + width / 2, y: center.y + depth / 2), kind: kind)
                }
            }
        }
    }

    func testBasicShapesUseTheirExactNormalizedMeasurements() throws {
        let rectangle = try XCTUnwrap(ItemSymbols.primitives(for: .rectangle).first)
        XCTAssertEqual(rectangle, .polyline(points: [
            .init(x: -0.5, y: -0.5), .init(x: 0.5, y: -0.5),
            .init(x: 0.5, y: 0.5), .init(x: -0.5, y: 0.5)
        ], closed: true))
        let ellipse = ItemPrimitive.ellipse(center: .init(x: 0, y: 0), width: 1, depth: 1)
        XCTAssertEqual(ItemSymbols.primitives(for: .circle), [ellipse])
        XCTAssertEqual(ItemSymbols.primitives(for: .ellipse), [ellipse])
        XCTAssertEqual(ItemSymbols.primitives(for: .triangle), [.polyline(points: [
            .init(x: 0, y: -0.5), .init(x: 0.5, y: 0.5), .init(x: -0.5, y: 0.5)
        ], closed: true)])
        XCTAssertEqual(ItemSymbols.primitives(for: .line), [.polyline(points: [
            .init(x: -0.5, y: 0), .init(x: 0.5, y: 0)
        ], closed: false)])
    }

    func testStraightStairsHaveTreadsAndADirectionArrow() {
        let paths = ItemSymbols.primitives(for: .straightStairs).compactMap { primitive -> [PlanPoint]? in
            guard case let .polyline(points, false) = primitive else { return nil }
            return points
        }
        let treads = paths.filter {
            $0.count == 2 && $0[0].x == -0.5 && $0[1].x == 0.5 && $0[0].y == $0[1].y
        }
        XCTAssertGreaterThanOrEqual(treads.count, 10)
        let shaft = paths.first { $0.count == 2 && $0[0].x == 0 && $0[1].x == 0 }
        XCTAssertNotNil(shaft)
        XCTAssertTrue(paths.contains { $0.count == 3 && $0[1].y < $0[0].y && $0[1].y < $0[2].y },
                      "The arrowhead should show the upward travel direction")
    }

    func testSpiralStairsHaveRadialTreadsInsideTheirCircularFootprint() {
        let primitives = ItemSymbols.primitives(for: .spiralStairs)
        XCTAssertTrue(primitives.contains(.ellipse(center: .init(x: 0, y: 0), width: 1, depth: 1)))
        let radialTreads = primitives.compactMap { primitive -> [PlanPoint]? in
            guard case let .polyline(points, false) = primitive, points.count == 2 else { return nil }
            return points
        }
        XCTAssertGreaterThanOrEqual(radialTreads.count, 10)
        for points in radialTreads {
            XCTAssertEqual(hypot(points[1].x, points[1].y), 0.5, accuracy: 0.000_001)
        }
    }

    func testItemOnlySVGFramesRotatedDimensionsAndEscapesItsUserName() throws {
        let item = PlanItem(name: "Desk & <Chair> \"A\" 'B'\u{0}", kind: .rectangle,
                            position: .init(x: 10_000, y: 20_000), width: 600, depth: 1200,
                            rotationDegrees: 90)
        let svg = try FloorPlan(items: [item]).svg()
        XCTAssertTrue(svg.contains("viewBox=\"8900 19200 2200 1600\""),
                      "An item-only drawing should include its rotated footprint without pulling in the origin")
        XCTAssertTrue(svg.contains("class=\"plan-item\" data-kind=\"rectangle\" transform=\"translate(10000 20000) rotate(90)\""))
        XCTAssertTrue(svg.contains("d=\"M -300 -600 L 300 -600 L 300 600 L -300 600 Z\""))
        XCTAssertTrue(svg.contains("<title>Desk &amp; &lt;Chair&gt; &quot;A&quot; &apos;B&apos;</title>"))
        XCTAssertFalse(svg.contains("class=\"measurement-label\""), "Object measurements are placement previews, not automatic drawing annotations")
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    func testSVGPreservesEllipseRadiiAndLineLengthInMillimetres() throws {
        let ellipse = PlanItem(name: "Oval", kind: .ellipse, position: .init(x: 0, y: 0),
                               width: 1200, depth: 600)
        let line = PlanItem(name: "Line", kind: .line, position: .init(x: 0, y: 1500),
                            width: 800, depth: 1, rotationDegrees: 30)
        let svg = try FloorPlan(items: [ellipse, line]).svg()
        XCTAssertTrue(svg.contains("<ellipse cx=\"0\" cy=\"0\" rx=\"600\" ry=\"300\"/>"))
        XCTAssertTrue(svg.contains("d=\"M -400 0 L 400 0\""))
        XCTAssertTrue(svg.contains("transform=\"translate(0 1500) rotate(30)\""))
        XCTAssertFalse(svg.contains(" scale("), "Physical dimensions must not scale the symbol's line weight")
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    func testItemsExportAfterOpeningsAndBeforeUserDimensions() throws {
        var plan = FloorPlan.empty
        let wall = try plan.addWall(from: .init(x: 0, y: 0), to: .init(x: 6000, y: 0))
        try plan.addOpening(wallID: wall, kind: .door, offset: 1500, width: 900, height: 2100)
        try plan.addItem(kind: .bed, name: "Queen bed", position: .init(x: 2000, y: 2000), width: 1524, depth: 2032)
        try plan.addDimension(from: .init(x: 0, y: 1000), to: .init(x: 6000, y: 1000))
        let svg = try plan.svg()
        let opening = try XCTUnwrap(svg.range(of: "class=\"door-leaf\""))
        let item = try XCTUnwrap(svg.range(of: "class=\"plan-item\""))
        let measurement = try XCTUnwrap(svg.range(of: "class=\"measurement\""))
        XCTAssertLessThan(opening.lowerBound, item.lowerBound)
        XCTAssertLessThan(item.lowerBound, measurement.lowerBound)
    }

    func testEveryKindExportsAsValidXMLWithItsOwnSymbol() throws {
        for kind in PlanItemKind.allCases {
            let item = PlanItem(name: kind.rawValue, kind: kind, position: .init(x: 0, y: 0),
                                width: 900, depth: 900, rotationDegrees: 25)
            let svg = try FloorPlan(items: [item]).svg()
            XCTAssertTrue(svg.contains("data-kind=\"\(kind.rawValue)\""))
            XCTAssertTrue(svg.contains("<path ") || svg.contains("<ellipse "), "\(kind)")
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(), "\(kind)")
        }
    }

    private func assertWithinFootprint(_ point: PlanPoint, kind: PlanItemKind,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(point.x.isFinite && point.y.isFinite, "\(kind)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(point.x), 0.500_000_001, "\(kind) x", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(point.y), 0.500_000_001, "\(kind) y", file: file, line: line)
    }
}
