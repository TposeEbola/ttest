import Foundation
import XCTest
@testable import BlueprintCore

final class MeasurementUnitTests: XCTestCase {
    func testCommonImperialMeasurements() throws {
        for text in ["12' 6\"", "12ft 6in", "12ft6in", "12 feet 6 inches", "12′ 6″"] {
            XCTAssertEqual(try MeasurementUnit.imperial.parse(text), 3810, accuracy: 0.000_001, text)
        }
        XCTAssertEqual(try MeasurementUnit.imperial.parse("80in"), 2032, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.imperial.parse("6 1/2in"), 165.1, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.imperial.parse("1/2\""), 12.7, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.imperial.parse("6 1 / 2 in"), 165.1, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.imperial.parse("1/2ft"), 152.4, accuracy: 0.000_001)
    }

    func testSignAppliesToEntireCoordinate() throws {
        XCTAssertEqual(try MeasurementUnit.imperial.parse("-2' 3\""), -685.8, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.imperial.parse("−0' 3\""), -76.2, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.imperial.parse("+2' 3\""), 685.8, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.metric.parse("-150 mm"), -150)
    }

    func testBareNumberAndExplicitUnitRules() throws {
        XCTAssertEqual(try MeasurementUnit.imperial.parse("10"), 254, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.metric.parse("10"), 10)
        XCTAssertEqual(try MeasurementUnit.imperial.parse("150mm"), 150)
        XCTAssertEqual(try MeasurementUnit.metric.parse("2ft 3in"), 685.8, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.metric.parse(".5"), 0.5)
    }

    func testInvalidInputIsRejected() {
        for unit in MeasurementUnit.allCases {
            for text in ["", "nan", "inf", "infinity", "1/0in", "--2", "-+2", "2' -3\"", "2' +3\"", "2ft garbage", "12foobar", "2\"\"", "2''", "1mm in", "1,000", "1e309", "2..3", "1/2/3in"] {
                XCTAssertThrowsError(try unit.parse(text), "\(unit.rawValue): \(text)")
            }
        }
    }

    func testDisplayCarriesRoundedInchesIntoNextFoot() {
        XCTAssertEqual(MeasurementUnit.imperial.format(3810), "12' 6\"")
        XCTAssertEqual(MeasurementUnit.imperial.format(11.9999 * 25.4), "1' 0\"")
        XCTAssertEqual(MeasurementUnit.imperial.format(-76.2), "−3\"")
        XCTAssertEqual(MeasurementUnit.metric.format(114.3), "114.3 mm")
        XCTAssertEqual(MeasurementUnit.imperial.format(.infinity), "—")
    }

    func testEditableValuesPreservePrecisionAcrossUnitSwitches() throws {
        for original in [0, 114.3, -685.812345678, 1_234_567.8912345, 0.000_001] {
            var value = original
            for _ in 0..<20 {
                value = try MeasurementUnit.imperial.parse(MeasurementUnit.imperial.inputString(value))
                value = try MeasurementUnit.metric.parse(MeasurementUnit.metric.inputString(value))
            }
            XCTAssertEqual(value, original, accuracy: 0.000_001)
        }
    }

    func testEditableImperialValuesShowBothFeetAndInches() throws {
        let cases: [(Double, String)] = [
            (6096, "20' 0\""),
            (3810, "12' 6\""),
            (-685.8, "-2' 3\""),
            (152.4, "0' 6\""),
            (0, "0' 0\""),
            (11.9999999999 * 25.4, "1' 0\"")
        ]
        for (millimetres, expected) in cases {
            let text = MeasurementUnit.imperial.inputString(millimetres)
            XCTAssertEqual(text, expected)
            XCTAssertEqual(try MeasurementUnit.imperial.parse(text), millimetres, accuracy: 0.000_001)
        }
        XCTAssertEqual(MeasurementUnit.metric.inputString(6096), "6096")
        XCTAssertEqual(MeasurementUnit.metric.inputString(114.3), "114.3")
    }

    func testAreaFormattingUsesPhysicalSquareUnits() {
        // A 20 ft × 15 ft centreline room with 6-inch walls has a
        // 19.5 ft × 14.5 ft interior: 282.75 square feet.
        let interiorArea = (19.5 * 304.8) * (14.5 * 304.8)
        XCTAssertEqual(MeasurementUnit.imperial.formatArea(interiorArea), "282.75 sq ft")
        XCTAssertEqual(MeasurementUnit.metric.formatArea(interiorArea), "26.268 m²")
        XCTAssertEqual(MeasurementUnit.imperial.formatArea(304.8 * 304.8), "1 sq ft")
        XCTAssertEqual(MeasurementUnit.metric.formatArea(1_000_000), "1 m²")
        XCTAssertEqual(MeasurementUnit.imperial.formatArea(1_000_000), "10.764 sq ft")
        XCTAssertEqual(MeasurementUnit.imperial.formatArea(0), "0 sq ft")
        XCTAssertEqual(MeasurementUnit.metric.formatArea(0), "0 m²")
        for invalid in [-1.0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(MeasurementUnit.imperial.formatArea(invalid), "—")
            XCTAssertEqual(MeasurementUnit.metric.formatArea(invalid), "—")
        }
    }

    func testMcChickenUsesExactlyFourInches() throws {
        XCTAssertEqual(MeasurementUnit.mcChickenMillimetres, 101.6)
        XCTAssertEqual(MeasurementUnit.mcChicken.format(try MeasurementUnit.imperial.parse("4in")), "1 McChicken")
        XCTAssertEqual(MeasurementUnit.mcChicken.format(203.2), "2 McChickens")
        XCTAssertEqual(MeasurementUnit.mcChicken.format(0), "0 McChickens")
        XCTAssertEqual(MeasurementUnit.mcChicken.format(-101.6), "-1 McChicken")
        XCTAssertEqual(MeasurementUnit.mcChicken.format(101.6 * 1.234567), "1.235 McChickens")
        XCTAssertEqual(try MeasurementUnit.mcChicken.parse("2"), 203.2, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.mcChicken.parse("-.5"), -50.8, accuracy: 0.000_001)
    }

    func testExplicitMcChickenUnitsWorkInEveryDisplayMode() throws {
        for unit in MeasurementUnit.allCases {
            for text in ["2 McChickens", "2mcchicken", "2 MCCHICKENS", "2🍔", "2 McChickens 🍔", "2McChicken🍔"] {
                XCTAssertEqual(try unit.parse(text), 203.2, accuracy: 0.000_001, "\(unit.rawValue): \(text)")
            }
            XCTAssertEqual(try unit.parse("−.5 McChicken"), -50.8, accuracy: 0.000_001)
        }
        XCTAssertEqual(try MeasurementUnit.mcChicken.parse("150mm"), 150)
        XCTAssertEqual(try MeasurementUnit.mcChicken.parse("2ft 3in"), 685.8, accuracy: 0.000_001)
        XCTAssertEqual(try MeasurementUnit.mcChicken.parse("6 1/2in"), 165.1, accuracy: 0.000_001)
    }

    func testMcChickenEditableValuesPreservePrecision() throws {
        XCTAssertEqual(MeasurementUnit.mcChicken.inputString(203.2), "2 McChickens")
        XCTAssertEqual(MeasurementUnit.mcChicken.inputString(101.6 * 1.234567891), "1.234567891 McChickens")
        for original in [0, 101.6, -685.812345678, 1_234_567.8912345, 0.000_001] {
            var value = original
            for _ in 0..<20 {
                value = try MeasurementUnit.mcChicken.parse(MeasurementUnit.mcChicken.inputString(value))
                value = try MeasurementUnit.imperial.parse(MeasurementUnit.imperial.inputString(value))
                value = try MeasurementUnit.metric.parse(MeasurementUnit.metric.inputString(value))
            }
            XCTAssertEqual(value, original, accuracy: 0.000_001)
        }
    }

    func testMcChickenAreaUsesSquaredLengthUnit() {
        let squareMcChicken = MeasurementUnit.mcChickenMillimetres * MeasurementUnit.mcChickenMillimetres
        XCTAssertEqual(MeasurementUnit.mcChicken.formatArea(squareMcChicken), "1 McChickens²")
        XCTAssertEqual(MeasurementUnit.mcChicken.formatArea(1.234567 * squareMcChicken), "1.235 McChickens²")
        XCTAssertEqual(MeasurementUnit.mcChicken.formatArea(0), "0 McChickens²")
        for invalid in [-1.0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(MeasurementUnit.mcChicken.formatArea(invalid), "—")
        }
    }

    func testMcChickenRejectsMalformedAndNonfiniteMeasurements() {
        for unit in MeasurementUnit.allCases {
            for text in ["McChicken", "🍔", "nan McChickens", "infinity🍔", "1/0 McChicken", "2 McChicken garbage", "2 McChicken McChicken", "2🍔🍔", "2mm🍔", "2ft McChicken"] {
                XCTAssertThrowsError(try unit.parse(text), "\(unit.rawValue): \(text)")
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(MeasurementUnit.mcChicken.format(invalid), "—")
            XCTAssertEqual(MeasurementUnit.mcChicken.inputString(invalid), "")
        }
    }

    func testMcChickenPreferenceIsCodableAndListed() throws {
        XCTAssertEqual(MeasurementUnit.mcChicken.rawValue, "McChickens 🍔")
        XCTAssertEqual(MeasurementUnit.allCases, [.metric, .imperial, .mcChicken])
        let saved = try JSONEncoder().encode(MeasurementUnit.mcChicken)
        XCTAssertEqual(try JSONDecoder().decode(MeasurementUnit.self, from: saved), .mcChicken)
    }
}
