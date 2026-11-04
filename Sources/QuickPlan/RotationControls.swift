#if os(macOS)
import SwiftUI

@MainActor
struct RotationControls: View {
    @ObservedObject var store: PlanStore
    var compact = false
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            if compact { Image(systemName: "rotate.right") }
            else { Label("Rotate selection…", systemImage: "rotate.right") }
        }
        .disabled(!store.canRotateSelection)
        .help(store.selectedOpening?.kind == .door ? "Rotate the door around its hinge" : "Rotate selected objects or walls and their attached openings")
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            RotationPopover(store: store) { isPresented = false }
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { store.cancelRotation() }
        }
    }
}

@MainActor
private struct RotationPopover: View {
    @ObservedObject var store: PlanStore
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("ROTATE SELECTION").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                Spacer()
                Button { store.cancelRotation(); dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Cancel rotation")
            }
            RotationDial(store: store).frame(width: 230, height: 230)
            HStack {
                Text("Rotation").font(.system(size: 12))
                TextField("Degrees", value: Binding(get: { store.rotationDegrees }, set: { store.previewRotation($0) }),
                          format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 90)
                    .accessibilityLabel("Rotation in degrees")
                Text("°")
            }
            if let guide = store.rotationGuideDegrees {
                Label("Aligned at \(guide.formatted(.number.precision(.fractionLength(0...1))))°", systemImage: "scope")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.blue)
            } else {
                Text("Drag the circle or enter an exact angle.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(store.selectedOpening?.kind == .door
                 ? "Rotate the door around its hinge. Its opening stays in the wall."
                 : "Selected objects and walls rotate together. Attached openings follow their walls; unselected items stay in place.")
                .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Cancel") { store.cancelRotation(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply rotation") { store.commitRotation(); dismiss() }
                    .buttonStyle(BlackButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 280)
        .background(.white).foregroundStyle(.black)
        .onAppear { store.beginRotation() }
        .onDisappear { store.cancelRotation() }
    }
}

@MainActor
private struct RotationDial: View {
    @ObservedObject var store: PlanStore

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) / 2 - 25
            let radians = store.rotationDegrees * .pi / 180
            let handle = CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
            ZStack {
                Canvas { context, _ in
                    let ring = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: ring), with: .color(.black.opacity(0.4)), lineWidth: 1)
                    for degrees in stride(from: 0, to: 360, by: 15) {
                        let angle = Double(degrees) * .pi / 180
                        let major = degrees % 45 == 0
                        var tick = Path()
                        tick.move(to: CGPoint(x: center.x + cos(angle) * (radius - (major ? 10 : 5)),
                                             y: center.y + sin(angle) * (radius - (major ? 10 : 5))))
                        tick.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                        context.stroke(tick, with: .color(.black.opacity(major ? 0.8 : 0.25)), lineWidth: 1)
                        if degrees % 90 == 0 {
                            let point = CGPoint(x: center.x + cos(angle) * (radius + 17), y: center.y + sin(angle) * (radius + 17))
                            context.draw(Text("\(degrees)°").font(.system(size: 9, design: .monospaced)).foregroundColor(.black), at: point)
                        }
                    }
                    var pointer = Path()
                    pointer.move(to: center); pointer.addLine(to: handle)
                    context.stroke(pointer, with: .color(store.rotationGuideDegrees == nil ? .black : .blue), lineWidth: 1.5)
                }
                VStack(spacing: 3) {
                    Text("\(store.rotationDegrees.formatted(.number.precision(.fractionLength(0...1))))°")
                        .font(.system(size: 27, weight: .light, design: .monospaced))
                    Text("ROTATION").font(.system(size: 8, design: .monospaced)).tracking(1)
                }
                .padding(6).background(.white)
                Circle().fill(store.rotationGuideDegrees == nil ? Color.black : .blue)
                    .frame(width: 13, height: 13).position(handle)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let x = value.location.x - center.x
                let y = value.location.y - center.y
                guard hypot(x, y) > 8 else { return }
                store.previewRotation(atan2(y, x) * 180 / .pi)
            })
        }
        .accessibilityLabel("Circular rotation control")
        .accessibilityValue("\(store.rotationDegrees) degrees")
        .accessibilityHint("Drag around the circle or use the degree field below.")
    }
}
#endif
