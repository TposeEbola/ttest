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
                Text(inputHint)
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
        .frame(width: 440, height: 330)
    }

    private var inputHint: String {
        switch store.unit {
        case .imperial: return "Enter feet and inches, such as 8' 6\" or 30 1/2in. Plain numbers mean inches."
        case .metric: return "Enter millimetres, such as 2400 or 152.4mm."
        case .mcChicken: return "A little easter egg: 1 McChicken = 4 inches (101.6 mm). Enter 3 McChickens or just 3. Your plan keeps its real dimensions."
        }
    }
}
#endif
