import Foundation

/// A saved point-to-point dimension in model millimetres. Endpoints do not
/// automatically move with walls, so annotations remain explicit measurements.
public struct PlanDimension: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: PlanPoint
    public var end: PlanPoint

    public init(id: UUID = UUID(), start: PlanPoint, end: PlanPoint) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var length: Double { start.distance(to: end) }
}

extension FloorPlan {
    @discardableResult
    public mutating func addDimension(from start: PlanPoint, to end: PlanPoint) throws -> UUID {
        let dimension = PlanDimension(start: start, end: end)
        var candidate = self
        candidate.dimensions.append(dimension)
        try candidate.validate()
        self = candidate
        return dimension.id
    }

    public mutating func updateDimension(id: UUID, start: PlanPoint, end: PlanPoint) throws {
        guard let index = dimensions.firstIndex(where: { $0.id == id }) else { throw PlanError.missingDimension }
        var candidate = self
        candidate.dimensions[index].start = start
        candidate.dimensions[index].end = end
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
