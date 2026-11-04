import Foundation

public struct PlanSelection: Equatable, Sendable {
    public var wallIDs: Set<UUID>
    public var openingIDs: Set<UUID>
    public var itemIDs: Set<UUID>

    public init(wallIDs: Set<UUID> = [], openingIDs: Set<UUID> = [], itemIDs: Set<UUID> = []) {
        self.wallIDs = wallIDs
        self.openingIDs = openingIDs
        self.itemIDs = itemIDs
    }

    public var isEmpty: Bool { wallIDs.isEmpty && openingIDs.isEmpty && itemIDs.isEmpty }
}

public enum PlanSelectionError: LocalizedError, Equatable {
    case emptySelection
    case missingHostWall
    case selectHostWallToRotate
    case invalidRotation
    case invalidClipboard

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select a wall, door, window, object, or shape first."
        case .missingHostWall:
            return "Select a destination wall before pasting this door or window onto another floor."
        case .selectHostWallToRotate:
            return "Select the host wall to rotate attached doors/windows."
        case .invalidRotation:
            return "Enter a finite rotation angle in degrees."
        case .invalidClipboard:
            return "The clipboard does not contain a valid QuickPlan selection."
        }
    }
}

/// Host walls in `sourceWalls` provide the geometry needed to validate copied
/// standalone doors/windows; they are references and are not themselves pasted.
public struct PlanClipboard: Codable, Equatable, Sendable {
    public var walls: [Wall]
    public var openings: [Opening]
    public var sourceWalls: [Wall]
    public var items: [PlanItem]

    public init(walls: [Wall] = [], openings: [Opening] = [], sourceWalls: [Wall] = [], items: [PlanItem] = []) {
        self.walls = walls
        self.openings = openings
        self.sourceWalls = sourceWalls
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case walls, openings, sourceWalls, items }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        walls = try container.decode([Wall].self, forKey: .walls)
        openings = try container.decode([Opening].self, forKey: .openings)
        sourceWalls = try container.decode([Wall].self, forKey: .sourceWalls)
        items = try container.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(walls, forKey: .walls)
        try container.encode(openings, forKey: .openings)
        try container.encode(sourceWalls, forKey: .sourceWalls)
        try container.encode(items, forKey: .items)
    }

    public func validate() throws {
        guard !walls.isEmpty || !openings.isEmpty || !items.isEmpty else { throw PlanSelectionError.emptySelection }
        let referencedWalls = Set(openings.map(\.wallID))
        guard Set(sourceWalls.map(\.id)).isSubset(of: referencedWalls) else {
            throw PlanSelectionError.invalidClipboard
        }
        // This checks duplicate IDs, finite measurements, host references, fit,
        // and overlap before any clipboard data can enter a destination plan.
        try FloorPlan(walls: walls + sourceWalls, openings: openings, items: items).validate()
    }
}

extension FloorPlan {
    /// Selecting a wall implicitly includes its attached doors and windows.
    public func copySelection(_ selection: PlanSelection) throws -> PlanClipboard {
        try validate()
        try validateSelection(selection)
        let copiedWalls = walls.filter { selection.wallIDs.contains($0.id) }
        let copiedOpenings = openings.filter {
            selection.openingIDs.contains($0.id) || selection.wallIDs.contains($0.wallID)
        }
        let referencedIDs = Set(copiedOpenings.map(\.wallID)).subtracting(selection.wallIDs)
        let clipboard = PlanClipboard(
            walls: copiedWalls, openings: copiedOpenings,
            sourceWalls: walls.filter { referencedIDs.contains($0.id) },
            items: items.filter { selection.itemIDs.contains($0.id) }
        )
        try clipboard.validate()
        return clipboard
    }

    /// Pasted walls receive new IDs and keep their attached openings. Standalone
    /// openings use the selected target wall, or their original wall if present.
    /// Offset is in plan millimetres; for openings it projects along their host.
    @discardableResult
    public mutating func paste(
        _ clipboard: PlanClipboard,
        offset: PlanPoint = PlanPoint(x: 300, y: 300),
        targetWallID: UUID? = nil
    ) throws -> PlanSelection {
        try validate()
        try clipboard.validate()
        guard offset.x.isFinite, offset.y.isFinite else { throw PlanError.invalidCoordinate }

        var candidate = self
        var remappedWallIDs: [UUID: UUID] = [:]
        var selection = PlanSelection()
        for wall in clipboard.walls {
            var copy = wall
            copy.id = UUID()
            copy.start.x += offset.x; copy.start.y += offset.y
            copy.end.x += offset.x; copy.end.y += offset.y
            remappedWallIDs[wall.id] = copy.id
            candidate.walls.append(copy)
            selection.wallIDs.insert(copy.id)
        }
        for opening in clipboard.openings {
            var copy = opening
            copy.id = UUID()
            if let newHostID = remappedWallIDs[opening.wallID] {
                copy.wallID = newHostID
            } else {
                let hostID = targetWallID ?? opening.wallID
                guard let host = walls.first(where: { $0.id == hostID }) else {
                    throw PlanSelectionError.missingHostWall
                }
                copy.wallID = host.id
                copy.offset += offset.x * host.direction.x + offset.y * host.direction.y
                selection.openingIDs.insert(copy.id)
            }
            candidate.openings.append(copy)
        }
        for item in clipboard.items {
            var copy = item
            copy.id = UUID()
            copy.position.x += offset.x
            copy.position.y += offset.y
            candidate.items.append(copy)
            selection.itemIDs.insert(copy.id)
        }
        try candidate.validate()
        self = candidate
        return selection
    }

    /// The centre of the selected geometry's axis-aligned bounds, in millimetres.
    public func selectionCenter(_ selection: PlanSelection) throws -> PlanPoint {
        let clipboard = try copySelection(selection)
        var points = clipboard.walls.flatMap { [$0.start, $0.end] }
        points.append(contentsOf: clipboard.items.flatMap(\.corners))
        for opening in clipboard.openings where !selection.wallIDs.contains(opening.wallID) {
            guard let host = clipboard.sourceWalls.first(where: { $0.id == opening.wallID }) else {
                throw PlanSelectionError.missingHostWall
            }
            points.append(host.point(at: opening.offset - opening.width / 2))
            points.append(host.point(at: opening.offset + opening.width / 2))
        }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else {
            throw PlanSelectionError.emptySelection
        }
        return PlanPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    /// Rotate selected walls, objects, and shapes. Unselected walls keep their endpoints;
    /// a selected wall's own doors/windows follow it at unchanged along-wall offsets.
    public mutating func rotateSelection(
        _ selection: PlanSelection, byDegrees degrees: Double, around pivot: PlanPoint? = nil
    ) throws {
        try validate()
        try validateSelection(selection)
        guard degrees.isFinite else { throw PlanSelectionError.invalidRotation }
        guard !selection.wallIDs.isEmpty || !selection.itemIDs.isEmpty,
              openings.filter({ selection.openingIDs.contains($0.id) })
                .allSatisfy({ selection.wallIDs.contains($0.wallID) }) else {
            throw PlanSelectionError.selectHostWallToRotate
        }
        let centre = try pivot ?? selectionCenter(selection)
        guard centre.x.isFinite, centre.y.isFinite else { throw PlanError.invalidCoordinate }
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        guard normalized != 0 else { return }
        let radians = normalized * .pi / 180
        // Exact quarter turns keep shared selected corners exactly equal and
        // avoid introducing trigonometric residue into orthogonal drawings.
        let cosine = snapTrig(cos(radians))
        let sine = snapTrig(sin(radians))
        func rotated(_ point: PlanPoint) -> PlanPoint {
            let dx = point.x - centre.x
            let dy = point.y - centre.y
            return PlanPoint(x: centre.x + dx * cosine - dy * sine,
                             y: centre.y + dx * sine + dy * cosine)
        }
        var candidate = self
        for index in candidate.walls.indices where selection.wallIDs.contains(candidate.walls[index].id) {
            candidate.walls[index].start = rotated(candidate.walls[index].start)
            candidate.walls[index].end = rotated(candidate.walls[index].end)
        }
        for index in candidate.items.indices where selection.itemIDs.contains(candidate.items[index].id) {
            candidate.items[index].position = rotated(candidate.items[index].position)
            let angle = (candidate.items[index].rotationDegrees + normalized)
                .truncatingRemainder(dividingBy: 360)
            candidate.items[index].rotationDegrees = angle < 0 ? angle + 360 : angle
        }
        try candidate.validate()
        self = candidate
    }

    private func validateSelection(_ selection: PlanSelection) throws {
        guard !selection.isEmpty else { throw PlanSelectionError.emptySelection }
        guard selection.wallIDs.isSubset(of: Set(walls.map(\.id))) else { throw PlanError.missingWall }
        guard selection.openingIDs.isSubset(of: Set(openings.map(\.id))) else { throw PlanError.missingOpening }
        guard selection.itemIDs.isSubset(of: Set(items.map(\.id))) else { throw PlanItemError.missingItem }
    }
}

private func snapTrig(_ value: Double) -> Double {
    if abs(value) < 0.000_000_000_001 { return 0 }
    if abs(value - 1) < 0.000_000_000_001 { return 1 }
    if abs(value + 1) < 0.000_000_000_001 { return -1 }
    return value
}
