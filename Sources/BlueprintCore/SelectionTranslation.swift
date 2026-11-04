import Foundation

public enum SelectionTranslationError: LocalizedError, Equatable {
    case ambiguousDestinationWall

    public var errorDescription: String? {
        "Select one door or window when moving an opening onto a different wall."
    }
}

extension FloorPlan {
    /// Translate walls as a rigid group while retaining their shared junctions.
    /// Unselected adjoining walls stretch at the connected endpoint. Openings
    /// attached to a moving wall follow it; individually selected openings slide
    /// along a host wall, or move to an explicitly chosen destination wall.
    public mutating func translateSelection(
        _ selection: PlanSelection,
        by delta: PlanPoint,
        targetWallID: UUID? = nil
    ) throws {
        try validate()
        guard !selection.isEmpty else { throw PlanSelectionError.emptySelection }
        guard selection.wallIDs.isSubset(of: Set(walls.map(\.id))) else { throw PlanError.missingWall }
        guard selection.openingIDs.isSubset(of: Set(openings.map(\.id))) else { throw PlanError.missingOpening }
        guard delta.x.isFinite, delta.y.isFinite else { throw PlanError.invalidCoordinate }

        let standaloneOpenings = openings.filter {
            selection.openingIDs.contains($0.id) && !selection.wallIDs.contains($0.wallID)
        }
        if let targetWallID {
            guard selection.wallIDs.isEmpty, standaloneOpenings.count == 1 else {
                throw SelectionTranslationError.ambiguousDestinationWall
            }
            guard walls.contains(where: { $0.id == targetWallID }) else { throw PlanError.missingWall }
        }
        guard delta.x != 0 || delta.y != 0 || targetWallID != nil else { return }

        let movedJunctions = Set(walls.filter { selection.wallIDs.contains($0.id) }
            .flatMap { [$0.start, $0.end] })
        func translated(_ point: PlanPoint) -> PlanPoint {
            PlanPoint(x: point.x + delta.x, y: point.y + delta.y)
        }
        var candidate = self
        // Compare every endpoint with the original snapshot, so one shared
        // junction is never translated more than once in a multi-wall drag.
        for index in walls.indices {
            if selection.wallIDs.contains(walls[index].id) || movedJunctions.contains(walls[index].start) {
                candidate.walls[index].start = translated(walls[index].start)
            }
            if selection.wallIDs.contains(walls[index].id) || movedJunctions.contains(walls[index].end) {
                candidate.walls[index].end = translated(walls[index].end)
            }
        }

        let originalWalls = Dictionary(uniqueKeysWithValues: walls.map { ($0.id, $0) })
        let destinationWalls = Dictionary(uniqueKeysWithValues: candidate.walls.map { ($0.id, $0) })
        for index in openings.indices {
            let opening = openings[index]
            guard selection.openingIDs.contains(opening.id),
                  !selection.wallIDs.contains(opening.wallID) else { continue }
            guard let originalHost = originalWalls[opening.wallID],
                  let destination = destinationWalls[targetWallID ?? opening.wallID] else {
                throw PlanError.missingWall
            }
            let desiredCenter = translated(originalHost.point(at: opening.offset))
            guard desiredCenter.x.isFinite, desiredCenter.y.isFinite else { throw PlanError.invalidCoordinate }
            candidate.openings[index].wallID = destination.id
            candidate.openings[index].offset = Geometry.projectedDistance(of: desiredCenter, onto: destination)
        }

        // Reject the whole drag when it would collapse a connected wall, push an
        // opening beyond an endpoint, or overlap another opening.
        try candidate.validate()
        self = candidate
    }
}
