import Foundation

public enum PlanAreaError: LocalizedError, Equatable {
    case invalidName
    case tooFewVertices
    case invalidCoordinate
    case zeroLengthEdge
    case degenerateArea
    case selfIntersection
    case missingArea

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Name the area using 1 to 100 characters."
        case .tooFewVertices: return "Choose at least three corners to enclose an area."
        case .invalidCoordinate: return "Area corners must be finite and within 10 km of the plan origin."
        case .zeroLengthEdge: return "Each area edge must have a nonzero length."
        case .degenerateArea: return "Enclose an area of at least 1 square millimetre."
        case .selfIntersection: return "Area edges cannot cross, overlap, or touch other nonadjacent edges."
        case .missingArea: return "The selected area no longer exists."
        }
    }
}

/// An explicit 2D polygon annotation. Wall edits do not move its saved corners.
public struct PlanArea: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var vertices: [PlanPoint]

    public init(id: UUID = UUID(), name: String = "Area", vertices: [PlanPoint]) {
        self.id = id
        self.name = name
        self.vertices = vertices
    }

    public var areaSquareMillimetres: Double {
        guard vertices.count >= 3, let origin = vertices.first else { return 0 }
        // Triangulate relative to a local origin to avoid subtracting large
        // global coordinates in the shoelace sum. Compensate the accumulation.
        var sum = 0.0
        var compensation = 0.0
        for index in 1..<(vertices.count - 1) {
            let a = vertices[index]
            let b = vertices[index + 1]
            let cross = (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
            let corrected = cross - compensation
            let next = sum + corrected
            compensation = (next - sum) - corrected
            sum = next
        }
        return abs(sum) / 2
    }

    public var perimeter: Double {
        guard vertices.count >= 2 else { return 0 }
        return vertices.indices.reduce(0) { $0 + vertices[$1].distance(to: vertices[($1 + 1) % vertices.count]) }
    }

    public func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else { throw PlanAreaError.invalidName }
        guard vertices.count >= 3 else { throw PlanAreaError.tooFewVertices }
        guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10_000_000 && abs($0.y) <= 10_000_000 }) else {
            throw PlanAreaError.invalidCoordinate
        }
        let count = vertices.count
        for index in vertices.indices {
            guard vertices[index].distance(to: vertices[(index + 1) % count]) > 0 else {
                throw PlanAreaError.zeroLengthEdge
            }
        }
        guard Set(vertices).count == vertices.count else { throw PlanAreaError.selfIntersection }
        for index in vertices.indices {
            let previous = vertices[(index + count - 1) % count]
            let current = vertices[index]
            let next = vertices[(index + 1) % count]
            // Forward collinear points are useful along long walls. Reversing
            // over an adjacent edge would instead draw overlapping boundary.
            if areaOrientation(previous, current, next) == 0 {
                let dot = (current.x - previous.x) * (next.x - current.x)
                    + (current.y - previous.y) * (next.y - current.y)
                guard dot >= 0 else { throw PlanAreaError.selfIntersection }
            }
        }
        for first in vertices.indices {
            let firstEnd = (first + 1) % count
            for second in (first + 1)..<count {
                let secondEnd = (second + 1) % count
                if firstEnd == second || secondEnd == first { continue }
                if areaSegmentsIntersect(vertices[first], vertices[firstEnd], vertices[second], vertices[secondEnd]) {
                    throw PlanAreaError.selfIntersection
                }
            }
        }
        guard areaSquareMillimetres.isFinite, areaSquareMillimetres >= 1 else { throw PlanAreaError.degenerateArea }
        guard perimeter.isFinite else { throw PlanAreaError.invalidCoordinate }
    }
}

extension FloorPlan {
    @discardableResult
    public mutating func addArea(vertices: [PlanPoint], name: String? = nil) throws -> UUID {
        let names = Set(areas.map(\.name))
        var number = 1
        while names.contains("Area \(number)") { number += 1 }
        let area = PlanArea(name: (name ?? "Area \(number)").trimmingCharacters(in: .whitespacesAndNewlines),
                            vertices: areaOpenVertices(vertices))
        var candidate = self
        candidate.areas.append(area)
        try candidate.validate()
        self = candidate
        return area.id
    }

    public mutating func updateArea(id: UUID, name: String, vertices: [PlanPoint]) throws {
        guard let index = areas.firstIndex(where: { $0.id == id }) else { throw PlanAreaError.missingArea }
        var candidate = self
        candidate.areas[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.areas[index].vertices = areaOpenVertices(vertices)
        try candidate.validate()
        self = candidate
    }

    public mutating func removeArea(id: UUID) {
        areas.removeAll { $0.id == id }
    }
}

extension Geometry {
    /// Prefer the real intersections of the wall-face offset lines at joined
    /// corners. Flat wall end caps would otherwise understate exterior areas.
    public static func nearestAreaBoundaryPoint(to point: PlanPoint, walls: [Wall], tolerance: Double) -> PlanPoint? {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else { return nil }
        struct Ray {
            let wallID: UUID
            let direction: PlanPoint
            let halfThickness: Double
        }
        var rays: [PlanPoint: [Ray]] = [:]
        for wall in walls {
            guard wall.length.isFinite, wall.length > 0, wall.thickness.isFinite, wall.thickness > 0,
                  [wall.start.x, wall.start.y, wall.end.x, wall.end.y].allSatisfy(\.isFinite) else { continue }
            rays[wall.start, default: []].append(Ray(wallID: wall.id, direction: wall.direction,
                                                    halfThickness: wall.thickness / 2))
            rays[wall.end, default: []].append(Ray(wallID: wall.id,
                                                 direction: PlanPoint(x: -wall.direction.x, y: -wall.direction.y),
                                                 halfThickness: wall.thickness / 2))
        }
        var closest: PlanPoint?
        var closestDistance = tolerance
        let origins = rays.keys.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        for origin in origins {
            guard let connections = rays[origin], connections.count >= 2 else { continue }
            for first in connections.indices {
                for second in (first + 1)..<connections.count {
                    let a = connections[first]
                    let b = connections[second]
                    guard a.wallID != b.wallID else { continue }
                    let cross = a.direction.x * b.direction.y - a.direction.y * b.direction.x
                    guard abs(cross) > 0.000_000_01 else { continue }
                    for aSide in [-1.0, 1.0] {
                        let offsetA = PlanPoint(x: -a.direction.y * a.halfThickness * aSide,
                                               y: a.direction.x * a.halfThickness * aSide)
                        for bSide in [-1.0, 1.0] {
                            let offsetB = PlanPoint(x: -b.direction.y * b.halfThickness * bSide,
                                                   y: b.direction.x * b.halfThickness * bSide)
                            let dx = offsetB.x - offsetA.x
                            let dy = offsetB.y - offsetA.y
                            let alongA = (dx * b.direction.y - dy * b.direction.x) / cross
                            let alongB = (dx * a.direction.y - dy * a.direction.x) / cross
                            // Both forward rays meet at an inside corner; both
                            // backward rays meet at its exterior miter. Mixed
                            // signs identify offset crossings across the corner.
                            let epsilon = 0.000_001
                            guard (alongA >= -epsilon && alongB >= -epsilon)
                                || (alongA <= epsilon && alongB <= epsilon) else { continue }
                            let candidate = PlanPoint(x: origin.x + offsetA.x + a.direction.x * alongA,
                                                      y: origin.y + offsetA.y + a.direction.y * alongA)
                            guard candidate.x.isFinite, candidate.y.isFinite,
                                  abs(candidate.x) <= 10_000_000, abs(candidate.y) <= 10_000_000,
                                  origin.distance(to: candidate) <= 4 * max(a.halfThickness, b.halfThickness) else { continue }
                            let distance = point.distance(to: candidate)
                            if distance <= closestDistance {
                                closestDistance = distance
                                closest = candidate
                            }
                        }
                    }
                }
            }
        }
        return closest ?? nearestWallFace(to: point, walls: walls, tolerance: tolerance)
    }
}

private func areaOpenVertices(_ vertices: [PlanPoint]) -> [PlanPoint] {
    if vertices.count > 1, vertices.first == vertices.last { return Array(vertices.dropLast()) }
    return vertices
}

private func areaOrientation(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint) -> Int {
    let first = (b.x - a.x) * (c.y - a.y)
    let second = (b.y - a.y) * (c.x - a.x)
    let cross = first - second
    let uncertainty = Double.ulpOfOne * 32 * max(1, abs(first) + abs(second))
    if abs(cross) <= uncertainty { return 0 }
    return cross > 0 ? 1 : -1
}

private func areaOnSegment(_ point: PlanPoint, _ a: PlanPoint, _ b: PlanPoint) -> Bool {
    let scale = [1, abs(point.x), abs(point.y), abs(a.x), abs(a.y), abs(b.x), abs(b.y)].max() ?? 1
    let uncertainty = Double.ulpOfOne * 32 * scale
    return point.x >= min(a.x, b.x) - uncertainty && point.x <= max(a.x, b.x) + uncertainty
        && point.y >= min(a.y, b.y) - uncertainty && point.y <= max(a.y, b.y) + uncertainty
}

private func areaSegmentsIntersect(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint, _ d: PlanPoint) -> Bool {
    let first = areaOrientation(a, b, c)
    let second = areaOrientation(a, b, d)
    let third = areaOrientation(c, d, a)
    let fourth = areaOrientation(c, d, b)
    if first * second < 0 && third * fourth < 0 { return true }
    if first == 0 && areaOnSegment(c, a, b) { return true }
    if second == 0 && areaOnSegment(d, a, b) { return true }
    if third == 0 && areaOnSegment(a, c, d) { return true }
    if fourth == 0 && areaOnSegment(b, c, d) { return true }
    return false
}
