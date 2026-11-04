import Foundation

public struct WallGuideResult: Equatable, Sendable {
    public var end: PlanPoint
    /// The resulting wall bearing, normalized to 0..<360 degrees.
    public var angleDegrees: Double?
    /// The resulting reference or grid length, in millimetres.
    public var matchedLength: Double?

    public init(end: PlanPoint, angleDegrees: Double? = nil, matchedLength: Double? = nil) {
        self.end = end
        self.angleDegrees = angleDegrees
        self.matchedLength = matchedLength
    }
}

extension Geometry {
    /// Snap a wall's bearing and length as one operation. References take priority
    /// over the measurement grid, and coordinates remain in model millimetres.
    public static func guidedWall(
        from start: PlanPoint,
        to proposed: PlanPoint,
        referenceWalls: [Wall],
        angleToleranceDegrees: Double = 2,
        lengthTolerance: Double,
        gridStep: Double = 0
    ) -> WallGuideResult {
        let unchanged = WallGuideResult(end: proposed)
        guard [start.x, start.y, proposed.x, proposed.y].allSatisfy({ $0.isFinite && abs($0) <= 10_000_000 }),
              angleToleranceDegrees.isFinite, angleToleranceDegrees >= 0,
              lengthTolerance.isFinite, lengthTolerance >= 0,
              gridStep.isFinite, gridStep >= 0 else { return unchanged }
        let dx = proposed.x - start.x
        let dy = proposed.y - start.y
        let length = hypot(dx, dy)
        guard length.isFinite, length > 0 else { return unchanged }

        let angle = atan2(dy, dx) * 180 / .pi
        let guidedAngle = snappedRotation(angle, toleranceDegrees: angleToleranceDegrees)
        let referenceLengths = referenceWalls.map(\.length).filter {
            $0.isFinite && $0 > 0 && $0 <= 10_000_000 && abs($0 - length) <= lengthTolerance
        }
        var guidedLength = referenceLengths.min { abs($0 - length) < abs($1 - length) }
        if guidedLength == nil, gridStep > 0 {
            let multiple = max(1, (length / gridStep).rounded())
            let gridLength = multiple * gridStep
            if gridLength.isFinite, gridLength <= 10_000_000, abs(gridLength - length) <= lengthTolerance {
                guidedLength = gridLength
            }
        }
        guard guidedAngle != nil || guidedLength != nil else { return unchanged }

        let unit = guidedAngle.map(guideUnitVector) ?? PlanPoint(x: dx / length, y: dy / length)
        let targetLength = guidedLength ?? length
        let end = PlanPoint(x: start.x + unit.x * targetLength, y: start.y + unit.y * targetLength)
        guard [end.x, end.y].allSatisfy({ $0.isFinite && abs($0) <= 10_000_000 }) else { return unchanged }
        let actualLength = start.distance(to: end)
        guard actualLength.isFinite, actualLength > 0 else { return unchanged }

        // Report only guides actually met by the final endpoint, including when
        // floating-point precision is limited by a distant plan origin.
        let actualAngle = atan2(end.y - start.y, end.x - start.x) * 180 / .pi
        let confirmedAngle = guidedAngle.flatMap { guideAngleDifference(actualAngle, $0) <= 0.000_001 ? $0 : nil }
        let confirmedLength = guidedLength.flatMap {
            abs(actualLength - $0) <= max(0.000_001, $0 * 0.000_000_000_001) ? $0 : nil
        }
        return WallGuideResult(end: end, angleDegrees: confirmedAngle, matchedLength: confirmedLength)
    }

    /// The nearest 45-degree bearing when it lies within the given tolerance.
    /// A zero tolerance permits exact multiples only; invalid values do not snap.
    public static func snappedRotation(_ degrees: Double, toleranceDegrees: Double = 2) -> Double? {
        guard degrees.isFinite, toleranceDegrees.isFinite, toleranceDegrees >= 0 else { return nil }
        let normalized = guideNormalizedDegrees(degrees)
        let nearest = guideNormalizedDegrees((normalized / 45).rounded() * 45)
        return guideAngleDifference(normalized, nearest) <= toleranceDegrees ? nearest : nil
    }
}

private func guideNormalizedDegrees(_ degrees: Double) -> Double {
    let remainder = degrees.truncatingRemainder(dividingBy: 360)
    if remainder == 0 { return 0 }
    return remainder < 0 ? remainder + 360 : remainder
}

private func guideAngleDifference(_ first: Double, _ second: Double) -> Double {
    let difference = abs(guideNormalizedDegrees(first) - guideNormalizedDegrees(second))
    return min(difference, 360 - difference)
}

private func guideUnitVector(_ degrees: Double) -> PlanPoint {
    // Exact cardinal components avoid tiny cosine errors at 90-degree angles.
    let diagonal = sqrt(0.5)
    switch degrees {
    case 0: return PlanPoint(x: 1, y: 0)
    case 45: return PlanPoint(x: diagonal, y: diagonal)
    case 90: return PlanPoint(x: 0, y: 1)
    case 135: return PlanPoint(x: -diagonal, y: diagonal)
    case 180: return PlanPoint(x: -1, y: 0)
    case 225: return PlanPoint(x: -diagonal, y: -diagonal)
    case 270: return PlanPoint(x: 0, y: -1)
    default: return PlanPoint(x: diagonal, y: -diagonal) // 315 degrees
    }
}
