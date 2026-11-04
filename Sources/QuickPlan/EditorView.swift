#if os(macOS)
import SwiftUI
import AppKit
import BlueprintCore

@MainActor
struct EditorView: View {
    @ObservedObject var store: PlanStore
    @State private var library = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 224)
                Divider()
                VStack(spacing: 0) {
                    canvasToolbar
                    Divider()
                    PlanCanvas(store: store)
                }
                Divider()
                VStack(spacing: 0) {
                    LayerPanel(store: store).frame(height: 310)
                    Divider()
                    inspector
                }.frame(width: 264)
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text(store.status).lineLimit(2).textSelection(.enabled)
                Spacer(minLength: 8)
                Text("\(store.plan.walls.count) WALLS  /  \(store.plan.openings.count) OPENINGS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 11))
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .background(.white)
        .foregroundStyle(.black)
        .background(WindowCloseGuard(store: store))
        .onAppear {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .onOpenURL { store.open(url: $0) }
        .onChange(of: store.tool) { _, tool in
            if tool == .door || tool == .window { library = true }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Rectangle().fill(.black).frame(width: 32, height: 32)
                Image(systemName: "square.split.bottomrightquarter").font(.system(size: 20)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("QUICKPLAN").font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(2)
                Text("A little space for big ideas.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.name + (store.isDirty ? " •" : ""))
                .font(.system(size: 13, weight: .medium))
            Text("FLOOR PLAN").font(.system(size: 9, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .overlay(Rectangle().stroke(.black.opacity(0.2)))
            Spacer()
            Button(action: store.open) { Label("Open", systemImage: "folder") }
            Button(action: store.save) { Label("Save", systemImage: "square.and.arrow.down") }
            Button(action: store.exportSVG) { Label("Export SVG", systemImage: "arrow.up.right") }
                .buttonStyle(BlackButtonStyle())
                .help("Export the active floor only, without reference layers")
            SettingsLink { Label("Settings", systemImage: "gearshape") }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                tab("DRAW", active: !library) { library = false; store.chooseTool(.wall) }
                tab("OBJECTS", active: library) { library = true }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if library { objectLibrary } else { drawPanel }
                }
                .padding(16)
            }
            Spacer(minLength: 0)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("MAKE ROOM.").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                Text("Every good plan starts\nwith a simple line.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            .padding(18)
        }
    }

    private var drawPanel: some View {
        Group {
            eyebrow("01 / DRAWING TOOLS")
            VStack(spacing: 8) {
                toolButton(.select, subtitle: "Select & inspect")
                toolButton(.wall, subtitle: "Click corners to connect")
            }
            Divider()
            DefaultThicknessEditor(store: store)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("DRAWING AIDS")
                Toggle("Smart guides", isOn: $store.smartGuides)
                Toggle("Orthogonal walls", isOn: $store.orthogonal)
                Toggle("Snap to grid", isOn: $store.snapToGrid)
                Toggle("Show grid", isOn: $store.showGrid)
                Text("Snap to existing corners or a \(store.unit == .imperial ? "6-inch" : "100 mm") grid. Turn aids off to draw freely; use the inspector for exact dimensions.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("DISPLAY UNITS")
                Picker("Units", selection: $store.unit) {
                    ForEach(DisplayUnit.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
                Text(unitInputHint(store.unit))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var objectLibrary: some View {
        Group {
            eyebrow("02 / OPENINGS")
            Text("The finishing touches.").font(.system(size: 19, weight: .semibold))
            Text("Choose an opening, then click a wall to place it.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            HStack(spacing: 6) {
                objectTab(.door)
                objectTab(.window)
            }
            VStack(spacing: 8) {
                ForEach(store.tool == .window ? OpeningPreset.windows : OpeningPreset.doors) { preset in
                    Button {
                        if store.tool != .window && store.tool != .door { store.chooseTool(.door) }
                        store.applyPreset(preset)
                    } label: {
                        HStack {
                            Image(systemName: store.tool == .window ? "window.casement" : "door.left.hand.open")
                                .font(.system(size: 22, weight: .light)).frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).font(.system(size: 11, weight: .semibold))
                                Text("\(store.unit.format(preset.width)) × \(store.unit.format(preset.height))")
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.openingWidth == preset.width && store.openingHeight == preset.height ? Color.black.opacity(0.05) : .white)
                        .overlay(Rectangle().stroke(.black.opacity(store.openingWidth == preset.width && store.openingHeight == preset.height ? 0.7 : 0.15)))
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("CUSTOM SIZE / \(unitAbbreviation(store.unit))")
                numberField("Width", value: $store.openingWidth, unit: store.unit)
                numberField("Height", value: $store.openingHeight, unit: store.unit)
                Text(unitInputHint(store.unit)).font(.system(size: 10)).foregroundStyle(.secondary)
                Text("Common nominal sizes are starting points. Confirm actual product and rough-opening dimensions before building.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }

    private var canvasToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: store.tool.symbol)
            Text(store.tool.title.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
            Divider().frame(height: 16)
            Button(action: store.undo) { Image(systemName: "arrow.uturn.backward") }.disabled(!store.canUndo).help("Undo (⌘Z)")
            Button(action: store.redo) { Image(systemName: "arrow.uturn.forward") }.disabled(!store.canRedo).help("Redo (⇧⌘Z)")
            RotationControls(store: store, compact: true)
            Spacer()
            Label(store.activeLayer.name, systemImage: store.activeLayer.isLocked ? "lock" : "square.3.layers.3d")
                .font(.system(size: 10)).lineLimit(1).help("Active floor")
            Button { store.zoom = max(0.00001, store.zoom / 1.25) } label: { Image(systemName: "minus") }.help("Zoom out")
            Text("\(Int((store.zoom / 0.08 * 100).rounded()))%")
                .font(.system(size: 10, design: .monospaced)).frame(width: 40)
            Button { store.zoom = min(0.8, store.zoom * 1.25) } label: { Image(systemName: "plus") }.help("Zoom in")
            Button(action: store.fit) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Fit drawing")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16).frame(height: 43)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                eyebrow("INSPECTOR")
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.system(size: 12))
            }.padding(16).frame(height: 43)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.selection.wallIDs.count + store.selection.openingIDs.count > 1 {
                        Text("Selection").font(.system(size: 23, weight: .semibold))
                        Text("\(store.selection.wallIDs.count) walls · \(store.selection.openingIDs.count) openings")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        RotationControls(store: store)
                        Button("Copy selected items", action: store.copySelection).buttonStyle(BlackButtonStyle())
                        Text("Shift-click to add or remove items from the selection. Doors and windows stay attached to their walls when a group is copied or rotated.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    } else if let opening = store.selectedOpening {
                        OpeningInspector(store: store, opening: opening).id(opening.id)
                    } else if let wall = store.selectedWall {
                        WallInspector(store: store, wall: wall).id(wall.id)
                    } else {
                        Image(systemName: "viewfinder").font(.system(size: 32, weight: .ultraLight)).padding(.top, 30)
                        Text("Precision, by design.").font(.system(size: 19, weight: .semibold))
                        Text("Select a wall, door, or window to edit its exact measurements.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        Divider()
                        eyebrow("ACTIVE FLOOR / \(store.activeLayer.name.uppercased())")
                        summaryRow("Walls", "\(store.plan.walls.count)")
                        summaryRow("Doors", "\(store.plan.openings.filter { $0.kind == .door }.count)")
                        summaryRow("Windows", "\(store.plan.openings.filter { $0.kind == .window }.count)")
                        summaryRow("Wall length", store.unit.format(store.plan.walls.reduce(0) { $0 + $1.length }))
                        Divider()
                        Text("Dimensions measure wall centre lines. Wall thickness is drawn equally on each side.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }.padding(18)
            }
            Spacer(minLength: 0)
            if !store.selection.isEmpty {
                Divider()
                Button(action: store.deleteSelection) { Label("Delete selected", systemImage: "trash") }
                    .buttonStyle(.borderless).padding(18)
            }
        }
    }

    private func tab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(active ? .white : .black)
                .background(active ? Color.black : Color.white)
                .overlay(Rectangle().stroke(.black))
        }.buttonStyle(.plain)
    }
    private func toolButton(_ tool: EditorTool, subtitle: String) -> some View {
        Button { store.chooseTool(tool) } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol).frame(width: 23).font(.system(size: 20, weight: .light))
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.title).font(.system(size: 12, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).opacity(0.65)
                }
                Spacer(minLength: 0)
            }
            .padding(12).foregroundStyle(store.tool == tool ? .white : .black)
            .background(store.tool == tool ? Color.black : .white)
            .overlay(Rectangle().stroke(.black.opacity(0.2)))
        }.buttonStyle(.plain)
    }
    private func objectTab(_ tool: EditorTool) -> some View {
        tab(tool.title.uppercased(), active: store.tool == tool) { store.chooseTool(tool) }
    }
}

@MainActor
private struct WallInspector: View {
    @ObservedObject var store: PlanStore
    let wall: Wall
    @State private var startX = 0.0
    @State private var startY = 0.0
    @State private var endX = 0.0
    @State private var endY = 0.0
    @State private var thickness = 150.0
    @State private var length = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wall").font(.system(size: 24, weight: .semibold))
            Text(store.unit.format(wall.length)).font(.system(size: 12, design: .monospaced))
            RotationControls(store: store)
            Divider()
            eyebrow("LENGTH / \(unitAbbreviation(store.unit))")
            numberField("Length", value: $length, unit: store.unit)
            Button("Apply length") {
                guard length.isFinite, length >= 1 else {
                    store.report("Enter a positive wall length of at least 1 mm.")
                    return
                }
                let factor = length / wall.length
                store.updateWall(id: wall.id, start: wall.start,
                                 end: PlanPoint(x: wall.start.x + (wall.end.x - wall.start.x) * factor,
                                                y: wall.start.y + (wall.end.y - wall.start.y) * factor), thickness: wall.thickness)
            }.buttonStyle(BlackButtonStyle())
            Text("Keeps the start point and direction. Connected corners move with the endpoint.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            Divider()
            eyebrow("GEOMETRY / \(unitAbbreviation(store.unit))")
            numberField("Start X", value: $startX, unit: store.unit)
            numberField("Start Y", value: $startY, unit: store.unit)
            numberField("End X", value: $endX, unit: store.unit)
            numberField("End Y", value: $endY, unit: store.unit)
            numberField("Thickness", value: $thickness, unit: store.unit)
            Text(unitInputHint(store.unit)).font(.system(size: 10)).foregroundStyle(.secondary)
            Button("Apply geometry") {
                store.updateWall(id: wall.id, start: PlanPoint(x: startX, y: startY),
                                 end: PlanPoint(x: endX, y: endY), thickness: thickness)
            }.buttonStyle(BlackButtonStyle())
        }
        .onAppear(perform: populate)
        .onChange(of: wall) { _, _ in populate() }
    }
    private func populate() {
        startX = wall.start.x; startY = wall.start.y; endX = wall.end.x; endY = wall.end.y
        thickness = wall.thickness; length = wall.length
    }
}

@MainActor
private struct OpeningInspector: View {
    @ObservedObject var store: PlanStore
    let opening: Opening
    @State private var offset = 0.0
    @State private var width = 0.0
    @State private var height = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(opening.kind.rawValue.capitalized).font(.system(size: 24, weight: .semibold))
            Text("\(store.unit.format(opening.width)) wide").font(.system(size: 12, design: .monospaced))
            Divider()
            eyebrow("DIMENSIONS / \(unitAbbreviation(store.unit))")
            numberField("Width", value: $width, unit: store.unit)
            numberField("Height", value: $height, unit: store.unit)
            numberField("Position", value: $offset, unit: store.unit)
            Text(unitInputHint(store.unit)).font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Position is measured from the wall’s start point to the centre of this opening.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Button("Apply dimensions") {
                store.updateOpening(id: opening.id, offset: offset, width: width, height: height)
            }.buttonStyle(BlackButtonStyle())
            Divider()
            Text("Openings must fit entirely within a wall and cannot overlap another opening.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }
        .onAppear(perform: populate)
        .onChange(of: opening) { _, _ in populate() }
    }
    private func populate() { offset = opening.offset; width = opening.width; height = opening.height }
}

@MainActor
private struct DefaultThicknessEditor: View {
    @ObservedObject var store: PlanStore
    @State private var thickness = 150.0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("WALL THICKNESS")
            HStack(spacing: 6) {
                ForEach(store.unit == .imperial ? [101.6, 152.4, 203.2] : [100.0, 150.0, 200.0], id: \.self) { value in
                    Button(store.unit == .imperial ? "\(Int((value / 25.4).rounded()))\"" : "\(Int(value))") { store.setDefaultThickness(value) }
                        .buttonStyle(.bordered)
                }
            }
            numberField("Custom", value: $thickness, unit: store.unit)
            Button("Set default") { store.setDefaultThickness(thickness) }.buttonStyle(.bordered)
            Text("Used for new walls. Select a wall to change its individual thickness.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
        }
        .onAppear { thickness = store.plan.defaultWallThickness }
        .onChange(of: store.plan.defaultWallThickness) { _, value in thickness = value }
    }
}

private func eyebrow(_ title: String) -> some View {
    Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
}
private func numberField(_ title: String, value: Binding<Double>, unit: MeasurementUnit) -> some View {
    HStack {
        Text(title).font(.system(size: 11)).frame(width: 62, alignment: .leading)
        TextField(title, value: value, format: LengthFormat(unit: unit))
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            .font(.system(size: 12, design: .monospaced)).accessibilityLabel("\(title) in \(unit.rawValue)")
            .help(unitInputHint(unit))
    }
}
private func unitAbbreviation(_ unit: MeasurementUnit) -> String { unit == .imperial ? "FT + IN" : "MM" }
private func unitInputHint(_ unit: MeasurementUnit) -> String {
    unit == .imperial ? "Enter 8' 6\", 30in, or 30 1/2in. Plain numbers are inches." : "Enter dimensions in millimetres."
}

struct LengthFormat: ParseableFormatStyle {
    var unit: MeasurementUnit
    func format(_ value: Double) -> String { unit.inputString(value) }
    var parseStrategy: LengthParseStrategy { LengthParseStrategy(unit: unit) }
}

struct LengthParseStrategy: ParseStrategy {
    var unit: MeasurementUnit
    func parse(_ value: String) throws -> Double { try unit.parse(value) }
}
private func summaryRow(_ title: String, _ value: String) -> some View {
    HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 11))
}
struct BlackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(.white).background(.black.opacity(configuration.isPressed ? 0.7 : 1))
    }
}

@MainActor
private struct WindowCloseGuard: NSViewRepresentable {
    let store: PlanStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> NSView {
        let view = WindowHookView()
        view.closeDelegate = context.coordinator
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    class WindowHookView: NSView {
        var closeDelegate: Coordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let closeDelegate else { return }
            if window.delegate !== closeDelegate {
                closeDelegate.previousDelegate = window.delegate
                window.delegate = closeDelegate
            }
        }
    }
    @MainActor
    class Coordinator: NSObject, NSWindowDelegate {
        let store: PlanStore
        weak var previousDelegate: NSWindowDelegate?
        init(store: PlanStore) { self.store = store }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            store.confirmClose() && (previousDelegate?.windowShouldClose?(sender) ?? true)
        }
        func windowWillClose(_ notification: Notification) { previousDelegate?.windowWillClose?(notification) }
        func windowDidResize(_ notification: Notification) { previousDelegate?.windowDidResize?(notification) }
        func windowDidBecomeKey(_ notification: Notification) { previousDelegate?.windowDidBecomeKey?(notification) }
        func windowDidResignKey(_ notification: Notification) { previousDelegate?.windowDidResignKey?(notification) }
    }
}
#endif
