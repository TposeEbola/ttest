import Foundation

public struct ObjectPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: PlanItemKind
    public let width: Double
    public let depth: Double

    public init(id: String, name: String, kind: PlanItemKind, width: Double, depth: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.width = width
        self.depth = depth
    }

    public var category: ObjectCategory { kind.category }
}

/// Common planning footprints, not installation clearances or manufacturer specifications.
public enum ObjectCatalog {
    public static func presets(for category: ObjectCategory) -> [ObjectPreset] {
        switch category {
        case .bedroom:
            return [
                .init(id: "bedroom.twin-bed", name: "Twin bed", kind: .bed, width: 965.2, depth: 1905),
                .init(id: "bedroom.queen-bed", name: "Queen bed", kind: .bed, width: 1524, depth: 2032),
                .init(id: "bedroom.king-bed", name: "King bed", kind: .bed, width: 1930.4, depth: 2032),
                .init(id: "bedroom.nightstand", name: "Nightstand", kind: .nightstand, width: 508, depth: 457.2),
                .init(id: "bedroom.dresser", name: "Dresser", kind: .dresser, width: 1524, depth: 508),
                .init(id: "bedroom.wardrobe", name: "Wardrobe", kind: .wardrobe, width: 1524, depth: 609.6)
            ]
        case .bathroom:
            return [
                .init(id: "bathroom.toilet", name: "Toilet", kind: .toilet, width: 508, depth: 762),
                .init(id: "bathroom.sink", name: "Bathroom sink", kind: .bathSink, width: 609.6, depth: 508),
                .init(id: "bathroom.bathtub", name: "Bathtub", kind: .bathtub, width: 1524, depth: 762),
                .init(id: "bathroom.shower", name: "Shower", kind: .shower, width: 914.4, depth: 914.4)
            ]
        case .miscellaneous:
            return [
                .init(id: "miscellaneous.storage", name: "Storage cabinet", kind: .storage, width: 914.4, depth: 457.2),
                .init(id: "miscellaneous.plant", name: "Potted plant", kind: .plant, width: 457.2, depth: 457.2),
                .init(id: "miscellaneous.rug", name: "Area rug", kind: .rug, width: 1524, depth: 2133.6),
                .init(id: "miscellaneous.car", name: "Car", kind: .car, width: 1828.8, depth: 4572)
            ]
        case .kitchen:
            return [
                .init(id: "kitchen.sink", name: "Kitchen sink", kind: .kitchenSink, width: 838.2, depth: 558.8),
                .init(id: "kitchen.stove", name: "Stove", kind: .stove, width: 762, depth: 635),
                .init(id: "kitchen.refrigerator", name: "Refrigerator", kind: .refrigerator, width: 914.4, depth: 762),
                .init(id: "kitchen.counter", name: "Counter", kind: .counter, width: 1524, depth: 635),
                .init(id: "kitchen.dining-table", name: "Dining table", kind: .diningTable, width: 1524, depth: 914.4)
            ]
        case .character:
            return [
                .init(id: "character.person", name: "Person", kind: .person, width: 508, depth: 304.8),
                .init(id: "character.child", name: "Child", kind: .child, width: 355.6, depth: 254),
                .init(id: "character.wheelchair", name: "Wheelchair", kind: .wheelchair, width: 762, depth: 1219.2)
            ]
        case .lights:
            return [
                .init(id: "lights.ceiling", name: "Ceiling light", kind: .ceilingLight, width: 304.8, depth: 304.8),
                .init(id: "lights.wall", name: "Wall light", kind: .wallLight, width: 254, depth: 152.4),
                .init(id: "lights.floor", name: "Floor lamp", kind: .floorLamp, width: 457.2, depth: 457.2)
            ]
        case .office:
            return [
                .init(id: "office.desk", name: "Desk", kind: .desk, width: 1524, depth: 762),
                .init(id: "office.chair", name: "Office chair", kind: .officeChair, width: 635, depth: 635),
                .init(id: "office.bookcase", name: "Bookcase", kind: .bookcase, width: 914.4, depth: 304.8)
            ]
        case .livingRoom:
            return [
                .init(id: "living-room.sofa", name: "Sofa", kind: .sofa, width: 2133.6, depth: 914.4),
                .init(id: "living-room.armchair", name: "Armchair", kind: .armchair, width: 914.4, depth: 914.4),
                .init(id: "living-room.coffee-table", name: "Coffee table", kind: .coffeeTable, width: 1219.2, depth: 609.6),
                .init(id: "living-room.television", name: "Television", kind: .television, width: 1219.2, depth: 101.6)
            ]
        case .staircase:
            return [
                .init(id: "staircase.straight", name: "Straight stairs · 36 in", kind: .straightStairs, width: 914.4, depth: 3048),
                .init(id: "staircase.wide", name: "Straight stairs · 42 in", kind: .straightStairs, width: 1066.8, depth: 3657.6),
                .init(id: "staircase.spiral", name: "Spiral stairs · 60 in", kind: .spiralStairs, width: 1524, depth: 1524)
            ]
        case .shapes:
            return [
                .init(id: "shapes.rectangle", name: "Rectangle", kind: .rectangle, width: 1000, depth: 600),
                .init(id: "shapes.circle", name: "Circle", kind: .circle, width: 1000, depth: 1000),
                .init(id: "shapes.ellipse", name: "Ellipse", kind: .ellipse, width: 1000, depth: 600),
                .init(id: "shapes.triangle", name: "Triangle", kind: .triangle, width: 1000, depth: 1000),
                .init(id: "shapes.line", name: "Line", kind: .line, width: 1000, depth: 1)
            ]
        }
    }
}
