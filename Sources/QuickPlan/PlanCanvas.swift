#if os(macOS)
import AppKit
import BlueprintCore
import SwiftUI

/// A millimetre-based drawing surface. Screen scale and panning never change geometry.
@MainActor
struct PlanCanvas: View {
    @ObservedObject var store: PlanStore
    @State private var center = PlanPoint(x: 0, y: 0)
    @State private var pan = CGSize.zero
    @State private var anchor: PlanPoint?
    @State private var dimensionAnchor: PlanPoint?
    @State private var areaVertices: [PlanPoint] = []
    @State private var cursor: PlanPoint?
    @State private var hoverLocation: CGPoint?
    @State private var magnificationStartZoom: Double?
    @State private var magnificationAnchor: CGPoint?
    @State private var dragStartPan: CGSize?
    @State private var isPanning = false
    @State private var dragStartWorld: PlanPoint?
    @State private var isMovingSelection = false
    @State private var dragWasCancelled = false
    @FocusState private var isFocused: Bool

    private var snapGrid: Double { store.unit == .imperial ? 152.4 : 100 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    if store.showGrid { drawGrid(context: &context, size: size) }
                    for layer in store.visibleLayers {
                        var composite = context
                        composite.opacity = layer.opacity
                        composite.drawLayer { floorContext in
                            // Apply opacity once to the floor's finished image, rather than
                            // darkening intersections independently for each wall stroke.
                            floorContext.opacity = 1
                            drawFloor(layer, context: &floorContext, size: size)
                        }
                    }
                    drawRotationGuide(context: &context, size: size)
                    drawPreview(context: &context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(drawingGesture(size: proxy.size))
                .simultaneousGesture(magnificationGesture(size: proxy.size))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverLocation = location
                        cursor = world(location, size: proxy.size)
                    case .ended:
                        hoverLocation = nil
                        cursor = nil
                    }
                }
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.escape) {
                    if store.dragPreviewActive {
                        store.cancelSelectionDrag()
                        dragWasCancelled = true
                        store.report("Move cancelled.")
                        return .handled
                    }
                    if store.rotationPreviewActive {
                        store.cancelRotation()
                        store.report("Rotation cancelled.")
                        return .handled
                    }
                    anchor = nil
                    dimensionAnchor = nil
                    areaVertices = []
                    store.report("Drawing ended. Click to begin again.")
                    return .handled
                }
                .onKeyPress(.return) {
                    guard store.tool == .area, !areaVertices.isEmpty else { return .ignored }
                    finishArea()
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard store.tool == .area, !areaVertices.isEmpty else { return .ignored }
                    areaVertices.removeLast()
                    store.report("Last area corner removed. Continue tracing, or press Escape to cancel.")
                    return .handled
                }
                .accessibilityLabel("Floor plan drawing canvas")
                .accessibilityHint("Pinch or scroll to zoom. Select and drag walls or openings. Measure places a distance; Area traces a closed room or footprint.")

                HStack(spacing: 12) {
                    Text(instructions)
                    Spacer(minLength: 12)
                    Text("\(store.snapToGrid ? "SNAP " + store.unit.format(snapGrid) : "FREE DRAW") · \(Int((store.zoom / 0.08 * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.black)
                .padding(10)
                .background(.white.opacity(0.94))
                .allowsHitTesting(false)
            }
            .background(CanvasScrollZoomBridge { factor, location in
                guard dragStartPan == nil, !store.dragPreviewActive,
                      magnificationStartZoom == nil else { return }
                applyZoom(store.zoom * factor, around: location, size: proxy.size)
            })
            .clipped()
            .onAppear { fitCanvas(size: proxy.size) }
            .onChange(of: store.tool) { _, _ in
                anchor = nil; dimensionAnchor = nil; areaVertices = []
                store.cancelSelectionDrag()
            }
            .onChange(of: store.rotationPreviewActive) { _, active in
                if active { anchor = nil; dimensionAnchor = nil; areaVertices = [] }
            }
            .onChange(of: store.document.activeLayerID) { _, _ in
                anchor = nil; dimensionAnchor = nil; areaVertices = []
                store.cancelSelectionDrag()
            }
            .onChange(of: store.canEditActiveLayer) { _, editable in
                if !editable { anchor = nil; dimensionAnchor = nil; areaVertices = [] }
            }
            .onChange(of: store.plan.walls) { _, walls in
                if let current = anchor, !walls.contains(where: { $0.start == current || $0.end == current }) {
                    anchor = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("quickPlanFitCanvas"))) { _ in
                fitCanvas(size: proxy.size)
            }
        }
    }

    private var instructions: String {
        if store.tool == .pan { return "DRAG TO PAN THE CANVAS · GEOMETRY STAYS IN PLACE" }
        if !store.activeLayer.isVisible { return "THIS FLOOR IS HIDDEN · SHOW IT IN LAYERS TO EDIT" }
        if store.activeLayer.isLocked { return "THIS FLOOR IS LOCKED · UNLOCK IT IN LAYERS TO EDIT" }
        if store.rotationPreviewActive { return "ROTATION PREVIEW · APPLY IN INSPECTOR · ESC TO CANCEL" }
        switch store.tool {
        case .select: return "CLICK TO SELECT · DRAG TO MOVE · SHIFT-CLICK TO ADD"
        case .pan: return "DRAG TO PAN THE CANVAS"
        case .measure: return dimensionAnchor == nil ? "CLICK FIRST WALL FACE TO MEASURE" : "CLICK SECOND WALL FACE · ESC TO CANCEL"
        case .area: return areaVertices.isEmpty ? "CLICK ROOM OR FOOTPRINT CORNERS TO TRACE AN AREA" : "CLICK FIRST POINT OR RETURN TO CLOSE · DELETE REMOVES A CORNER · ESC CANCELS"
        case .wall: return anchor == nil ? "CLICK FIRST WALL POINT · OPTION-DRAG TO PAN" : "CLICK NEXT POINT · ESC ENDS CHAIN"
        case .door: return "CLICK A WALL TO PLACE A DOOR · OPTION-DRAG TO PAN"
        case .window: return "CLICK A WALL TO PLACE A WINDOW · OPTION-DRAG TO PAN"
        }
    }

    private func recenter() {
        let points = visiblePoints
        if let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
           let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
            center = PlanPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        } else {
            center = PlanPoint(x: 0, y: 0)
        }
        pan = .zero
        anchor = nil
        dimensionAnchor = nil
        areaVertices = []
    }

    private func fitCanvas(size: CGSize) {
        magnificationStartZoom = nil
        magnificationAnchor = nil
        recenter()
        let walls = visibleWalls
        let points = visiblePoints
        guard !points.isEmpty else { store.zoom = 0.08; return }
        let width = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
        let height = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
        let padding = 2 * (walls.map(\.thickness).max() ?? 150)
        let scale = min(max(80, size.width - 120) / max(width + padding, 1),
                        max(80, size.height - 120) / max(height + padding, 1))
        store.zoom = min(0.15, max(0.00001, scale))
    }

    private var visibleWalls: [Wall] {
        store.visibleLayers.flatMap { layer in
            layer.id == store.document.activeLayerID ? store.canvasPlan.walls : layer.plan.walls
        }
    }

    private var visiblePoints: [PlanPoint] {
        store.visibleLayers.flatMap { layer in
            let plan = layer.id == store.document.activeLayerID ? store.canvasPlan : layer.plan
            return plan.walls.flatMap { [$0.start, $0.end] }
                + plan.dimensions.flatMap { [$0.start, $0.end] }
                + plan.areas.flatMap(\.vertices)
        }
    }

    private func screen(_ point: PlanPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (point.x - center.x) * store.zoom + size.width / 2 + pan.width,
                y: (point.y - center.y) * store.zoom + size.height / 2 + pan.height)
    }

    private func world(_ point: CGPoint, size: CGSize) -> PlanPoint {
        PlanPoint(x: (point.x - size.width / 2 - pan.width) / store.zoom + center.x,
                  y: (point.y - size.height / 2 - pan.height) / store.zoom + center.y)
    }

    private func applyZoom(_ requestedZoom: Double, around point: CGPoint, size: CGSize) {
        guard requestedZoom.isFinite, requestedZoom > 0,
              store.zoom.isFinite, store.zoom > 0,
              point.x.isFinite, point.y.isFinite else { return }
        let nextZoom = min(0.8, max(0.00001, requestedZoom))
        guard nextZoom != store.zoom else { return }
        let fixedPoint = world(point, size: size)
        // Keep the same model point directly beneath the mouse or pinch anchor.
        // Only the viewport changes; the document's geometry stays untouched.
        pan = CGSize(width: point.x - size.width / 2 - (fixedPoint.x - center.x) * nextZoom,
                     height: point.y - size.height / 2 - (fixedPoint.y - center.y) * nextZoom)
        store.zoom = nextZoom
        hoverLocation = point
        cursor = fixedPoint
    }

    private func magnificationGesture(size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                guard dragStartPan == nil, !store.dragPreviewActive else { return }
                if magnificationStartZoom == nil {
                    magnificationStartZoom = store.zoom
                    magnificationAnchor = hoverLocation ?? CGPoint(x: size.width / 2, y: size.height / 2)
                }
                guard let initial = magnificationStartZoom, let point = magnificationAnchor else { return }
                applyZoom(initial * Double(magnification), around: point, size: size)
            }
            .onEnded { magnification in
                if dragStartPan == nil, !store.dragPreviewActive,
                   let initial = magnificationStartZoom, let point = magnificationAnchor {
                    applyZoom(initial * Double(magnification), around: point, size: size)
                }
                magnificationStartZoom = nil
                magnificationAnchor = nil
            }
    }

    private struct WallSnap {
        let point: PlanPoint
        var angleDegrees: Double?
        var matchedLength: Double?
    }

    private func snapped(_ point: PlanPoint) -> PlanPoint { wallSnap(point).point }

    private func wallSnap(_ point: PlanPoint) -> WallSnap {
        // Reference floors can supply alignment points without being modified.
        let endpoints = visibleWalls.flatMap { [$0.start, $0.end] }
        // Existing junctions take priority over orthogonal constraints so corners remain connected.
        if let nearest = endpoints.min(by: { point.distance(to: $0) < point.distance(to: $1) }),
           point.distance(to: nearest) <= 12 / store.zoom {
            // Never move a snapped junction to satisfy a drawing aid. Only show
            // a guide when this exact connected endpoint already meets it.
            guard store.smartGuides, let anchor, anchor.distance(to: nearest) > 0 else {
                return WallSnap(point: nearest)
            }
            let heading = atan2(nearest.y - anchor.y, nearest.x - anchor.x) * 180 / .pi
            let cardinal = (heading / 45).rounded() * 45
            let angle = abs(heading - cardinal) <= 0.000_000_1 ? cardinal : nil
            let length = anchor.distance(to: nearest)
            let matched = visibleWalls.first { abs($0.length - length) <= 0.000_001 }?.length
            return WallSnap(point: nearest, angleDegrees: angle, matchedLength: matched)
        }
        var result = Geometry.snap(point: point, to: [], grid: store.snapToGrid ? snapGrid : 0, tolerance: 0)
        if store.orthogonal, let anchor {
            if abs(result.x - anchor.x) >= abs(result.y - anchor.y) {
                result.y = anchor.y
            } else {
                result.x = anchor.x
            }
        }
        guard store.smartGuides, let anchor else { return WallSnap(point: result) }
        let guide = Geometry.guidedWall(from: anchor, to: result, referenceWalls: visibleWalls,
                                       angleToleranceDegrees: 2, lengthTolerance: 6 / store.zoom,
                                       gridStep: store.snapToGrid ? snapGrid : 0)
        return WallSnap(point: guide.end, angleDegrees: guide.angleDegrees, matchedLength: guide.matchedLength)
    }

    private func wallHit(at point: PlanPoint) -> Wall? {
        store.canvasPlan.walls
            .filter { Geometry.distance(from: point, to: $0) <= max($0.thickness / 2, 9 / store.zoom) }
            .min { Geometry.distance(from: point, to: $0) < Geometry.distance(from: point, to: $1) }
    }

    private func openingHit(at point: PlanPoint) -> Opening? {
        store.canvasPlan.openings.reversed().first { opening in
            guard let wall = store.canvasPlan.walls.first(where: { $0.id == opening.wallID }) else { return false }
            let along = Geometry.projectedDistance(of: point, onto: wall)
            let gapHit = abs(along - opening.offset) <= opening.width / 2 + 4 / store.zoom
                && Geometry.distance(from: point, to: wall) <= max(wall.thickness / 2 + 4 / store.zoom, 12 / store.zoom)
            if gapHit { return true }
            guard opening.kind == .door else { return false }
            let hingeDistance = opening.offset + (opening.hingeAtEnd ? opening.width / 2 : -opening.width / 2)
            let jamb = wall.point(at: hingeDistance)
            let unit = wall.direction
            let hinge = PlanPoint(x: jamb.x - unit.y * wall.thickness / 2,
                                  y: jamb.y + unit.x * wall.thickness / 2)
            let angle = atan2(unit.y, unit.x) + (opening.hingeAtEnd ? .pi : 0) + opening.doorSwingDegrees * .pi / 180
            let tip = PlanPoint(x: hinge.x + cos(angle) * opening.width, y: hinge.y + sin(angle) * opening.width)
            return Geometry.distance(from: point, to: Wall(start: hinge, end: tip, thickness: 1)) <= 8 / store.zoom
        }
    }

    private func dimensionHit(at point: PlanPoint) -> PlanDimension? {
        store.canvasPlan.dimensions.reversed().first { dimension in
            let segment = Wall(start: dimension.start, end: dimension.end, thickness: 1)
            if Geometry.distance(from: point, to: segment) <= 8 / store.zoom { return true }
            let middle = PlanPoint(x: (dimension.start.x + dimension.end.x) / 2,
                                   y: (dimension.start.y + dimension.end.y) / 2)
            return abs(point.x - middle.x) < 45 / store.zoom && abs(point.y - middle.y) < 12 / store.zoom
        }
    }

    private func areaHit(at point: PlanPoint, size: CGSize) -> PlanArea? {
        let location = screen(point, size: size)
        return store.canvasPlan.areas.reversed().first { area in
            if areaPath(area.vertices, size: size).contains(location) { return true }
            let label = areaLabelPoint(area.vertices, size: size)
            return abs(location.x - label.x) <= 55 && abs(location.y - label.y) <= 19
        }
    }

    private func areaPoint(_ point: PlanPoint) -> PlanPoint {
        if let boundary = Geometry.nearestAreaBoundaryPoint(to: point, walls: store.plan.walls, tolerance: 12 / store.zoom) {
            return boundary
        }
        return Geometry.snap(point: point, to: [], grid: store.snapToGrid ? snapGrid : 0, tolerance: 0)
    }

    private func finishArea() {
        guard store.canEditActiveLayer, !store.rotationPreviewActive else { return }
        guard areaVertices.count >= 3 else {
            store.report("Choose at least three different corners before closing the area.")
            return
        }
        let before = store.plan.areas.count
        store.commitArea(vertices: areaVertices)
        if store.plan.areas.count > before { areaVertices = [] }
    }

    private func measurementPoint(_ point: PlanPoint) -> PlanPoint {
        // Prefer the actual wall face over a centreline or grid intersection.
        if let face = Geometry.nearestWallFace(to: point, walls: store.plan.walls, tolerance: 12 / store.zoom) {
            if store.orthogonal, let start = dimensionAnchor {
                let horizontal = abs(face.x - start.x) >= abs(face.y - start.y)
                let aligned = PlanPoint(x: horizontal ? face.x : start.x,
                                        y: horizontal ? start.y : face.y)
                // Projecting an axis onto a diagonal face could leave that face.
                // Use alignment only if the resulting point still meets a wall face.
                if let exactFace = Geometry.nearestWallFace(to: aligned, walls: store.plan.walls, tolerance: 0.000_001) {
                    return exactFace
                }
            }
            return face
        }
        var result = Geometry.snap(point: point, to: [], grid: store.snapToGrid ? snapGrid : 0, tolerance: 0)
        if store.orthogonal, let start = dimensionAnchor {
            if abs(result.x - start.x) >= abs(result.y - start.y) { result.y = start.y }
            else { result.x = start.x }
        }
        return result
    }

    private func beginMove(at point: PlanPoint) -> Bool {
        let extending = NSEvent.modifierFlags.contains(.shift)
        if let opening = openingHit(at: point) {
            if !store.selection.openingIDs.contains(opening.id) && !store.selection.wallIDs.contains(opening.wallID) {
                store.selectOpening(opening.id, extending: extending)
            }
        } else if let wall = wallHit(at: point) {
            if !store.selection.wallIDs.contains(wall.id) { store.selectWall(wall.id, extending: extending) }
        } else { return false }
        store.beginSelectionDrag()
        return store.dragPreviewActive
    }

    private func moveDelta(to point: PlanPoint, from start: PlanPoint) -> PlanPoint {
        var delta = PlanPoint(x: point.x - start.x, y: point.y - start.y)
        if store.snapToGrid, let wall = store.plan.walls.first(where: { store.selection.wallIDs.contains($0.id) }) {
            let moved = PlanPoint(x: wall.start.x + delta.x, y: wall.start.y + delta.y)
            let snapped = Geometry.snap(point: moved, to: [], grid: snapGrid, tolerance: 0)
            delta = PlanPoint(x: snapped.x - wall.start.x, y: snapped.y - wall.start.y)
        }
        return delta
    }

    private func drawingGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartPan == nil {
                    isFocused = true
                    dragStartPan = pan
                    dragStartWorld = world(value.startLocation, size: size)
                    isPanning = store.tool == .pan || NSEvent.modifierFlags.contains(.option)
                    isMovingSelection = false
                    dragWasCancelled = false
                }
                if isPanning, let initial = dragStartPan {
                    pan = CGSize(width: initial.width + value.translation.width,
                                 height: initial.height + value.translation.height)
                } else if store.tool == .select, store.canEditActiveLayer,
                          !store.rotationPreviewActive, !dragWasCancelled,
                          hypot(value.translation.width, value.translation.height) >= 3,
                          let start = dragStartWorld {
                    if !isMovingSelection { isMovingSelection = beginMove(at: start) }
                    if isMovingSelection {
                        let current = world(value.location, size: size)
                        let delta = moveDelta(to: current, from: start)
                        let host: UUID?
                        if store.selection.wallIDs.isEmpty && store.selection.openingIDs.count == 1 {
                            host = store.plan.walls
                                .filter { Geometry.distance(from: current, to: $0) <= max($0.thickness / 2, 12 / store.zoom) }
                                .min { Geometry.distance(from: current, to: $0) < Geometry.distance(from: current, to: $1) }?.id
                        } else { host = nil }
                        store.previewSelectionDrag(by: delta, targetWallID: host)
                    }
                }
                cursor = world(value.location, size: size)
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if isMovingSelection && !dragWasCancelled { store.commitSelectionDrag() }
                else if distance < 4 && !isPanning && !dragWasCancelled {
                    handleClick(world(value.location, size: size), size: size)
                }
                dragStartPan = nil
                dragStartWorld = nil
                isPanning = false
                isMovingSelection = false
                dragWasCancelled = false
            }
    }

    private func handleClick(_ point: PlanPoint, size: CGSize) {
        isFocused = true
        guard store.canEditActiveLayer else {
            anchor = nil
            store.report(store.activeLayer.isLocked
                ? "Unlock this floor in Layers before editing it."
                : "Show this floor in Layers before editing it.")
            return
        }
        guard !store.rotationPreviewActive || store.tool == .select else {
            store.report("Apply or cancel the rotation preview before drawing.")
            return
        }
        switch store.tool {
        case .pan: break
        case .select:
            let extending = NSEvent.modifierFlags.contains(.shift)
            if let opening = openingHit(at: point) {
                store.selectOpening(opening.id, extending: extending)
            } else if let wall = wallHit(at: point) {
                store.selectWall(wall.id, extending: extending)
            } else if let dimension = dimensionHit(at: point) {
                store.selectDimension(dimension.id)
            } else if let area = areaHit(at: point, size: size) {
                store.selectArea(area.id)
            } else if !extending {
                store.selectWall(nil)
            }
        case .area:
            let next = areaPoint(point)
            if areaVertices.count >= 3, let first = areaVertices.first,
               min(first.distance(to: point), first.distance(to: next)) <= 12 / store.zoom {
                finishArea()
                return
            }
            if let last = areaVertices.last, last.distance(to: next) < 1 { return }
            areaVertices.append(next)
            store.report(areaVertices.count < 3
                ? "Choose another corner of the room or footprint."
                : "Click the first corner or press Return to close and measure the area.")
        case .measure:
            let next = measurementPoint(point)
            guard let previous = dimensionAnchor else {
                dimensionAnchor = next
                store.report("Click the other room wall face to place the inside measurement.")
                return
            }
            guard previous.distance(to: next) >= 1 else { return }
            store.commitDimension(from: previous, to: next)
            dimensionAnchor = nil
        case .wall:
            let next = snapped(point)
            guard let previous = anchor else {
                anchor = next
                store.report("Click the next endpoint. Walls snap to the grid and existing endpoints.")
                return
            }
            guard hypot(next.x - previous.x, next.y - previous.y) > 0.01 else { return }
            let oldCount = store.plan.walls.count
            store.commitWall(from: previous, to: next)
            if store.plan.walls.count > oldCount { anchor = next }
        case .door, .window:
            guard let wall = wallHit(at: point) else {
                store.report("Click an existing wall to place the opening.")
                return
            }
            store.placeOpening(on: wall.id, at: Geometry.projectedDistance(of: point, onto: wall))
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let spacing = snapGrid * store.zoom
        guard spacing >= 3 else { return }
        let zero = screen(PlanPoint(x: 0, y: 0), size: size)
        var path = Path()
        var x = zero.x.truncatingRemainder(dividingBy: spacing)
        if x < 0 { x += spacing }
        while x < size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y = zero.y.truncatingRemainder(dividingBy: spacing)
        if y < 0 { y += spacing }
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(.black.opacity(0.065)), lineWidth: 0.5)
    }

    private func wallPath(_ wall: Wall, size: CGSize, extra: Double = 0) -> Path {
        let a = screen(wall.start, size: size)
        let b = screen(wall.end, size: size)
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return Path() }
        let half = wall.thickness * store.zoom / 2 + extra
        let nx = -(b.y - a.y) / length * half
        let ny = (b.x - a.x) / length * half
        var path = Path()
        path.move(to: CGPoint(x: a.x + nx, y: a.y + ny))
        path.addLine(to: CGPoint(x: b.x + nx, y: b.y + ny))
        path.addLine(to: CGPoint(x: b.x - nx, y: b.y - ny))
        path.addLine(to: CGPoint(x: a.x - nx, y: a.y - ny))
        path.closeSubpath()
        return path
    }

    private func drawFloor(_ layer: FloorLayer, context: inout GraphicsContext, size: CGSize) {
        let isActive = layer.id == store.document.activeLayerID
        let plan = isActive ? store.canvasPlan : layer.plan
        let showSelection = isActive && store.canEditActiveLayer
        for area in plan.areas {
            drawArea(area, selected: showSelection && store.selectedAreaID == area.id,
                     context: &context, size: size)
        }
        for wall in plan.walls {
            drawWall(wall, showSelection: showSelection, context: &context, size: size)
        }
        for polygon in Geometry.junctionPatches(for: plan.walls) {
            var path = Path()
            for (index, point) in polygon.enumerated() {
                if index == 0 { path.move(to: screen(point, size: size)) }
                else { path.addLine(to: screen(point, size: size)) }
            }
            path.closeSubpath()
            context.fill(path, with: .color(.black))
        }
        // Erase wall material only inside this isolated floor image. Transparent
        // openings reveal reference floors instead of painting over them in white.
        for opening in plan.openings {
            guard let wall = plan.walls.first(where: { $0.id == opening.wallID }) else { continue }
            cutOpening(opening, wall: wall, context: &context, size: size)
        }
        for opening in plan.openings {
            guard let wall = plan.walls.first(where: { $0.id == opening.wallID }) else { continue }
            drawOpening(opening, wall: wall, showSelection: showSelection, context: &context, size: size)
        }
        for dimension in plan.dimensions {
            drawRoomDimension(dimension, selected: showSelection && store.selectedDimensionID == dimension.id,
                              context: &context, size: size)
        }
        if isActive {
            for wall in plan.walls { drawDimension(wall, context: &context, size: size) }
        }
    }

    private func areaPath(_ vertices: [PlanPoint], size: CGSize) -> Path {
        var path = Path()
        for (index, point) in vertices.enumerated() {
            if index == 0 { path.move(to: screen(point, size: size)) }
            else { path.addLine(to: screen(point, size: size)) }
        }
        if vertices.count >= 3 { path.closeSubpath() }
        return path
    }

    private func areaLabelPoint(_ vertices: [PlanPoint], size: CGSize) -> CGPoint {
        guard let first = vertices.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in vertices.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return screen(PlanPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2), size: size)
    }

    private func drawArea(_ area: PlanArea, selected: Bool, context: inout GraphicsContext, size: CGSize) {
        let path = areaPath(area.vertices, size: size)
        let color: Color = selected ? .blue : .black
        context.fill(path, with: .color(color.opacity(selected ? 0.055 : 0.025)))
        context.stroke(path, with: .color(color.opacity(selected ? 0.85 : 0.5)),
                       style: StrokeStyle(lineWidth: selected ? 1.3 : 0.8, dash: [4, 3]))
        let point = areaLabelPoint(area.vertices, size: size)
        let value = store.unit.formatArea(area.areaSquareMillimetres)
        let labelWidth = max(70, Double(max(area.name.count, value.count)) * 6.8 + 12)
        context.fill(Path(CGRect(x: point.x - labelWidth / 2, y: point.y - 19,
                                 width: labelWidth, height: 38)), with: .color(.white.opacity(0.94)))
        context.draw(Text(area.name).font(.system(size: 10, weight: .medium)).foregroundColor(color),
                     at: CGPoint(x: point.x, y: point.y - 8))
        context.draw(Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(color),
                     at: CGPoint(x: point.x, y: point.y + 8))
        if selected {
            for vertex in area.vertices {
                let handle = screen(vertex, size: size)
                context.fill(Path(ellipseIn: CGRect(x: handle.x - 3, y: handle.y - 3, width: 6, height: 6)),
                             with: .color(.blue))
            }
        }
    }

    private func previewAreaSquareMillimetres(_ vertices: [PlanPoint]) -> Double {
        guard vertices.count >= 3, let origin = vertices.first else { return 0 }
        // Translate to the first vertex to reduce cancellation at distant origins.
        var doubleArea = 0.0
        for index in vertices.indices {
            let a = vertices[index]
            let b = vertices[(index + 1) % vertices.count]
            doubleArea += (a.x - origin.x) * (b.y - origin.y) - (b.x - origin.x) * (a.y - origin.y)
        }
        return abs(doubleArea) / 2
    }

    private func drawWall(_ wall: Wall, showSelection: Bool, context: inout GraphicsContext, size: CGSize) {
        context.fill(wallPath(wall, size: size), with: .color(.black))
        if showSelection && store.selection.wallIDs.contains(wall.id) {
            context.stroke(wallPath(wall, size: size, extra: 4), with: .color(.black),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            for point in [wall.start, wall.end] {
                let p = screen(point, size: size)
                let handle = Path(CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                context.fill(handle, with: .color(.white))
                context.stroke(handle, with: .color(.black), lineWidth: 1.5)
            }
        }
    }

    private func cutOpening(_ opening: Opening, wall: Wall, context: inout GraphicsContext, size: CGSize) {
        let position = screen(wall.point(at: opening.offset), size: size)
        let width = opening.width * store.zoom
        let thickness = wall.thickness * store.zoom
        var local = context
        local.translateBy(x: position.x, y: position.y)
        local.rotate(by: .radians(atan2(wall.end.y - wall.start.y, wall.end.x - wall.start.x)))
        local.blendMode = .destinationOut
        local.fill(Path(CGRect(x: -width / 2, y: -thickness / 2 - 0.5,
                               width: width, height: thickness + 1)), with: .color(.black))
    }

    private func drawOpening(_ opening: Opening, wall: Wall, showSelection: Bool, context: inout GraphicsContext, size: CGSize) {
        let position = screen(wall.point(at: opening.offset), size: size)
        let width = opening.width * store.zoom
        let thickness = wall.thickness * store.zoom
        var local = context
        local.translateBy(x: position.x, y: position.y)
        local.rotate(by: .radians(atan2(wall.end.y - wall.start.y, wall.end.x - wall.start.x)))
        var marks = Path()
        for x in [-width / 2, width / 2] {
            marks.move(to: CGPoint(x: x, y: -thickness / 2))
            marks.addLine(to: CGPoint(x: x, y: thickness / 2))
        }
        if opening.kind == .window {
            for y in [-thickness * 0.22, thickness * 0.22] {
                marks.move(to: CGPoint(x: -width / 2, y: y))
                marks.addLine(to: CGPoint(x: width / 2, y: y))
            }
        } else {
            let hinge = CGPoint(x: opening.hingeAtEnd ? width / 2 : -width / 2, y: thickness / 2)
            let baseDegrees = opening.hingeAtEnd ? 180.0 : 0.0
            let leafDegrees = baseDegrees + opening.doorSwingDegrees
            let radians = leafDegrees * .pi / 180
            let tip = CGPoint(x: hinge.x + cos(radians) * width, y: hinge.y + sin(radians) * width)
            marks.move(to: hinge)
            marks.addLine(to: tip)
            var swing = Path()
            swing.addArc(center: hinge, radius: width, startAngle: .degrees(baseDegrees),
                         endAngle: .degrees(leafDegrees), clockwise: opening.doorSwingDegrees < 0)
            local.stroke(swing, with: .color(.black.opacity(0.65)), lineWidth: 0.8)
            if showSelection && store.selection.openingIDs.contains(opening.id) {
                local.fill(Path(ellipseIn: CGRect(x: hinge.x - 3, y: hinge.y - 3, width: 6, height: 6)), with: .color(.white))
                local.stroke(Path(ellipseIn: CGRect(x: hinge.x - 3, y: hinge.y - 3, width: 6, height: 6)), with: .color(.black), lineWidth: 1)
            }
        }
        local.stroke(marks, with: .color(.black), lineWidth: 1.2)
        if showSelection && store.selection.openingIDs.contains(opening.id) {
            let rect = CGRect(x: -width / 2 - 4, y: -thickness / 2 - 4,
                              width: width + 8, height: thickness + 8)
            local.stroke(Path(rect), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func drawRoomDimension(_ dimension: PlanDimension, selected: Bool,
                                   context: inout GraphicsContext, size: CGSize, preview: Bool = false) {
        let start = screen(dimension.start, size: size)
        let end = screen(dimension.end, size: size)
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 0 else { return }
        let nx = -(end.y - start.y) / distance
        let ny = (end.x - start.x) / distance
        let color: Color = selected || preview ? .blue : .black
        var marks = Path()
        marks.move(to: start); marks.addLine(to: end)
        for point in [start, end] {
            marks.move(to: CGPoint(x: point.x - nx * 5, y: point.y - ny * 5))
            marks.addLine(to: CGPoint(x: point.x + nx * 5, y: point.y + ny * 5))
        }
        context.stroke(marks, with: .color(color), style: StrokeStyle(lineWidth: selected ? 1.4 : 0.9,
                                                                     dash: preview ? [5, 3] : []))
        let text = store.unit.format(dimension.length)
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let width = max(45, Double(text.count) * 6.8 + 12)
        context.fill(Path(CGRect(x: middle.x - width / 2, y: middle.y - 10, width: width, height: 20)), with: .color(.white))
        context.draw(Text(text).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(color), at: middle)
        if selected || preview {
            for point in [start, end] {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }

    private func drawDimension(_ wall: Wall, context: inout GraphicsContext, size: CGSize) {
        let a = screen(wall.start, size: size)
        let b = screen(wall.end, size: size)
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 20 else { return }
        let nx = -(b.y - a.y) / length
        let ny = (b.x - a.x) / length
        let offset = -(wall.thickness * store.zoom / 2 + 21)
        let from = CGPoint(x: a.x + nx * offset, y: a.y + ny * offset)
        let to = CGPoint(x: b.x + nx * offset, y: b.y + ny * offset)
        var line = Path()
        line.move(to: from)
        line.addLine(to: to)
        for point in [from, to] {
            line.move(to: CGPoint(x: point.x - nx * 4, y: point.y - ny * 4))
            line.addLine(to: CGPoint(x: point.x + nx * 4, y: point.y + ny * 4))
        }
        context.stroke(line, with: .color(.black.opacity(0.55)), lineWidth: 0.7)
        let label = store.unit.format(wall.length)
        let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let labelWidth = max(36, Double(label.count) * 6.8 + 10)
        let background = CGRect(x: middle.x - labelWidth / 2, y: middle.y - 9, width: labelWidth, height: 18)
        context.fill(Path(background), with: .color(.white))
        context.draw(Text(label).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.black), at: middle)
    }

    private func drawGuideLine(through point: PlanPoint, angleDegrees: Double,
                               context: inout GraphicsContext, size: CGSize) {
        let pivot = screen(point, size: size)
        let radians = angleDegrees * .pi / 180
        let radius = hypot(size.width, size.height) * 2
        let dx = cos(radians) * radius
        let dy = sin(radians) * radius
        var line = Path()
        line.move(to: CGPoint(x: pivot.x - dx, y: pivot.y - dy))
        line.addLine(to: CGPoint(x: pivot.x + dx, y: pivot.y + dy))
        context.stroke(line, with: .color(.blue.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
    }

    private func drawRotationGuide(context: inout GraphicsContext, size: CGSize) {
        guard store.canEditActiveLayer, let pivot = store.rotationPivot,
              let heading = store.rotationGuideDegrees else { return }
        drawGuideLine(through: pivot, angleDegrees: heading, context: &context, size: size)
        let p = screen(pivot, size: size)
        context.stroke(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                       with: .color(.blue), lineWidth: 1.2)
        let label = Text("\(guideAngle(heading))°")
            .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.blue)
        context.draw(label, at: CGPoint(x: p.x + 12, y: p.y + 17), anchor: .leading)
    }

    private func guideAngle(_ degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return normalized.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func drawPreview(context: inout GraphicsContext, size: CGSize) {
        guard store.canEditActiveLayer, !store.rotationPreviewActive, !store.dragPreviewActive, let cursor else { return }
        if store.tool == .area {
            var endpoint = areaPoint(cursor)
            let canClose: Bool
            if areaVertices.count >= 3, let first = areaVertices.first,
               min(first.distance(to: cursor), first.distance(to: endpoint)) <= 12 / store.zoom {
                endpoint = first
                canClose = true
            } else { canClose = false }
            let point = screen(endpoint, size: size)
            let previewVertices = areaVertices + [endpoint]
            let path = areaPath(previewVertices, size: size)
            if previewVertices.count >= 3 {
                context.fill(path, with: .color(.blue.opacity(0.04)))
                let value = store.unit.formatArea(previewAreaSquareMillimetres(previewVertices))
                context.draw(Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.blue),
                             at: CGPoint(x: point.x + 12, y: point.y - 18), anchor: .leading)
            }
            context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 1.1, dash: [5, 3]))
            for vertex in areaVertices {
                let position = screen(vertex, size: size)
                context.fill(Path(ellipseIn: CGRect(x: position.x - 3, y: position.y - 3, width: 6, height: 6)),
                             with: .color(.blue))
            }
            let radius = canClose ? 7.0 : 4.0
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                               width: radius * 2, height: radius * 2)), with: .color(.white))
            context.stroke(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                 width: radius * 2, height: radius * 2)), with: .color(.blue), lineWidth: 1.4)
        } else if store.tool == .measure {
            let endpoint = measurementPoint(cursor)
            let point = screen(endpoint, size: size)
            context.stroke(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                           with: .color(.blue), lineWidth: 1.2)
            if let start = dimensionAnchor {
                let dimension = PlanDimension(start: start, end: endpoint)
                drawRoomDimension(dimension, selected: false, context: &context, size: size, preview: true)
            }
        } else if store.tool == .wall {
            let guide = wallSnap(cursor)
            let endpoint = guide.point
            let p = screen(endpoint, size: size)
            let hasGuide = guide.angleDegrees != nil || guide.matchedLength != nil
            if let anchor, let angle = guide.angleDegrees {
                drawGuideLine(through: anchor, angleDegrees: angle, context: &context, size: size)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: p.x - 7, y: p.y)); cross.addLine(to: CGPoint(x: p.x + 7, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - 7)); cross.addLine(to: CGPoint(x: p.x, y: p.y + 7))
            context.stroke(cross, with: .color(hasGuide ? .blue : .black), lineWidth: 1)
            if let anchor {
                let from = screen(anchor, size: size)
                var line = Path()
                line.move(to: from); line.addLine(to: p)
                context.stroke(line, with: .color(.black.opacity(0.28)), lineWidth: store.plan.defaultWallThickness * store.zoom)
                context.stroke(line, with: .color(hasGuide ? .blue : .black), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                let distance = hypot(endpoint.x - anchor.x, endpoint.y - anchor.y)
                var labelParts: [String] = []
                if let angle = guide.angleDegrees { labelParts.append("\(guideAngle(angle))°") }
                labelParts.append(store.unit.format(distance))
                if let matched = guide.matchedLength {
                    labelParts.append(visibleWalls.contains { abs($0.length - matched) <= 0.000_001 }
                        ? "LENGTH MATCH" : "GRID LENGTH")
                }
                let label = Text(labelParts.joined(separator: " · "))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(hasGuide ? .blue : .black)
                context.draw(label, at: CGPoint(x: p.x + 12, y: p.y - 16), anchor: .leading)
                if guide.matchedLength != nil {
                    let dx = p.x - from.x
                    let dy = p.y - from.y
                    let screenLength = hypot(dx, dy)
                    if screenLength > 0 {
                        let nx = -dy / screenLength * 5
                        let ny = dx / screenLength * 5
                        var ticks = Path()
                        for endpoint in [from, p] {
                            ticks.move(to: CGPoint(x: endpoint.x - nx, y: endpoint.y - ny))
                            ticks.addLine(to: CGPoint(x: endpoint.x + nx, y: endpoint.y + ny))
                        }
                        context.stroke(ticks, with: .color(.blue), lineWidth: 1.2)
                    }
                }
            }
        } else if store.tool == .door || store.tool == .window, let wall = wallHit(at: cursor) {
            let offset = Geometry.projectedDistance(of: cursor, onto: wall)
            let p = screen(wall.point(at: offset), size: size)
            var local = context
            local.translateBy(x: p.x, y: p.y)
            local.rotate(by: .radians(atan2(wall.end.y - wall.start.y, wall.end.x - wall.start.x)))
            let width = store.openingWidth * store.zoom
            let thickness = max(10, wall.thickness * store.zoom + 6)
            local.stroke(Path(CGRect(x: -width / 2, y: -thickness / 2, width: width, height: thickness)),
                         with: .color(.black), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }
}

#endif
