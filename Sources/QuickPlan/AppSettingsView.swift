#if os(macOS)
import SwiftUI
import BlueprintCore

@MainActor
struct AppSettingsView: View {
    @ObservedObject var store: PlanStore
    var body: some View {
        TabView {
            Form {
                Picker("Measurements", selection: $store.unit) {
                    ForEach(MeasurementUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                }.pickerStyle(.radioGroup)
                Text("Changes measurement labels and dimension inputs. Your plan keeps the same exact physical size.")
                    .font(.callout).foregroundStyle(.secondary)
                Text(store.unit == .imperial ? "Enter feet and inches, such as 8' 6\" or 30 1/2in. Plain numbers mean inches." : "Enter millimetres, such as 2400 or 152.4mm.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Units", systemImage: "ruler") }
            Form {
                Toggle("Snap to the drawing grid", isOn: $store.snapToGrid)
                Toggle("Keep new walls at right angles", isOn: $store.orthogonal)
                Toggle("Show grid", isOn: $store.showGrid)
                Toggle("Smart angle and measurement guides", isOn: $store.smartGuides)
                Text("Turn off snapping and right angles for freeform layouts. Walls can still connect to existing corners.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Drawing", systemImage: "pencil.and.outline") }
        }
        .padding(16)
        .frame(width: 440, height: 290)
    }
}
#endif
