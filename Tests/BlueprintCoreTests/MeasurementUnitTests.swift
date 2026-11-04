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
}
