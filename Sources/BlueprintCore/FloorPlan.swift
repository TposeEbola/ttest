import Foundation

/// Plan coordinates and dimensions are always stored in millimetres.
public struct PlanPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: PlanPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

public struct Wall: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: PlanPoint
    public var end: PlanPoint
    public var thickness: Double

    public init(id: UUID = UUID(), start: PlanPoint, end: PlanPoint, thickness: Double = 150) {
        self.id = id
        self.start = start
        self.end = end
        self.thickness = thickness
    }

    public var length: Double { start.distance(to: end) }

    public var direction: PlanPoint {
        guard length > 0 else { return PlanPoint(x: 0, y: 0) }
        return PlanPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
    }

    /// A point measured from the wall's start along its centreline.
    public func point(at distance: Double) -> PlanPoint {
        let unit = direction
        return PlanPoint(x: start.x + unit.x * distance, y: start.y + unit.y * distance)
    }
}

public enum OpeningKind: String, Codable, CaseIterable, Sendable {
    case door
    case window
}

public struct Opening: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var wallID: UUID
    public var kind: OpeningKind
    /// Distance from the wall's start to the opening's centre, in millimetres.
    public var offset: Double
    public var width: Double
    public var height: Double
    /// The leaf's signed rotation from its closed position along the wall.
    /// Positive and negative angles place the swing on opposite wall faces.
    public var doorSwingDegrees: Double
    public var hingeAtEnd: Bool

    public init(
        id: UUID = UUID(), wallID: UUID, kind: OpeningKind,
        offset: Double, width: Double, height: Double,
        doorSwingDegrees: Double = 90, hingeAtEnd: Bool = false
    ) {
        self.id = id
        self.wallID = wallID
        self.kind = kind
        self.offset = offset
        self.width = width
        self.height = height
        self.doorSwingDegrees = doorSwingDegrees
        self.hingeAtEnd = hingeAtEnd
    }

    private enum CodingKeys: String, CodingKey {
        case id, wallID, kind, offset, width, height, doorSwingDegrees, hingeAtEnd
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        wallID = try values.decode(UUID.self, forKey: .wallID)
        kind = try values.decode(OpeningKind.self, forKey: .kind)
        offset = try values.decode(Double.self, forKey: .offset)
        width = try values.decode(Double.self, forKey: .width)
        height = try values.decode(Double.self, forKey: .height)
        doorSwingDegrees = try values.decodeIfPresent(Double.self, forKey: .doorSwingDegrees) ?? 90
        hingeAtEnd = try values.decodeIfPresent(Bool.self, forKey: .hingeAtEnd) ?? false
    }
}

public enum PlanError: LocalizedError, Equatable {
    case invalidCoordinate
    case invalidWallLength
    case invalidThickness
    case missingWall
    case missingOpening
    case duplicateIdentifier
    case invalidOpeningDimensions
    case openingOutsideWall
    case overlappingOpenings
    case invalidDimensionLength
    case missingDimension
    case invalidDimensionOffset
    case invalidDoorAngle
    case notADoor

    public var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "Enter finite coordinates within 10 km of the plan origin."
        case .invalidWallLength:
            return "Walls must be at least 1 mm long and no longer than 10 km."
        case .invalidThickness:
            return "Wall thickness must be between 1 and 5,000 mm."
        case .missingWall:
            return "The selected wall no longer exists."
        case .missingOpening:
            return "The selected door or window no longer exists."
        case .duplicateIdentifier:
            return "This plan contains duplicate object identifiers."
        case .invalidOpeningDimensions:
            return "Door and window dimensions must be finite and between 1 and 1,000,000 mm."
        case .openingOutsideWall:
            return "The door or window must fit entirely within its wall."
        case .overlappingOpenings:
            return "Doors and windows on the same wall cannot overlap."
        case .invalidDimensionLength:
            return "Measurement lines must be at least 1 mm long and no longer than 10 km."
        case .missingDimension:
            return "The selected measurement no longer exists."
        case .invalidDimensionOffset:
            return "Enter a finite measurement-line offset."
        case .invalidDoorAngle:
            return "Enter a door swing angle between -180° and 180°."
        case .notADoor:
            return "Select a door to change its swing or hinge."
        }
    }
}

public struct FloorPlan: Codable, Equatable, Sendable {
    public var walls: [Wall]
    public var openings: [Opening]
    public var dimensions: [PlanDimension]
    public var areas: [PlanArea]
    public var defaultWallThickness: Double

    public init(walls: [Wall] = [], openings: [Opening] = [], dimensions: [PlanDimension] = [], areas: [PlanArea] = [], defaultWallThickness: Double = 150) {
        self.walls = walls
        self.openings = openings
        self.dimensions = dimensions
        self.areas = areas
        self.defaultWallThickness = defaultWallThickness
    }

    private enum CodingKeys: String, CodingKey {
        case walls, openings, dimensions, areas, defaultWallThickness
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        walls = try values.decode([Wall].self, forKey: .walls)
        openings = try values.decode([Opening].self, forKey: .openings)
        dimensions = try values.decodeIfPresent([PlanDimension].self, forKey: .dimensions) ?? []
        areas = try values.decodeIfPresent([PlanArea].self, forKey: .areas) ?? []
        defaultWallThickness = try values.decode(Double.self, forKey: .defaultWallThickness)
    }

    public static let empty = FloorPlan()

    public static var example: FloorPlan {
        let a = PlanPoint(x: 0, y: 0)
        let b = PlanPoint(x: 6096, y: 0)
        let c = PlanPoint(x: 6096, y: 4572)
        let d = PlanPoint(x: 0, y: 4572)
        let walls = [
            Wall(start: a, end: b, thickness: 152.4),
            Wall(start: b, end: c, thickness: 152.4),
            Wall(start: c, end: d, thickness: 152.4),
            Wall(start: d, end: a, thickness: 152.4)
        ]
        return FloorPlan(
            walls: walls,
            openings: [
                Opening(wallID: walls[2].id, kind: .door, offset: 4572, width: 914.4, height: 2032),
                Opening(wallID: walls[0].id, kind: .window, offset: 3048, width: 1219.2, height: 1219.2)
            ],
            defaultWallThickness: 152.4
        )
    }

    /// Validate decoded documents and edits before accepting them into the editor.
    public func validate() throws {
        try Self.validateThickness(defaultWallThickness)
        guard Set(walls.map(\.id)).count == walls.count,
              Set(openings.map(\.id)).count == openings.count,
              Set(dimensions.map(\.id)).count == dimensions.count,
              Set(areas.map(\.id)).count == areas.count,
              Set(walls.map(\.id)).isDisjoint(with: Set(openings.map(\.id))),
              Set(dimensions.map(\.id)).isDisjoint(with: Set(walls.map(\.id))),
              Set(dimensions.map(\.id)).isDisjoint(with: Set(openings.map(\.id))),
              Set(areas.map(\.id)).isDisjoint(with: Set(walls.map(\.id) + openings.map(\.id) + dimensions.map(\.id))) else {
            throw PlanError.duplicateIdentifier
        }
        for area in areas { try area.validate() }
        for dimension in dimensions {
            guard dimension.offset.isFinite else { throw PlanError.invalidDimensionOffset }
            for point in [dimension.start, dimension.end, dimension.lineStart, dimension.lineEnd] {
                guard point.x.isFinite, point.y.isFinite,
                      abs(point.x) <= 10_000_000, abs(point.y) <= 10_000_000 else {
                    throw PlanError.invalidCoordinate
                }
            }
            guard dimension.length.isFinite, (1...10_000_000).contains(dimension.length) else {
                throw PlanError.invalidDimensionLength
            }
        }
        for wall in walls {
            for point in [wall.start, wall.end] {
                guard point.x.isFinite, point.y.isFinite,
                      abs(point.x) <= 10_000_000, abs(point.y) <= 10_000_000 else {
                    throw PlanError.invalidCoordinate
                }
            }
            guard wall.length.isFinite, (1...10_000_000).contains(wall.length) else {
                throw PlanError.invalidWallLength
            }
            try Self.validateThickness(wall.thickness)
        }
        let wallByID = Dictionary(uniqueKeysWithValues: walls.map { ($0.id, $0) })
        for opening in openings {
            guard let wall = wallByID[opening.wallID] else { throw PlanError.missingWall }
            guard opening.doorSwingDegrees.isFinite, (-180...180).contains(opening.doorSwingDegrees) else {
                throw PlanError.invalidDoorAngle
            }
            guard opening.width.isFinite, opening.height.isFinite,
                  (1...1_000_000).contains(opening.width),
                  (1...1_000_000).contains(opening.height) else {
                throw PlanError.invalidOpeningDimensions
            }
            guard opening.offset.isFinite,
                  opening.offset - opening.width / 2 >= -Self.epsilon,
                  opening.offset + opening.width / 2 <= wall.length + Self.epsilon else {
                throw PlanError.openingOutsideWall
            }
        }
        let grouped = Dictionary(grouping: openings, by: \.wallID)
        for group in grouped.values {
            let ordered = group.sorted { $0.offset - $0.width / 2 < $1.offset - $1.width / 2 }
            for (previous, next) in zip(ordered, ordered.dropFirst()) {
                guard previous.offset + previous.width / 2 <= next.offset - next.width / 2 + Self.epsilon else {
                    throw PlanError.overlappingOpenings
                }
            }
        }
    }

    @discardableResult
    public mutating func addWall(from start: PlanPoint, to end: PlanPoint, thickness: Double? = nil) throws -> UUID {
        let wall = Wall(start: start, end: end, thickness: thickness ?? defaultWallThickness)
        var candidate = self
        candidate.walls.append(wall)
        try candidate.validate()
        self = candidate
        return wall.id
    }

    /// Moving a junction moves every endpoint attached to that junction.
    /// The complete edit is rejected if it would invalidate any wall or opening.
    public mutating func updateWall(id: UUID, start: PlanPoint, end: PlanPoint, thickness: Double) throws {
        guard let original = walls.first(where: { $0.id == id }) else { throw PlanError.missingWall }
        var candidate = self
        for index in candidate.walls.indices {
            let oldStart = candidate.walls[index].start
            let oldEnd = candidate.walls[index].end
            if oldStart == original.start { candidate.walls[index].start = start }
            if oldStart == original.end { candidate.walls[index].start = end }
            if oldEnd == original.start { candidate.walls[index].end = start }
            if oldEnd == original.end { candidate.walls[index].end = end }
            if candidate.walls[index].id == id { candidate.walls[index].thickness = thickness }
        }
        try candidate.validate()
        self = candidate
    }

    public mutating func removeWall(id: UUID) {
        walls.removeAll { $0.id == id }
        openings.removeAll { $0.wallID == id }
    }

    @discardableResult
    public mutating func addOpening(
        wallID: UUID, kind: OpeningKind, offset: Double, width: Double, height: Double
    ) throws -> UUID {
        let opening = Opening(wallID: wallID, kind: kind, offset: offset, width: width, height: height)
        var candidate = self
        candidate.openings.append(opening)
        try candidate.validate()
        self = candidate
        return opening.id
    }

    public mutating func updateOpening(id: UUID, offset: Double, width: Double, height: Double) throws {
        guard let index = openings.firstIndex(where: { $0.id == id }) else { throw PlanError.missingOpening }
        var candidate = self
        candidate.openings[index].offset = offset
        candidate.openings[index].width = width
        candidate.openings[index].height = height
        try candidate.validate()
        self = candidate
    }

    public mutating func removeOpening(id: UUID) {
        openings.removeAll { $0.id == id }
    }

    private static let epsilon = 0.000_001

    private static func validateThickness(_ thickness: Double) throws {
        guard thickness.isFinite, (1...5000).contains(thickness) else { throw PlanError.invalidThickness }
    }
}
