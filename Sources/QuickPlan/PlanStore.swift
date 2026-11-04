#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BlueprintCore

enum EditorTool: String, CaseIterable, Identifiable {
    case select, pan, wall, measure, area, door, window, object, rectangle, circle, ellipse, triangle, line
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .pan: return "hand.draw"
        case .wall: return "line.diagonal"
        case .measure: return "ruler"
        case .area: return "square.dashed"
        case .door: return "door.left.hand.open"
        case .window: return "window.casement"
        case .object: return "square.on.circle"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .ellipse: return "oval"
        case .triangle: return "triangle"
        case .line: return "line.diagonal"
        }
    }
}

typealias DisplayUnit = MeasurementUnit

struct OpeningPreset: Identifiable {
    let name: String
    let width: Double
    let height: Double
    var id: String { name }
    static let doors = [
        OpeningPreset(name: "Interior door", width: 812.8, height: 2032),
        OpeningPreset(name: "Entry door", width: 914.4, height: 2032),
        OpeningPreset(name: "Bathroom door", width: 711.2, height: 2032),
        OpeningPreset(name: "Double door", width: 1524, height: 2032)
    ]
    static let windows = [
        OpeningPreset(name: "Standard window", width: 1219.2, height: 1219.2),
        OpeningPreset(name: "Small window", width: 609.6, height: 914.4),
        OpeningPreset(name: "Wide window", width: 1828.8, height: 1219.2),
        OpeningPreset(name: "Picture window", width: 2438.4, height: 1524)
    ]
}

@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var document: PlanDocument
    @Published private(set) var selection = PlanSelection()
    @Published private(set) var selectedDimensionID: UUID?
    @Published private(set) var selectedAreaID: UUID?
    @Published var tool: EditorTool = .select
    @Published var zoom: Double = 0.08
    @Published var status = "Draw a wall, or select an element to edit its measurements."
    @Published var showGrid = true
    @Published var snapToGrid = true
    @Published var orthogonal = true
    @Published var smartGuides = true
    @Published private(set) var rotationDegrees: Double = 0
    @Published private(set) var rotationPreviewPlan: FloorPlan?
    @Published private(set) var rotationPivot: PlanPoint?
    @Published private(set) var rotationGuideDegrees: Double?
    @Published private(set) var dragPreviewPlan: FloorPlan?
    @Published var unit: DisplayUnit = .imperial {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: "measurementUnit") }
    }
    @Published var openingWidth: Double = 812.8
    @Published var openingHeight: Double = 2032
    @Published var catalogCategory: ObjectCategory = .bedroom
    @Published var selectedPreset: ObjectPreset?
    @Published var itemWidth: Double = 1524
    @Published var itemDepth: Double = 2032
    @Published private(set) var undoStack: [PlanDocument] = []
    @Published private(set) var redoStack: [PlanDocument] = []
    @Published private(set) var fileURL: URL?
    @Published private(set) var savedDocument: PlanDocument
    private var opacityEditStart: PlanDocument?
    private var rotationBasePlan: FloorPlan?
    private var rotationBaseSelection: PlanSelection?
    private var rotationBaseLayerID: UUID?
    private var rotationReferenceAngle: Double = 0
    private var rotatingDoorID: UUID?
    private var dragBasePlan: FloorPlan?
    private var dragBaseSelection: PlanSelection?
    private var dragBaseLayerID: UUID?
    private let pasteboard: NSPasteboard
    private var lastPasteData: Data?
    private var pasteSequences: [UUID: Int] = [:]
    static let selectionPasteboardType = NSPasteboard.PasteboardType("com.quickplan.selection")

    init(pasteboard: NSPasteboard? = nil) {
        self.pasteboard = pasteboard ?? .general
        let initial = PlanDocument.example
        document = initial
        savedDocument = initial
        if let preset = ObjectCatalog.presets(for: .bedroom).first {
            selectedPreset = preset
            itemWidth = preset.width
            itemDepth = preset.depth
        }
        if let stored = UserDefaults.standard.string(forKey: "measurementUnit"), let unit = DisplayUnit(rawValue: stored) {
            self.unit = unit
        }
    }

    var plan: FloorPlan { document.activeLayer.plan }
    var canvasPlan: FloorPlan { dragPreviewPlan ?? rotationPreviewPlan ?? plan }
    var activeLayer: FloorLayer { document.activeLayer }
    var visibleLayers: [FloorLayer] { document.layers.filter { $0.isVisible && $0.opacity > 0 } }
    var canEditActiveLayer: Bool { activeLayer.isVisible && !activeLayer.isLocked }
    var canUndo: Bool { !undoStack.isEmpty || (opacityEditStart.map { $0.layers != document.layers } ?? false) }
    var canRedo: Bool { !redoStack.isEmpty }
    // Selecting a floor changes the editing context, not the drawing itself.
    var isDirty: Bool { document.layers != savedDocument.layers }
    var name: String { fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled Plan" }
    var selectedWall: Wall? { plan.walls.first { $0.id == selectedWallID } }
    var selectedOpening: Opening? { plan.openings.first { $0.id == selectedOpeningID } }
    var selectedItem: PlanItem? { plan.items.first { $0.id == selectedItemID } }
    var selectedDimension: PlanDimension? { plan.dimensions.first { $0.id == selectedDimensionID } }
    var selectedArea: PlanArea? { plan.areas.first { $0.id == selectedAreaID } }
    var selectedWallID: UUID? {
        selection.wallIDs.count == 1 && selection.openingIDs.isEmpty && selection.itemIDs.isEmpty ? selection.wallIDs.first : nil
    }
    var selectedOpeningID: UUID? {
        selection.openingIDs.count == 1 && selection.wallIDs.isEmpty && selection.itemIDs.isEmpty ? selection.openingIDs.first : nil
    }
    var selectedItemID: UUID? {
        selection.itemIDs.count == 1 && selection.wallIDs.isEmpty && selection.openingIDs.isEmpty ? selection.itemIDs.first : nil
    }
    var canCopySelection: Bool { !selection.isEmpty }
    var canPasteSelection: Bool {
        canEditActiveLayer && pasteboard.availableType(from: [Self.selectionPasteboardType]) != nil
    }
    var canRotateSelection: Bool {
        canEditActiveLayer && (!selection.wallIDs.isEmpty || !selection.itemIDs.isEmpty || selectedOpening?.kind == .door)
    }
    var rotationPreviewActive: Bool { rotationBasePlan != nil }
    var dragPreviewActive: Bool { dragBasePlan != nil }

    func report(_ message: String) { status = message }
    func selectWall(_ id: UUID?, extending: Bool = false) {
        guard allowSelection() else { return }
        guard let id, plan.walls.contains(where: { $0.id == id }) else {
            if !extending { clearSelection() }
            return
        }
        cancelPreviews()
        selectedDimensionID = nil
        selectedAreaID = nil
        if extending {
            var next = selection
            if next.wallIDs.contains(id) { next.wallIDs.remove(id) }
            else { next.wallIDs.insert(id) }
            selection = next
        } else { selection = PlanSelection(wallIDs: [id]) }
    }
    func selectOpening(_ id: UUID?, extending: Bool = false) {
        guard allowSelection() else { return }
        guard let id, plan.openings.contains(where: { $0.id == id }) else {
            if !extending { clearSelection() }
            return
        }
        cancelPreviews()
        selectedDimensionID = nil
        selectedAreaID = nil
        if extending {
            var next = selection
            if next.openingIDs.contains(id) { next.openingIDs.remove(id) }
            else { next.openingIDs.insert(id) }
            selection = next
        } else { selection = PlanSelection(openingIDs: [id]) }
    }
    func selectItem(_ id: UUID?, extending: Bool = false) {
        guard allowSelection() else { return }
        guard let id, plan.items.contains(where: { $0.id == id }) else {
            if !extending { clearSelection() }
            return
        }
        cancelPreviews()
        selectedDimensionID = nil
        selectedAreaID = nil
        if extending {
            var next = selection
            if next.itemIDs.contains(id) { next.itemIDs.remove(id) }
            else { next.itemIDs.insert(id) }
            selection = next
        } else { selection = PlanSelection(itemIDs: [id]) }
    }
    func selectAll() {
        if let textView = NSApplication.shared.keyWindow?.firstResponder as? NSTextView, textView.isFieldEditor {
            textView.selectAll(nil)
            return
        }
        guard canEditActiveLayer else { clearSelection(); return }
        cancelPreviews()
        selectedDimensionID = nil
        selectedAreaID = nil
        selection = PlanSelection(wallIDs: Set(plan.walls.map(\.id)), itemIDs: Set(plan.items.map(\.id)))
    }
    private func allowSelection() -> Bool {
        guard canEditActiveLayer else {
            clearSelection()
            report(activeLayer.isLocked ? PlanDocumentError.lockedLayer.localizedDescription : PlanDocumentError.hiddenLayer.localizedDescription)
            return false
        }
        return true
    }
    func selectDimension(_ id: UUID?) {
        guard allowSelection() else { return }
        clearSelection()
        if let id, plan.dimensions.contains(where: { $0.id == id }) { selectedDimensionID = id }
    }
    func selectArea(_ id: UUID?) {
        guard allowSelection() else { return }
        clearSelection()
        if let id, plan.areas.contains(where: { $0.id == id }) { selectedAreaID = id }
    }
    @discardableResult
    func change(_ message: String, _ edit: (inout FloorPlan) throws -> Void) -> Bool {
        changeDocument(message) { try $0.editActivePlan(edit) }
    }
    private func remember(_ previous: PlanDocument) {
        undoStack.append(previous)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    @discardableResult
    private func changeDocument(_ message: String, _ edit: (inout PlanDocument) throws -> Void) -> Bool {
        endLayerOpacityEdit()
        cancelPreviews()
        do {
            var next = document
            try edit(&next)
            try next.validate()
            guard next != document else { return false }
            remember(document)
            let changedFloor = next.activeLayerID != document.activeLayerID
            document = next
            if changedFloor || !canEditActiveLayer { clearSelection() }
            status = message
            return true
        } catch { status = error.localizedDescription; return false }
    }
    func commitWall(from: PlanPoint, to: PlanPoint) {
        change("Wall added. Click the next corner to continue; press Escape to finish.") {
            let id = try $0.addWall(from: from, to: to, thickness: $0.defaultWallThickness)
            selection = PlanSelection(wallIDs: [id])
            selectedDimensionID = nil
            selectedAreaID = nil
        }
    }
    func placeOpening(on wallID: UUID, at offset: Double) {
        let kind: OpeningKind = tool == .window ? .window : .door
        change("\(kind.rawValue.capitalized) added. Select it to adjust its position or size.") {
            let id = try $0.addOpening(wallID: wallID, kind: kind, offset: offset, width: openingWidth, height: openingHeight)
            selection = PlanSelection(openingIDs: [id])
            selectedDimensionID = nil
            selectedAreaID = nil
        }
    }
    func updateWall(id: UUID, start: PlanPoint, end: PlanPoint, thickness: Double) {
        change("Wall updated. Shared corners stay connected.") {
            try $0.updateWall(id: id, start: start, end: end, thickness: thickness)
        }
    }
    func updateOpening(id: UUID, offset: Double, width: Double, height: Double) {
        change("Opening updated.") { try $0.updateOpening(id: id, offset: offset, width: width, height: height) }
    }
    func updateDoor(id: UUID, swingDegrees: Double, hingeAtEnd: Bool) {
        change("Door orientation updated.") { try $0.updateDoor(id: id, swingDegrees: swingDegrees, hingeAtEnd: hingeAtEnd) }
    }
    func choosePreset(_ preset: ObjectPreset) {
        clearSelection()
        catalogCategory = preset.kind.category
        selectedPreset = preset
        itemWidth = preset.width
        itemDepth = preset.depth
        chooseTool(.object)
        report("\(preset.name) selected. Click in the plan to place it; custom dimensions are in Objects.")
    }
    func placeItem(at position: PlanPoint) {
        guard let preset = selectedPreset else { report("Choose an object from the library first."); return }
        let circular = preset.kind == .circle || preset.kind == .spiralStairs
        let depth = circular ? itemWidth : (preset.kind == .line ? 1 : itemDepth)
        insertItem(kind: preset.kind, name: preset.name, position: position, width: itemWidth, depth: depth, rotationDegrees: 0)
    }
    func commitShape(kind: PlanItemKind, position: PlanPoint, width: Double, depth: Double, rotationDegrees: Double = 0) {
        let name: String
        switch kind {
        case .rectangle: name = "Rectangle"
        case .circle: name = "Circle"
        case .ellipse: name = "Ellipse"
        case .triangle: name = "Triangle"
        case .line: name = "Line"
        default: report("Choose a basic shape from Draw."); return
        }
        insertItem(kind: kind, name: name, position: position, width: width, depth: depth, rotationDegrees: rotationDegrees)
    }
    private func insertItem(kind: PlanItemKind, name: String, position: PlanPoint, width: Double, depth: Double, rotationDegrees: Double) {
        change("\(name) placed. Select it to move, resize, copy, or rotate it.") {
            let id = try $0.addItem(kind: kind, name: name, position: position, width: width, depth: depth, rotationDegrees: rotationDegrees)
            selection = PlanSelection(itemIDs: [id])
            selectedDimensionID = nil
            selectedAreaID = nil
        }
    }
    func updateItem(id: UUID, name: String, position: PlanPoint, width: Double, depth: Double, rotationDegrees: Double) {
        change("Object updated.") {
            try $0.updateItem(id: id, name: name, position: position, width: width, depth: depth, rotationDegrees: rotationDegrees)
        }
    }
    func commitDimension(from: PlanPoint, to: PlanPoint, offset: Double = 0) {
        change("Measurement placed. Its anchors and dimension-line position are saved with this floor.") {
            let id = try $0.addDimension(from: from, to: to, offset: offset)
            selection = PlanSelection()
            selectedDimensionID = id
            selectedAreaID = nil
        }
    }
    func updateDimension(id: UUID, start: PlanPoint, end: PlanPoint, offset: Double? = nil) {
        change("Measurement updated.") { try $0.updateDimension(id: id, start: start, end: end, offset: offset) }
    }
    func commitArea(vertices: [PlanPoint]) {
        change("Closed area saved. Its square footage appears in the floor list.") {
            let id = try $0.addArea(vertices: vertices)
            selection = PlanSelection()
            selectedDimensionID = nil
            selectedAreaID = id
        }
    }
    func updateArea(id: UUID, name: String, vertices: [PlanPoint]) {
        change("Area updated.") { try $0.updateArea(id: id, name: name, vertices: vertices) }
    }
    func setDefaultThickness(_ thickness: Double) {
        change("Default wall thickness updated.") { $0.defaultWallThickness = thickness }
    }
    func deleteSelection() {
        if let id = selectedAreaID {
            if change("Area deleted.", { $0.removeArea(id: id) }) { clearSelection() }
            return
        }
        if let id = selectedDimensionID {
            if change("Measurement deleted.", { $0.removeDimension(id: id) }) { clearSelection() }
            return
        }
        guard !selection.isEmpty else { return }
        let targets = selection
        if change("Selection deleted. Use Undo to restore it.", {
            for id in targets.openingIDs { $0.removeOpening(id: id) }
            for id in targets.wallIDs { $0.removeWall(id: id) }
            for id in targets.itemIDs { $0.removeItem(id: id) }
        }) { clearSelection() }
    }
    func undo() {
        if let editor = NSApplication.shared.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
            if editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
            return
        }
        endLayerOpacityEdit()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document); document = previous; clearSelection(); status = "Undone."
    }
    func redo() {
        if let editor = NSApplication.shared.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
            if editor.undoManager?.canRedo == true { editor.undoManager?.redo() }
            return
        }
        endLayerOpacityEdit()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document); document = next; clearSelection(); status = "Redone."
    }
    func clearSelection() {
        cancelPreviews()
        selection = PlanSelection()
        selectedDimensionID = nil
        selectedAreaID = nil
    }
    private func cancelPreviews() {
        cancelRotation()
        cancelSelectionDrag()
    }

    func beginSelectionDrag() {
        guard canEditActiveLayer, !selection.isEmpty else { return }
        endLayerOpacityEdit()
        cancelPreviews()
        dragBasePlan = plan
        dragBaseSelection = selection
        dragBaseLayerID = activeLayer.id
        dragPreviewPlan = plan
    }
    func previewSelectionDrag(by delta: PlanPoint, targetWallID: UUID? = nil) {
        guard let original = dragBasePlan, let targets = dragBaseSelection,
              dragBaseLayerID == activeLayer.id, canEditActiveLayer else { return }
        do {
            var preview = original
            try preview.translateSelection(targets, by: delta, targetWallID: targetWallID)
            dragPreviewPlan = preview
        } catch {
            dragPreviewPlan = nil
            report(error.localizedDescription)
        }
    }
    func commitSelectionDrag() {
        guard dragBaseLayerID == activeLayer.id, canEditActiveLayer,
              dragBasePlan != nil, let preview = dragPreviewPlan else {
            cancelSelectionDrag()
            return
        }
        cancelSelectionDrag()
        change("Selection moved. Use Undo to restore its previous position.") { $0 = preview }
    }
    func cancelSelectionDrag() {
        dragBasePlan = nil
        dragBaseSelection = nil
        dragBaseLayerID = nil
        dragPreviewPlan = nil
    }
    func copySelection() {
        if let textView = NSApplication.shared.keyWindow?.firstResponder as? NSTextView, textView.isFieldEditor {
            textView.copy(nil)
            return
        }
        guard canCopySelection else { report("Select walls, openings, or objects to copy."); return }
        do {
            let copied = try plan.copySelection(selection)
            let data = try JSONEncoder().encode(copied)
            pasteboard.clearContents()
            guard pasteboard.setData(data, forType: Self.selectionPasteboardType) else {
                report("The clipboard could not accept the selection.")
                return
            }
            pasteboard.setString("QuickPlan: \(copied.walls.count) walls, \(copied.openings.count) openings, \(copied.items.count) objects", forType: .string)
            lastPasteData = nil
            pasteSequences.removeAll()
            report("Selection copied. Paste onto this floor or select another floor first.")
        } catch { report(error.localizedDescription) }
    }
    func pasteSelection() {
        pasteSelection(inPlace: false)
    }
    func pasteInPlace() {
        pasteSelection(inPlace: true)
    }
    private func pasteSelection(inPlace: Bool) {
        if let textView = NSApplication.shared.keyWindow?.firstResponder as? NSTextView, textView.isFieldEditor {
            textView.paste(nil)
            return
        }
        guard canEditActiveLayer else {
            report(activeLayer.isLocked ? PlanDocumentError.lockedLayer.localizedDescription : PlanDocumentError.hiddenLayer.localizedDescription)
            return
        }
        guard let data = pasteboard.data(forType: Self.selectionPasteboardType) else {
            report("Copy a QuickPlan selection before pasting.")
            return
        }
        do {
            let copied = try JSONDecoder().decode(PlanClipboard.self, from: data)
            let target = copied.walls.isEmpty && copied.items.isEmpty ? (selectedWallID ?? selectedOpening?.wallID) : nil
            let changingHost = target.map { target in copied.openings.contains { $0.wallID != target } } ?? false
            let nextSequence = lastPasteData == data ? (pasteSequences[activeLayer.id] ?? 0) + 1 : 1
            let distance = 304.8 * Double(nextSequence)
            let offset = inPlace || changingHost ? PlanPoint(x: 0, y: 0) : PlanPoint(x: distance, y: distance)
            let succeeded = change(inPlace ? "Selection pasted in place with independent walls and openings." : "Selection pasted with independent walls and openings.") {
                selection = try $0.paste(copied, offset: offset, targetWallID: target)
                selectedDimensionID = nil
                selectedAreaID = nil
            }
            if succeeded && !inPlace {
                if lastPasteData != data { pasteSequences.removeAll() }
                lastPasteData = data
                pasteSequences[activeLayer.id] = nextSequence
            }
        } catch { report("Could not paste: \(error.localizedDescription)") }
    }

    func beginRotation() {
        guard canRotateSelection else {
            if !canEditActiveLayer {
                report(activeLayer.isLocked ? PlanDocumentError.lockedLayer.localizedDescription : PlanDocumentError.hiddenLayer.localizedDescription)
            } else { report("Select a wall, object, group, or door to rotate. Windows follow their host wall.") }
            return
        }
        endLayerOpacityEdit()
        cancelPreviews()
        let pivot: PlanPoint
        let door = selectedOpening?.kind == .door ? selectedOpening : nil
        do {
            if let door, let host = plan.walls.first(where: { $0.id == door.wallID }) {
                let distance = door.offset + (door.hingeAtEnd ? 1 : -1) * door.width / 2
                let jamb = host.point(at: distance)
                pivot = PlanPoint(x: jamb.x - host.direction.y * host.thickness / 2,
                                  y: jamb.y + host.direction.x * host.thickness / 2)
            } else { pivot = try plan.selectionCenter(selection) }
        }
        catch { report(error.localizedDescription); return }
        rotationBasePlan = plan
        rotationBaseSelection = selection
        rotationBaseLayerID = activeLayer.id
        rotationPivot = pivot
        rotatingDoorID = door?.id
        if let door, let host = plan.walls.first(where: { $0.id == door.wallID }) {
            rotationReferenceAngle = atan2(host.end.y - host.start.y, host.end.x - host.start.x) * 180 / .pi
                + (door.hingeAtEnd ? 180 : 0) + door.doorSwingDegrees
        } else if let reference = plan.walls.first(where: { selection.wallIDs.contains($0.id) }) {
            rotationReferenceAngle = atan2(reference.end.y - reference.start.y, reference.end.x - reference.start.x) * 180 / .pi
        } else if let reference = plan.items.first(where: { selection.itemIDs.contains($0.id) }) {
            rotationReferenceAngle = reference.rotationDegrees.truncatingRemainder(dividingBy: 360)
        }
        rotationDegrees = 0
        rotationPreviewPlan = plan
    }
    func previewRotation(_ degrees: Double) {
        guard degrees.isFinite else {
            rotationPreviewPlan = nil
            rotationGuideDegrees = nil
            report(PlanSelectionError.invalidRotation.localizedDescription)
            return
        }
        if rotationBasePlan == nil { beginRotation() }
        guard let original = rotationBasePlan, let targets = rotationBaseSelection,
              let pivot = rotationPivot, rotationBaseLayerID == activeLayer.id,
              canEditActiveLayer else { return }
        // Whole turns have no geometric effect. Keep the dial's trigonometry
        // bounded even when an unusually large finite angle is entered.
        let boundedDegrees = degrees.truncatingRemainder(dividingBy: 360)
        var adjusted = boundedDegrees
        rotationGuideDegrees = nil
        if smartGuides, let snapped = Geometry.snappedRotation(rotationReferenceAngle + boundedDegrees) {
            let worldAngle = rotationReferenceAngle + boundedDegrees
            let nearestTurn = snapped + ((worldAngle - snapped) / 360).rounded() * 360
            adjusted = nearestTurn - rotationReferenceAngle
            rotationGuideDegrees = snapped
        }
        rotationDegrees = adjusted
        do {
            var preview = original
            if let doorID = rotatingDoorID, let door = original.openings.first(where: { $0.id == doorID }) {
                var swing = (door.doorSwingDegrees + adjusted).truncatingRemainder(dividingBy: 360)
                if swing > 180 { swing -= 360 }
                if swing < -180 { swing += 360 }
                try preview.updateDoor(id: doorID, swingDegrees: swing, hingeAtEnd: door.hingeAtEnd)
            } else { try preview.rotateSelection(targets, byDegrees: adjusted, around: pivot) }
            rotationPreviewPlan = preview
            report("Rotation preview: \(adjusted.formatted(.number.precision(.fractionLength(0...2))))°. Apply to keep it, or cancel.")
        } catch {
            rotationPreviewPlan = nil
            rotationGuideDegrees = nil
            report(error.localizedDescription)
        }
    }
    func commitRotation() {
        guard rotationBaseLayerID == activeLayer.id, canEditActiveLayer,
              let preview = rotationPreviewPlan, rotationBasePlan != nil else {
            cancelRotation()
            return
        }
        let degrees = rotationDegrees
        cancelRotation()
        change("Selection rotated by \(degrees.formatted(.number.precision(.fractionLength(0...2))))°.") { $0 = preview }
    }
    func cancelRotation() {
        rotationBasePlan = nil
        rotationBaseSelection = nil
        rotationBaseLayerID = nil
        rotationPreviewPlan = nil
        rotationPivot = nil
        rotationGuideDegrees = nil
        rotationDegrees = 0
        rotationReferenceAngle = 0
        rotatingDoorID = nil
    }
    func chooseTool(_ value: EditorTool) {
        cancelPreviews()
        tool = value
        if value == .door { applyPreset(OpeningPreset.doors[0]) }
        if value == .window { applyPreset(OpeningPreset.windows[0]) }
    }
    func applyPreset(_ preset: OpeningPreset) { openingWidth = preset.width; openingHeight = preset.height }
    func selectLayer(id: UUID) {
        endLayerOpacityEdit()
        cancelPreviews()
        do {
            var next = document
            try next.setActiveLayer(id: id)
            document = next
            clearSelection()
            status = activeLayer.isLocked ? "\(activeLayer.name) is locked. Unlock it to draw or edit."
                : (!activeLayer.isVisible ? "\(activeLayer.name) is hidden. Show it to draw or edit." : "Editing \(activeLayer.name). Other floors stay separate.")
        } catch { status = error.localizedDescription }
    }
    func addLayer() {
        changeDocument("New floor added. Draw over a faded reference floor to align the layout.") { try $0.addLayer() }
    }
    func duplicateActiveLayer() {
        let id = activeLayer.id
        changeDocument("Floor duplicated with independent walls and openings.") { try $0.duplicateLayer(id: id) }
    }
    func removeLayer(id: UUID) {
        if changeDocument("Floor removed. Use Undo to restore it.", { try $0.removeLayer(id: id) }) { clearSelection() }
    }
    func renameLayer(id: UUID, name: String) {
        changeDocument("Floor renamed.") { try $0.renameLayer(id: id, name: name) }
    }
    func setLayerLocked(id: UUID, locked: Bool) {
        changeDocument(locked ? "Floor locked. Its walls and openings are protected." : "Floor unlocked.") {
            try $0.setLayerLocked(id: id, locked: locked)
        }
    }
    func setLayerVisible(id: UUID, visible: Bool) {
        changeDocument(visible ? "Floor shown." : "Floor hidden.") { try $0.setLayerVisible(id: id, visible: visible) }
    }
    func moveLayer(id: UUID, to index: Int) {
        changeDocument("Floor stacking order updated.") { try $0.moveLayer(id: id, to: index) }
    }
    func beginLayerOpacityEdit() {
        endLayerOpacityEdit()
        cancelPreviews()
        opacityEditStart = document
    }
    func setLayerOpacity(id: UUID, opacity: Double) {
        guard opacityEditStart != nil else {
            changeDocument("Floor opacity updated.") { try $0.setLayerOpacity(id: id, opacity: opacity) }
            return
        }
        do {
            var next = document
            try next.setLayerOpacity(id: id, opacity: opacity)
            document = next
            status = "\(activeLayer.name) opacity: \(Int((activeLayer.opacity * 100).rounded()))%."
        } catch { status = error.localizedDescription }
    }
    func endLayerOpacityEdit() {
        guard let before = opacityEditStart else { return }
        opacityEditStart = nil
        if before.layers != document.layers { remember(before) }
    }
    func fit() {
        NotificationCenter.default.post(name: Notification.Name("quickPlanFitCanvas"), object: nil)
    }

    private func confirmDiscard() -> Bool {
        endLayerOpacityEdit()
        cancelPreviews()
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(name)?"
        alert.informativeText = "Your unsaved edits will be lost if you continue without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); return !isDirty
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func confirmClose() -> Bool { confirmDiscard() }
    func newPlan() {
        guard confirmDiscard() else { return }
        document = PlanDocument(plan: FloorPlan(defaultWallThickness: unit == .metric ? 150 : 152.4))
        lastPasteData = nil; pasteSequences.removeAll()
        savedDocument = document; fileURL = nil
        undoStack = []; redoStack = []; clearSelection(); fit()
        status = "New plan. Choose Wall and click two corners to begin."
    }
    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "quickplan") ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }
    func open(url: URL) {
        guard confirmDiscard() else { return }
        do {
            let loaded = try JSONDecoder().decode(PlanDocument.self, from: Data(contentsOf: url))
            try loaded.validate()
            document = loaded; savedDocument = loaded; fileURL = url
            lastPasteData = nil; pasteSequences.removeAll()
            undoStack = []; redoStack = []; clearSelection(); fit()
            status = "Opened \(url.lastPathComponent)."
        } catch { status = "Could not open plan: \(error.localizedDescription)" }
    }
    func save() {
        guard let url = fileURL else { saveAs(); return }
        write(to: url)
    }
    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "quickplan") ?? .json]
        panel.nameFieldStringValue = "\(name).quickplan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }
    private func write(to url: URL) {
        endLayerOpacityEdit()
        cancelPreviews()
        do {
            try document.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            fileURL = url; savedDocument = document; status = "Saved all floors to \(url.lastPathComponent)."
        } catch { status = "Could not save plan: \(error.localizedDescription)" }
    }
    func exportSVG() {
        cancelPreviews()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.title = "Export Active Floor SVG"
        panel.message = "Exports \(activeLayer.name) at full opacity. Other floors are excluded."
        panel.nameFieldStringValue = "\(name) - \(activeLayer.name).svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try plan.svg().write(to: url, atomically: true, encoding: .utf8)
            status = "Exported \(activeLayer.name) only at full opacity; measurements are in millimetres."
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }
}
#endif
