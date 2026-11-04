#if os(macOS)
import SwiftUI
import BlueprintCore

/// Floors share one drawing origin, while each keeps its own editable geometry.
@MainActor
struct LayerPanel: View {
    @ObservedObject var store: PlanStore

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
                        FloorLayerRow(store: store, layer: layer)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 80, maxHeight: 144)

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
    @State private var draftName: String
    @State private var isRenaming = false
    @FocusState private var isNameFocused: Bool

    init(store: PlanStore, layer: FloorLayer) {
        self.store = store
        self.layer = layer
        _draftName = State(initialValue: layer.name)
    }

    private var isSelected: Bool { store.activeLayer.id == layer.id }
    private var index: Int { store.document.layers.firstIndex { $0.id == layer.id } ?? 0 }

    var body: some View {
        HStack(spacing: 7) {
            Button { store.selectLayer(id: layer.id) } label: {
                ZStack {
                    Rectangle().fill(.white)
                    Rectangle().stroke(.black.opacity(0.5), lineWidth: 1)
                    Image(systemName: "square.split.bottomrightquarter")
                        .font(.system(size: 17, weight: .light))
                }
                .frame(width: 28, height: 28)
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
                Text("\(layer.plan.walls.count) walls · \(Int((layer.opacity * 100).rounded()))%")
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
            .help(layer.isLocked ? "Unlock \(layer.name)" : "Lock \(layer.name) to protect its walls and openings")
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
