import Foundation

/// Display preferences never change the millimetres stored in a floor plan.
public enum MeasurementUnit: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case metric = "Millimetres"
    case imperial = "Feet & inches"

    public var id: String { rawValue }

    public func format(_ mm: Double) -> String {
        guard mm.isFinite else { return "—" }
        switch self {
        case .metric:
            return Self.decimal(mm, places: 3) + " mm"
        case .imperial:
            // Round the whole measurement before splitting feet and inches so
            // an inch value of 11.9999 carries into the next foot correctly.
            let thousandths = abs(mm) / 25.4 * 1000
            guard thousandths.isFinite else { return "—" }
            let inches = thousandths.rounded() / 1000
            let feet = floor(inches / 12)
            let remainder = inches - feet * 12
            let sign = mm < 0 && inches > 0 ? "−" : ""
            let inchText = Self.decimal(remainder, places: 3) + "\""
            return feet > 0 ? sign + Self.decimal(feet, places: 0) + "' " + inchText : sign + inchText
        }
    }

    /// Editable text keeps nine decimal places in the active unit, avoiding the
    /// lower precision used for compact drawing annotations.
    public func inputString(_ mm: Double) -> String {
        guard mm.isFinite else { return "" }
        switch self {
        case .metric:
            return Self.decimal(mm, places: 9)
        case .imperial:
            return Self.decimal(mm / 25.4, places: 9) + "\""
        }
    }

    /// Imperial bare numbers are inches; metric bare numbers are millimetres.
    /// Explicit mm, ft/' and in/\" units work in either display preference.
    public func parse(_ text: String) throws -> Double {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "′", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "″", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
        var sign = 1.0
        if value.first == "-" || value.first == "+" {
            sign = value.first == "-" ? -1 : 1
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A sign applies to the entire dimension, never to a component.
        guard !value.isEmpty, !value.contains("-"), !value.contains("+") else { throw MeasurementError.invalidMeasurement }

        let millimetres: Double
        if value.hasSuffix("mm") {
            millimetres = try Self.number(String(value.dropLast(2)), fractions: false)
        } else {
            value = value.replacingOccurrences(of: "feet|foot|ft", with: "'", options: .regularExpression)
                .replacingOccurrences(of: "inches|inch|in", with: "\"", options: .regularExpression)
            if value.contains("'") {
                let components = value.components(separatedBy: "'")
                guard components.count == 2 else { throw MeasurementError.invalidMeasurement }
                let feet = try Self.number(components[0], fractions: true)
                var inchText = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if inchText.hasSuffix("\"") {
                    inchText.removeLast()
                    guard !inchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw MeasurementError.invalidMeasurement
                    }
                }
                let inches = inchText.isEmpty ? 0 : try Self.number(inchText, fractions: true)
                millimetres = (feet * 12 + inches) * 25.4
            } else if value.hasSuffix("\"") {
                millimetres = try Self.number(String(value.dropLast()), fractions: true) * 25.4
            } else {
                let amount = try Self.number(value, fractions: self == .imperial)
                millimetres = self == .imperial ? amount * 25.4 : amount
            }
        }
        let result = sign * millimetres
        guard result.isFinite else { throw MeasurementError.invalidMeasurement }
        return result == 0 ? 0 : result
    }

    private static func number(_ text: String, fractions: Bool) throws -> Double {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decimalPattern = #"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)"#
        let fractionPattern = #"(?:[0-9]+\s+)?[0-9]+\s*/\s*[0-9]+"#
        let pattern = fractions ? "^(?:\(decimalPattern)|\(fractionPattern))$" : "^\(decimalPattern)$"
        guard let match = text.range(of: pattern, options: .regularExpression),
              match == text.startIndex..<text.endIndex else { throw MeasurementError.invalidMeasurement }
        if text.contains("/") {
            let fraction = text.components(separatedBy: "/")
            let left = fraction[0].split(whereSeparator: { $0.isWhitespace })
            guard let last = left.last, let numerator = Double(last),
                  let denominator = Double(fraction[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  denominator > 0 else { throw MeasurementError.invalidMeasurement }
            let whole: Double
            if left.count == 2 {
                guard let parsed = Double(left[0]) else { throw MeasurementError.invalidMeasurement }
                whole = parsed
            } else {
                whole = 0
            }
            let result = whole + numerator / denominator
            guard result.isFinite else { throw MeasurementError.invalidMeasurement }
            return result
        }
        guard let result = Double(text), result.isFinite else { throw MeasurementError.invalidMeasurement }
        return result
    }

    private static func decimal(_ value: Double, places: Int) -> String {
        var result = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
        if result.contains(".") {
            while result.last == "0" { result.removeLast() }
            if result.last == "." { result.removeLast() }
        }
        return result == "-0" ? "0" : result
    }
}

public enum MeasurementError: LocalizedError {
    case invalidMeasurement

    public var errorDescription: String? {
        "Enter a measurement such as 12' 6\", 80in, 6 1/2in, or 150mm. Use one sign at the beginning for negative coordinates."
    }
}
