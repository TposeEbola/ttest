import Foundation

public enum Geometry {
    /// Prefer an existing junction within the tolerance; otherwise use the grid.
    public static func snap(point: PlanPoint, to endpoints: [PlanPoint], grid: Double, tolerance: Double) -> PlanPoint {
        if tolerance.isFinite, tolerance >= 0,
           let closest = endpoints.min(by: { point.distance(to: $0) < point.distance(to: $1) }),
           point.distance(to: closest) <= tolerance {
            return closest
        }
        guard grid.isFinite, grid > 0 else { return point }
        return PlanPoint(x: (point.x / grid).rounded() * grid, y: (point.y / grid).rounded() * grid)
    }

    /// The distance along the segment to its closest point, clamped to its ends.
    public static func projectedDistance(of point: PlanPoint, onto wall: Wall) -> Double {
        let length = wall.length
        guard length > 0 else { return 0 }
        let unit = wall.direction
        let projection = (point.x - wall.start.x) * unit.x + (point.y - wall.start.y) * unit.y
        return min(length, max(0, projection))
    }

    public static func distance(from point: PlanPoint, to wall: Wall) -> Double {
        point.distance(to: wall.point(at: projectedDistance(of: point, onto: wall)))
    }

    /// Fill the exterior corner between two walls drawn with flat end caps.
    /// Junctions with three or more branches retain their overlapping wall bodies;
    /// very acute two-wall junctions use a bevel instead of an unbounded miter.
    public static func junctionPatches(for walls: [Wall]) -> [[PlanPoint]] {
        struct Ray {
            let wallID: UUID
            let direction: PlanPoint
            let halfThickness: Double
        }
        var junctions: [PlanPoint: [Ray]] = [:]
        for wall in walls {
            guard wall.length.isFinite, wall.length > 0,
                  wall.thickness.isFinite, wall.thickness > 0,
                  wall.start.x.isFinite, wall.start.y.isFinite,
                  wall.end.x.isFinite, wall.end.y.isFinite else { continue }
            let direction = wall.direction
            junctions[wall.start, default: []].append(Ray(
                wallID: wall.id, direction: direction, halfThickness: wall.thickness / 2
            ))
            junctions[wall.end, default: []].append(Ray(
                wallID: wall.id, direction: PlanPoint(x: -direction.x, y: -direction.y),
                halfThickness: wall.thickness / 2
            ))
        }
        // Stable order also keeps exported documents reproducible.
        let origins = junctions.keys.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        return origins.compactMap { origin in
            guard let rays = junctions[origin], rays.count == 2,
                  rays[0].wallID != rays[1].wallID else { return nil }
            let first = rays[0]
            let second = rays[1]
            let cross = first.direction.x * second.direction.y - first.direction.y * second.direction.x
            guard abs(cross) > 0.000_000_01 else { return nil }
            let sign = cross > 0 ? 1.0 : -1.0
            let a = PlanPoint(
                x: origin.x + first.direction.y * first.halfThickness * sign,
                y: origin.y - first.direction.x * first.halfThickness * sign
            )
            let b = PlanPoint(
                x: origin.x - second.direction.y * second.halfThickness * sign,
                y: origin.y + second.direction.x * second.halfThickness * sign
            )
            let t = ((b.x - a.x) * second.direction.y - (b.y - a.y) * second.direction.x) / cross
            let miter = PlanPoint(x: a.x + t * first.direction.x, y: a.y + t * first.direction.y)
            guard miter.x.isFinite, miter.y.isFinite,
                  origin.distance(to: miter) <= 4 * max(first.halfThickness, second.halfThickness) else {
                return [origin, a, b]
            }
            return [origin, a, miter, b]
        }
    }
}
