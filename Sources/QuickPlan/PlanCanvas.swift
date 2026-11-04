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
    @State private var cursor: PlanPoint?
    @State private var dragStartPan: CGSize?
    @State private var isPanning = false
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
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): cursor = world(location, size: proxy.size)
                    case .ended: cursor = nil
                    }
                }
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.escape) {
                    if store.rotationPreviewActive {
                        store.cancelRotation()
                        store.report("Rotation cancelled.")
                        return .handled
                    }
                    anchor = nil
                    store.report("Wall chain ended. Click to start another wall.")
                    return .handled
                }
                .accessibilityLabel("Floor plan drawing canvas")
                .accessibilityHint("Choose a wall tool and click two points. Shift-click to select multiple objects. Use the inspector for exact measurements and rotation.")

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
            .clipped()
            .onAppear { fitCanvas(size: proxy.size) }
            .onChange(of: store.tool) { _, _ in anchor = nil }
            .onChange(of: store.rotationPreviewActive) { _, active in
                if active { anchor = nil }
            }
            .onChange(of: store.document.activeLayerID) { _, _ in anchor = nil }
            .onChange(of: store.canEditActiveLayer) { _, editable in
                if !editable { anchor = nil }
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
        if !store.activeLayer.isVisible { return "THIS FLOOR IS HIDDEN · SHOW IT IN LAYERS TO EDIT" }
        if store.activeLayer.isLocked { return "THIS FLOOR IS LOCKED · UNLOCK IT IN LAYERS TO EDIT" }
        if store.rotationPreviewActive { return "ROTATION PREVIEW · APPLY IN INSPECTOR · ESC TO CANCEL" }
        switch store.tool {
        case .select: return "CLICK TO SELECT · SHIFT-CLICK TO ADD · DRAG EMPTY SPACE TO PAN"
        case .wall: return anchor == nil ? "CLICK FIRST WALL POINT · OPTION-DRAG TO PAN" : "CLICK NEXT POINT · ESC ENDS CHAIN"
        case .door: return "CLICK A WALL TO PLACE A DOOR · OPTION-DRAG TO PAN"
        case .window: return "CLICK A WALL TO PLACE A WINDOW · OPTION-DRAG TO PAN"
        }
    }

    private func recenter() {
        let points = visibleWalls.flatMap { [$0.start, $0.end] }
        if let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
           let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
            center = PlanPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        } else {
            center = PlanPoint(x: 0, y: 0)
        }
        pan = .zero
        anchor = nil
    }

    private func fitCanvas(size: CGSize) {
        recenter()
        let walls = visibleWalls
        guard !walls.isEmpty else { store.zoom = 0.08; return }
        let points = walls.flatMap { [$0.start, $0.end] }
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

    private func screen(_ point: PlanPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (point.x - center.x) * store.zoom + size.width / 2 + pan.width,
                y: (point.y - center.y) * store.zoom + size.height / 2 + pan.height)
    }

    private func world(_ point: CGPoint, size: CGSize) -> PlanPoint {
        PlanPoint(x: (point.x - size.width / 2 - pan.width) / store.zoom + center.x,
                  y: (point.y - size.height / 2 - pan.height) / store.zoom + center.y)
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
            return abs(along - opening.offset) <= opening.width / 2 + 4 / store.zoom
                && Geometry.distance(from: point, to: wall) <= max(wall.thickness / 2 + 4 / store.zoom, 12 / store.zoom)
        }
    }

    private func drawingGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartPan == nil {
                    dragStartPan = pan
                    let start = world(value.startLocation, size: size)
                    isPanning = NSEvent.modifierFlags.contains(.option)
                        || (store.tool == .select && (!store.canEditActiveLayer
                            || (wallHit(at: start) == nil && openingHit(at: start) == nil)))
                }
                if isPanning, let initial = dragStartPan {
                    pan = CGSize(width: initial.width + value.translation.width,
                                 height: initial.height + value.translation.height)
                }
                cursor = world(value.location, size: size)
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance < 4 && !NSEvent.modifierFlags.contains(.option) {
                    handleClick(world(value.location, size: size))
                }
                dragStartPan = nil
                isPanning = false
            }
    }

    private func handleClick(_ point: PlanPoint) {
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
        case .select:
            let extending = NSEvent.modifierFlags.contains(.shift)
            if let opening = openingHit(at: point) {
                store.selectOpening(opening.id, extending: extending)
            } else if let wall = wallHit(at: point) {
                store.selectWall(wall.id, extending: extending)
            } else if !extending {
                store.selectWall(nil)
            }
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
        if isActive {
            for wall in plan.walls { drawDimension(wall, context: &context, size: size) }
        }
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
            marks.move(to: CGPoint(x: -width / 2, y: thickness / 2))
            marks.addLine(to: CGPoint(x: -width / 2, y: thickness / 2 + width))
            var swing = Path()
            swing.addArc(center: CGPoint(x: -width / 2, y: thickness / 2), radius: width,
                         startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            local.stroke(swing, with: .color(.black.opacity(0.65)), lineWidth: 0.8)
        }
        local.stroke(marks, with: .color(.black), lineWidth: 1.2)
        if showSelection && store.selection.openingIDs.contains(opening.id) {
            let rect = CGRect(x: -width / 2 - 4, y: -thickness / 2 - 4,
                              width: width + 8, height: thickness + 8)
            local.stroke(Path(rect), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
        guard store.canEditActiveLayer, !store.rotationPreviewActive, let cursor else { return }
        if store.tool == .wall {
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
