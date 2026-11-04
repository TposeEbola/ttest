#if os(macOS)
import SwiftUI
import BlueprintCore
import AppKit

/// Floors share one drawing origin, while each keeps its own editable geometry.
@MainActor
struct LayerPanel: View {
    @ObservedObject var store: PlanStore
    @State private var expandedFloorIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 12))
                Text("FLOORS & LAYERS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                Spacer()
                Button(action: store.addLayer) { Image(systemName: "plus") }
                    .help("Add an empty floor above the current floor")
                    .accessibilityLabel("Add floor")
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            Divider()

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(store.document.layers.reversed())) { layer in
                        VStack(spacing: 0) {
                            FloorLayerRow(store: store, layer: layer, isExpanded: expansionBinding(for: layer.id))
                            if expandedFloorIDs.contains(layer.id) {
                                floorContents(layer)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 80, idealHeight: 165, maxHeight: .infinity)

            Divider()
            HStack(spacing: 14) {
                Button(action: store.addLayer) {
                    Label("Add floor", systemImage: "plus.square")
                }
                .help("Create a blank floor and keep the other floors as references")
                Spacer(minLength: 0)
                Button(action: store.duplicateActiveLayer) {
                    Image(systemName: "square.on.square")
                }
                .help("Duplicate the selected floor")
                .accessibilityLabel("Duplicate selected floor")
                Button { store.removeLayer(id: store.activeLayer.id) } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.document.layers.count == 1)
                .help("Delete the selected floor; use Undo to restore it")
                .accessibilityLabel("Delete selected floor")
            }
            .font(.system(size: 10))
            .padding(.horizontal, 12)
            .frame(height: 30)
            Divider()

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Opacity")
                    Spacer()
                    Text("\(Int((store.activeLayer.opacity * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.system(size: 10))
                Slider(value: Binding(
                    get: { store.activeLayer.opacity },
                    set: { store.setLayerOpacity(id: store.activeLayer.id, opacity: $0) }
                ), in: 0...1, onEditingChanged: { editing in
                    if editing { store.beginLayerOpacityEdit() }
                    else { store.endLayerOpacityEdit() }
                })
                .controlSize(.small)
                .accessibilityLabel("Selected floor opacity")
                .accessibilityValue("\(Int((store.activeLayer.opacity * 100).rounded())) percent")
                .help("Fade this floor to trace or compare it with another floor")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: stateSymbol)
                Text(stateMessage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .buttonStyle(.borderless)
        .tint(.black)
        .background(.white)
        .onAppear { expandedFloorIDs.insert(store.activeLayer.id) }
        .onChange(of: store.activeLayer.id) { _, id in expandedFloorIDs.insert(id) }
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { expandedFloorIDs.contains(id) }, set: { expanded in
            if expanded { expandedFloorIDs.insert(id) }
            else { expandedFloorIDs.remove(id) }
        })
    }

    @ViewBuilder
    private func floorContents(_ layer: FloorLayer) -> some View {
        VStack(spacing: 1) {
            if layer.plan.walls.isEmpty && layer.plan.items.isEmpty && layer.plan.dimensions.isEmpty && layer.plan.areas.isEmpty {
                Text("No items yet").font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 30).padding(.vertical, 8)
            }
            ForEach(Array(layer.plan.walls.enumerated()), id: \.element.id) { index, wall in
                Button {
                    prepareSelection(in: layer)
                    store.selectWall(wall.id, extending: NSEvent.modifierFlags.contains(.shift))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.diagonal").frame(width: 13)
                        Text("Wall \(index + 1)")
                        Spacer(minLength: 4)
                        Text(store.unit.format(wall.length)).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.system(size: 10)).padding(.vertical, 6).padding(.leading, 29).padding(.trailing, 9)
                    .frame(maxWidth: .infinity)
                    .background(isSelected(wall: wall.id, in: layer) ? Color.black.opacity(0.08) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select Wall \(index + 1) on \(layer.name); Shift-click to extend the selection")
                .accessibilityLabel("Wall \(index + 1), \(store.unit.format(wall.length)), \(layer.name)")

                ForEach(layer.plan.openings.filter { $0.wallID == wall.id }) { opening in
                    Button {
                        prepareSelection(in: layer)
                        store.selectOpening(opening.id, extending: NSEvent.modifierFlags.contains(.shift))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: opening.kind == .door ? "door.left.hand.open" : "window.casement").frame(width: 13)
                            Text(opening.kind.rawValue.capitalized)
                            Spacer(minLength: 4)
                            Text(store.unit.format(opening.width)).font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.system(size: 9)).padding(.vertical, 5).padding(.leading, 44).padding(.trailing, 9)
                        .background(store.activeLayer.id == layer.id && store.selection.openingIDs.contains(opening.id) ? Color.black.opacity(0.08) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Select this \(opening.kind.rawValue) on Wall \(index + 1)")
                }
            }
            ForEach(layer.plan.items) { item in
                Button {
                    prepareSelection(in: layer)
                    store.selectItem(item.id, extending: NSEvent.modifierFlags.contains(.shift))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: objectCategorySymbol(item.kind.category)).frame(width: 13)
                        Text(item.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(itemDimensions(item))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.system(size: 10)).padding(.vertical, 6).padding(.leading, 29).padding(.trailing, 9)
                    .background(store.activeLayer.id == layer.id && store.selection.itemIDs.contains(item.id) ? Color.black.opacity(0.08) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select \(item.name) on \(layer.name); Shift-click to extend the selection")
                .accessibilityLabel("\(item.name), \(itemDimensions(item)), \(layer.name)")
            }
            ForEach(Array(layer.plan.dimensions.enumerated()), id: \.element.id) { index, dimension in
                Button {
                    prepareSelection(in: layer)
                    store.selectDimension(dimension.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ruler").frame(width: 13)
                        Text("Measure \(index + 1)")
                        Spacer(minLength: 4)
                        Text(store.unit.format(dimension.length)).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.system(size: 10)).padding(.vertical, 6).padding(.leading, 29).padding(.trailing, 9)
                    .background(store.activeLayer.id == layer.id && store.selectedDimensionID == dimension.id ? Color.black.opacity(0.08) : .clear)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            ForEach(layer.plan.areas) { area in
                Button {
                    prepareSelection(in: layer)
                    store.selectArea(area.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.dashed").frame(width: 13)
                        Text(area.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(store.unit.formatArea(area.areaSquareMillimetres))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.system(size: 10)).padding(.vertical, 6).padding(.leading, 29).padding(.trailing, 9)
                    .background(store.activeLayer.id == layer.id && store.selectedAreaID == area.id ? Color.black.opacity(0.08) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Select \(area.name) on \(layer.name)")
                .accessibilityLabel("\(area.name), \(store.unit.formatArea(area.areaSquareMillimetres)), \(layer.name)")
            }
        }
        .padding(.vertical, 3)
    }

    private func prepareSelection(in layer: FloorLayer) {
        if store.activeLayer.id != layer.id { store.selectLayer(id: layer.id) }
        store.chooseTool(.select)
    }

    private func itemDimensions(_ item: PlanItem) -> String {
        if item.isCircular { return "Ø \(store.unit.format(item.width))" }
        if item.kind == .line { return store.unit.format(item.width) }
        return "\(store.unit.format(item.width)) × \(store.unit.format(item.depth))"
    }

    private func isSelected(wall id: UUID, in layer: FloorLayer) -> Bool {
        store.activeLayer.id == layer.id && store.selection.wallIDs.contains(id)
    }

    private var stateSymbol: String {
        if !store.activeLayer.isVisible { return "eye.slash" }
        if store.activeLayer.isLocked { return "lock" }
        return "pencil"
    }

    private var stateMessage: String {
        if !store.activeLayer.isVisible { return "This floor is hidden. Show it to draw or edit." }
        if store.activeLayer.isLocked { return "This floor is locked. Unlock it to draw or edit." }
        return "Draw on the selected floor. Lock others to protect them."
    }
}

@MainActor
private struct FloorLayerRow: View {
    @ObservedObject var store: PlanStore
    let layer: FloorLayer
    @Binding var isExpanded: Bool
    @State private var draftName: String
    @State private var isRenaming = false
    @FocusState private var isNameFocused: Bool

    init(store: PlanStore, layer: FloorLayer, isExpanded: Binding<Bool>) {
        self.store = store
        self.layer = layer
        _isExpanded = isExpanded
        _draftName = State(initialValue: layer.name)
    }

    private var isSelected: Bool { store.activeLayer.id == layer.id }
    private var index: Int { store.document.layers.firstIndex { $0.id == layer.id } ?? 0 }

    var body: some View {
        HStack(spacing: 5) {
            Button { isExpanded.toggle() } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).frame(width: 12, height: 28)
            }
            .help(isExpanded ? "Collapse \(layer.name)" : "Show items in \(layer.name)")
            .accessibilityLabel(isExpanded ? "Collapse \(layer.name)" : "Expand \(layer.name)")
            Button { store.selectLayer(id: layer.id) } label: {
                ZStack {
                    Rectangle().fill(.white)
                    Rectangle().stroke(.black.opacity(0.5), lineWidth: 1)
                    Image(systemName: "square.split.bottomrightquarter")
                        .font(.system(size: 17, weight: .light))
                }
                .frame(width: 23, height: 28)
            }
            .accessibilityLabel("Select \(layer.name)")

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Floor name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .focused($isNameFocused)
                        .onSubmit(commitName)
                        .onKeyPress(.escape) {
                            draftName = layer.name
                            isRenaming = false
                            isNameFocused = false
                            return .handled
                        }
                        .accessibilityLabel("Floor name")
                } else {
                    Text(layer.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .onTapGesture(count: 2, perform: beginRename)
                        .help("Click to select; double-click to rename")
                }
                Text("\(layer.plan.walls.count) walls · \(layer.plan.items.count) objects · \(Int((layer.opacity * 100).rounded()))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { store.setLayerVisible(id: layer.id, visible: !layer.isVisible) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 26)
            }
            .help(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)")
            .accessibilityLabel(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)")

            Button { store.setLayerLocked(id: layer.id, locked: !layer.isLocked) } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 26)
            }
            .help(layer.isLocked ? "Unlock \(layer.name)" : "Lock \(layer.name) to protect its items")
            .accessibilityLabel(layer.isLocked ? "Unlock \(layer.name)" : "Lock \(layer.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isSelected ? Color.black.opacity(0.055) : .white)
        .overlay(Rectangle().stroke(.black.opacity(isSelected ? 0.8 : 0.13), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { store.selectLayer(id: layer.id) }
        .contextMenu {
            Button("Select Floor") { store.selectLayer(id: layer.id) }
            Button("Rename…", action: beginRename)
            Divider()
            Button("Move Up") { store.moveLayer(id: layer.id, to: index + 1) }
                .disabled(index >= store.document.layers.count - 1)
            Button("Move Down") { store.moveLayer(id: layer.id, to: index - 1) }
                .disabled(index == 0)
            Divider()
            Button(layer.isLocked ? "Unlock Floor" : "Lock Floor") {
                store.setLayerLocked(id: layer.id, locked: !layer.isLocked)
            }
            Button("Delete Floor") { store.removeLayer(id: layer.id) }
                .disabled(store.document.layers.count == 1)
        }
        .onChange(of: isNameFocused) { _, focused in
            if focused { store.selectLayer(id: layer.id) }
            else { commitName() }
        }
        .onChange(of: layer.name) { _, name in
            if !isNameFocused { draftName = name }
        }
    }

    private func beginRename() {
        store.selectLayer(id: layer.id)
        draftName = layer.name
        isRenaming = true
        DispatchQueue.main.async { isNameFocused = true }
    }

    private func commitName() {
        if draftName != layer.name { store.renameLayer(id: layer.id, name: draftName) }
        // Restore the saved name if validation rejected the draft.
        draftName = store.document.layers.first { $0.id == layer.id }?.name ?? layer.name
        isRenaming = false
        isNameFocused = false
    }
}
#endif
