import Foundation

public enum ObjectCategory: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case bedroom = "Bedroom"
    case bathroom = "Bathroom"
    case miscellaneous = "Miscellaneous"
    case kitchen = "Kitchen"
    case character = "Character"
    case lights = "Lights"
    case office = "Office"
    case livingRoom = "Living Room"
    case staircase = "Staircase"
    case shapes = "Shapes"

    public var id: String { rawValue }
}

public enum PlanItemKind: String, CaseIterable, Codable, Hashable, Sendable {
    case bed, nightstand, dresser, wardrobe
    case toilet, bathSink, bathtub, shower
    case storage, plant, rug, car
    case kitchenSink, stove, refrigerator, counter, diningTable
    case person, child, wheelchair
    case ceilingLight, wallLight, floorLamp
    case desk, officeChair, bookcase
    case sofa, armchair, coffeeTable, television
    case straightStairs, spiralStairs
    case rectangle, circle, ellipse, triangle, line

    public var category: ObjectCategory {
        switch self {
        case .bed, .nightstand, .dresser, .wardrobe: return .bedroom
        case .toilet, .bathSink, .bathtub, .shower: return .bathroom
        case .storage, .plant, .rug, .car: return .miscellaneous
        case .kitchenSink, .stove, .refrigerator, .counter, .diningTable: return .kitchen
        case .person, .child, .wheelchair: return .character
        case .ceilingLight, .wallLight, .floorLamp: return .lights
        case .desk, .officeChair, .bookcase: return .office
        case .sofa, .armchair, .coffeeTable, .television: return .livingRoom
        case .straightStairs, .spiralStairs: return .staircase
        case .rectangle, .circle, .ellipse, .triangle, .line: return .shapes
        }
    }
}

/// A measured top-down symbol. Dimensions and the centre position are stored in millimetres.
public struct PlanItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: PlanItemKind
    public var position: PlanPoint
    public var width: Double
    public var depth: Double
    public var rotationDegrees: Double

    public init(
        id: UUID = UUID(), name: String, kind: PlanItemKind, position: PlanPoint,
        width: Double, depth: Double, rotationDegrees: Double = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.position = position
        self.width = width
        self.depth = depth
        self.rotationDegrees = rotationDegrees
    }

    public var isCircular: Bool { kind == .circle || kind == .spiralStairs }

    /// Corners of the rotated footprint, also useful as conservative bounds for curved symbols.
    public var corners: [PlanPoint] {
        let radians = rotationDegrees.truncatingRemainder(dividingBy: 360) * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return [
            PlanPoint(x: -width / 2, y: -depth / 2),
            PlanPoint(x: width / 2, y: -depth / 2),
            PlanPoint(x: width / 2, y: depth / 2),
            PlanPoint(x: -width / 2, y: depth / 2)
        ].map { point in
            PlanPoint(
                x: position.x + point.x * cosine - point.y * sine,
                y: position.y + point.x * sine + point.y * cosine
            )
        }
    }

    public func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else { throw PlanItemError.invalidName }
        guard width.isFinite, depth.isFinite,
              (1...1_000_000).contains(width), (1...1_000_000).contains(depth) else {
            throw PlanItemError.invalidSize
        }
        guard rotationDegrees.isFinite else { throw PlanItemError.invalidRotation }
        guard !isCircular || abs(width - depth) <= 0.000_001 else {
            throw PlanItemError.circularDimensions
        }
        for point in [position] + corners {
            guard point.x.isFinite, point.y.isFinite,
                  abs(point.x) <= 10_000_000, abs(point.y) <= 10_000_000 else {
                throw PlanError.invalidCoordinate
            }
        }
    }
}

public enum PlanItemError: LocalizedError, Equatable {
    case missingItem
    case invalidName
    case invalidSize
    case invalidRotation
    case circularDimensions

    public var errorDescription: String? {
        switch self {
        case .missingItem: return "The selected object or shape no longer exists."
        case .invalidName: return "Enter an object name between 1 and 100 characters."
        case .invalidSize: return "Object dimensions must be finite and between 1 and 1,000,000 mm."
        case .invalidRotation: return "Enter a finite rotation angle."
        case .circularDimensions: return "Circles and spiral staircases must have equal width and depth."
        }
    }
}

extension FloorPlan {
    @discardableResult
    public mutating func addItem(
        kind: PlanItemKind, name: String, position: PlanPoint,
        width: Double, depth: Double, rotationDegrees: Double = 0
    ) throws -> UUID {
        let item = PlanItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, position: position,
            width: width, depth: depth, rotationDegrees: rotationDegrees
        )
        var candidate = self
        candidate.items.append(item)
        try candidate.validate()
        self = candidate
        return item.id
    }

    public mutating func updateItem(
        id: UUID, name: String, position: PlanPoint,
        width: Double, depth: Double, rotationDegrees: Double
    ) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw PlanItemError.missingItem }
        var candidate = self
        candidate.items[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.items[index].position = position
        candidate.items[index].width = width
        candidate.items[index].depth = depth
        candidate.items[index].rotationDegrees = rotationDegrees
        try candidate.validate()
        self = candidate
    }

    public mutating func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }
}
