import Foundation

/// A saved point-to-point dimension in model millimetres. Endpoints do not
/// automatically move with walls, so annotations remain explicit measurements.
public struct PlanDimension: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: PlanPoint
    public var end: PlanPoint
    /// Signed distance from the measured anchors to the dimension line, in millimetres.
    public var offset: Double

    public init(id: UUID = UUID(), start: PlanPoint, end: PlanPoint, offset: Double = 0) {
        self.id = id
        self.start = start
        self.end = end
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, offset
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        start = try values.decode(PlanPoint.self, forKey: .start)
        end = try values.decode(PlanPoint.self, forKey: .end)
        offset = try values.decodeIfPresent(Double.self, forKey: .offset) ?? 0
    }

    public var length: Double { start.distance(to: end) }

    public var lineStart: PlanPoint { shifted(start) }
    public var lineEnd: PlanPoint { shifted(end) }
    public var labelAngleDegrees: Double { Geometry.readableDimensionAngle(from: start, to: end) }

    /// Projects a pointer onto the normal (-dy, dx), so moving along the
    /// measured segment does not change the dimension line's offset.
    public func projectedOffset(toward point: PlanPoint) -> Double {
        let normal = unitNormal
        return (point.x - start.x) * normal.x + (point.y - start.y) * normal.y
    }

    private var unitNormal: PlanPoint {
        let distance = length
        guard distance.isFinite, distance > 0 else { return .init(x: 0, y: 0) }
        return .init(x: -(end.y - start.y) / distance, y: (end.x - start.x) / distance)
    }

    private func shifted(_ point: PlanPoint) -> PlanPoint {
        let normal = unitNormal
        return .init(x: point.x + normal.x * offset, y: point.y + normal.y * offset)
    }
}

extension FloorPlan {
    @discardableResult
    public mutating func addDimension(from start: PlanPoint, to end: PlanPoint, offset: Double = 0) throws -> UUID {
        let dimension = PlanDimension(start: start, end: end, offset: offset)
        var candidate = self
        candidate.dimensions.append(dimension)
        try candidate.validate()
        self = candidate
        return dimension.id
    }

    public mutating func updateDimension(id: UUID, start: PlanPoint, end: PlanPoint, offset: Double? = nil) throws {
        guard let index = dimensions.firstIndex(where: { $0.id == id }) else { throw PlanError.missingDimension }
        var candidate = self
        candidate.dimensions[index].start = start
        candidate.dimensions[index].end = end
        if let offset { candidate.dimensions[index].offset = offset }
        try candidate.validate()
        self = candidate
    }

    public mutating func removeDimension(id: UUID) {
        dimensions.removeAll { $0.id == id }
    }

    public mutating func updateDoor(id: UUID, swingDegrees: Double, hingeAtEnd: Bool) throws {
        guard let index = openings.firstIndex(where: { $0.id == id }) else { throw PlanError.missingOpening }
        guard openings[index].kind == .door else { throw PlanError.notADoor }
        var candidate = self
        candidate.openings[index].doorSwingDegrees = swingDegrees
        candidate.openings[index].hingeAtEnd = hingeAtEnd
        try candidate.validate()
        self = candidate
    }
}

extension Geometry {
    /// An upright dimension label angle in [-90, 90). Vertical labels always
    /// read bottom to top, regardless of which anchor was placed first.
    public static func readableDimensionAngle(from start: PlanPoint, to end: PlanPoint) -> Double {
        let angle = atan2(end.y - start.y, end.x - start.x) * 180 / .pi
        if angle >= 90 { return angle - 180 }
        if angle < -90 { return angle + 180 }
        return angle
    }

    /// The nearest point on a wall's two long faces, within model-space tolerance.
    /// This targets the actual room-side surface instead of the wall centre line.
    public static func nearestWallFace(to point: PlanPoint, walls: [Wall], tolerance: Double) -> PlanPoint? {
        guard point.x.isFinite, point.y.isFinite,
              tolerance.isFinite, tolerance >= 0 else { return nil }
        var closest: PlanPoint?
        var closestDistance = tolerance
        for wall in walls {
            guard wall.length.isFinite, wall.length > 0,
                  wall.thickness.isFinite, wall.thickness > 0,
                  [wall.start.x, wall.start.y, wall.end.x, wall.end.y].allSatisfy(\.isFinite) else { continue }
            let direction = wall.direction
            let projection = (point.x - wall.start.x) * direction.x + (point.y - wall.start.y) * direction.y
            let along = min(wall.length, max(0, projection))
            for side in [-1.0, 1.0] {
                let candidate = PlanPoint(
                    x: wall.start.x + direction.x * along - direction.y * wall.thickness / 2 * side,
                    y: wall.start.y + direction.y * along + direction.x * wall.thickness / 2 * side
                )
                let distance = point.distance(to: candidate)
                if distance <= closestDistance {
                    closest = candidate
                    closestDistance = distance
                }
            }
        }
        return closest
    }
}
