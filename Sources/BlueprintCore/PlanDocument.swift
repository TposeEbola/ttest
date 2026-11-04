import Foundation

/// A separate, aligned 2D floor. Layer order is bottom-to-top in a document.
public struct FloorLayer: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var plan: FloorPlan
    public var isVisible: Bool
    public var isLocked: Bool
    public var opacity: Double

    public init(
        id: UUID = UUID(), name: String = "Floor 1", plan: FloorPlan = .empty,
        isVisible: Bool = true, isLocked: Bool = false, opacity: Double = 1
    ) {
        self.id = id
        self.name = name
        self.plan = plan
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.opacity = opacity
    }
}

public enum PlanDocumentError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case noLayers
    case duplicateLayerIdentifier
    case missingLayer
    case invalidLayerName
    case invalidOpacity
    case lockedLayer
    case hiddenLayer
    case lastLayer
    case invalidLayerPosition

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This file uses document version \(version), which this version of QuickPlan does not support."
        case .noLayers:
            return "A plan must contain at least one floor layer."
        case .duplicateLayerIdentifier:
            return "Each floor layer must have its own identifier."
        case .missingLayer:
            return "The selected floor layer no longer exists."
        case .invalidLayerName:
            return "Name the floor using 1 to 100 characters."
        case .invalidOpacity:
            return "Layer opacity must be between 0% and 100%."
        case .lockedLayer:
            return "This floor is locked. Unlock it in Layers before editing."
        case .hiddenLayer:
            return "This floor is hidden. Show it in Layers before editing."
        case .lastLayer:
            return "Keep at least one floor layer in the plan."
        case .invalidLayerPosition:
            return "Choose an existing position in the layer stack."
        }
    }
}

/// A `.quickplan` file containing one or more independent 2D floor plans.
public struct PlanDocument: Codable, Equatable, Sendable {
    public var layers: [FloorLayer]
    public var activeLayerID: UUID

    public init(plan: FloorPlan, name: String = "Floor 1") {
        let layer = FloorLayer(name: name, plan: plan)
        layers = [layer]
        activeLayerID = layer.id
    }

    /// Call `validate()` before adopting documents assembled with this initializer.
    public init(layers: [FloorLayer], activeLayerID: UUID) {
        self.layers = layers
        self.activeLayerID = activeLayerID
    }

    /// A validated document always has a matching active layer. The empty fallback
    /// allows inspecting an invalid, manually assembled value before validation.
    public var activeLayer: FloorLayer {
        layers.first(where: { $0.id == activeLayerID }) ?? FloorLayer(id: activeLayerID)
    }

    public static var empty: PlanDocument { PlanDocument(plan: .empty) }
    public static var example: PlanDocument { PlanDocument(plan: .example) }

    private enum CodingKeys: String, CodingKey { case version, layers, activeLayerID }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.layers) || container.contains(.version) || container.contains(.activeLayerID) {
            let version = try container.decode(Int.self, forKey: .version)
            guard version == 1 else { throw PlanDocumentError.unsupportedVersion(version) }
            self.init(
                layers: try container.decode([FloorLayer].self, forKey: .layers),
                activeLayerID: try container.decode(UUID.self, forKey: .activeLayerID)
            )
        } else {
            // Original single-floor files remain editable without losing IDs or precision.
            self.init(plan: try FloorPlan(from: decoder))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(layers, forKey: .layers)
        try container.encode(activeLayerID, forKey: .activeLayerID)
    }

    public func validate() throws {
        guard !layers.isEmpty else { throw PlanDocumentError.noLayers }
        guard Set(layers.map(\.id)).count == layers.count else {
            throw PlanDocumentError.duplicateLayerIdentifier
        }
        guard layers.contains(where: { $0.id == activeLayerID }) else { throw PlanDocumentError.missingLayer }
        for layer in layers {
            let name = layer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 100 else { throw PlanDocumentError.invalidLayerName }
            guard layer.opacity.isFinite, (0...1).contains(layer.opacity) else {
                throw PlanDocumentError.invalidOpacity
            }
            try layer.plan.validate()
        }
    }

    /// Content edits are confined to the active floor, even when other floors
    /// contain walls at the same coordinates or use the same imported IDs.
    public mutating func editActivePlan(_ edit: (inout FloorPlan) throws -> Void) throws {
        let index = try layerIndex(id: activeLayerID)
        guard !layers[index].isLocked else { throw PlanDocumentError.lockedLayer }
        guard layers[index].isVisible else { throw PlanDocumentError.hiddenLayer }
        try transaction { try edit(&$0.layers[index].plan) }
    }

    @discardableResult
    public mutating func addLayer(name: String? = nil) throws -> UUID {
        let name = name ?? nextFloorName()
        let layer = FloorLayer(name: name, plan: FloorPlan(defaultWallThickness: activeLayer.plan.defaultWallThickness))
        try transaction {
            $0.layers.append(layer)
            $0.activeLayerID = layer.id
        }
        return layer.id
    }

    @discardableResult
    public mutating func duplicateLayer(id: UUID) throws -> UUID {
        let index = try layerIndex(id: id)
        let original = layers[index]
        var plan = original.plan
        var wallIDs: [UUID: UUID] = [:]
        for index in plan.walls.indices {
            let oldID = plan.walls[index].id
            let newID = UUID()
            wallIDs[oldID] = newID
            plan.walls[index].id = newID
        }
        for index in plan.openings.indices {
            guard let newWallID = wallIDs[plan.openings[index].wallID] else { throw PlanError.missingWall }
            plan.openings[index].id = UUID()
            plan.openings[index].wallID = newWallID
        }
        let copy = FloorLayer(name: nextCopyName(for: original.name), plan: plan, opacity: original.opacity)
        try transaction {
            $0.layers.insert(copy, at: index + 1)
            $0.activeLayerID = copy.id
        }
        return copy.id
    }

    public mutating func removeLayer(id: UUID) throws {
        let index = try layerIndex(id: id)
        guard layers.count > 1 else { throw PlanDocumentError.lastLayer }
        try transaction {
            $0.layers.remove(at: index)
            if $0.activeLayerID == id {
                $0.activeLayerID = $0.layers[min(index, $0.layers.count - 1)].id
            }
        }
    }

    public mutating func setActiveLayer(id: UUID) throws {
        _ = try layerIndex(id: id)
        try transaction { $0.activeLayerID = id }
    }

    public mutating func renameLayer(id: UUID, name: String) throws {
        let index = try layerIndex(id: id)
        try transaction { $0.layers[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public mutating func setLayerLocked(id: UUID, locked: Bool) throws {
        let index = try layerIndex(id: id)
        try transaction { $0.layers[index].isLocked = locked }
    }

    public mutating func setLayerVisible(id: UUID, visible: Bool) throws {
        let index = try layerIndex(id: id)
        try transaction { $0.layers[index].isVisible = visible }
    }

    public mutating func setLayerOpacity(id: UUID, opacity: Double) throws {
        let index = try layerIndex(id: id)
        try transaction { $0.layers[index].opacity = opacity }
    }

    public mutating func moveLayer(id: UUID, to index: Int) throws {
        let originalIndex = try layerIndex(id: id)
        guard layers.indices.contains(index) else { throw PlanDocumentError.invalidLayerPosition }
        try transaction {
            let layer = $0.layers.remove(at: originalIndex)
            $0.layers.insert(layer, at: index)
        }
    }

    private func layerIndex(id: UUID) throws -> Int {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { throw PlanDocumentError.missingLayer }
        return index
    }

    private mutating func transaction(_ edit: (inout PlanDocument) throws -> Void) throws {
        var candidate = self
        try edit(&candidate)
        try candidate.validate()
        self = candidate
    }

    private func nextFloorName() -> String {
        let names = Set(layers.map(\.name))
        var number = 1
        while names.contains("Floor \(number)") { number += 1 }
        return "Floor \(number)"
    }

    private func nextCopyName(for name: String) -> String {
        let names = Set(layers.map(\.name))
        // Leave room for the suffix when a source already uses the maximum name length.
        let base = String(name.prefix(85))
        var candidate = "\(base) copy"
        var number = 2
        while names.contains(candidate) {
            candidate = "\(base) copy \(number)"
            number += 1
        }
        return candidate
    }
}
