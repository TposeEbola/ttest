#if os(macOS)
import SwiftUI
import AppKit

@main
@MainActor
struct QuickPlanApp: App {
    @StateObject private var store = PlanStore()
    @NSApplicationDelegateAdaptor(QuickPlanAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EditorView(store: store)
                .onAppear { appDelegate.store = store }
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(.light)
                .tint(.black)
        }
        .defaultSize(width: 1440, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Plan…", action: store.newPlan).keyboardShortcut("n")
                Button("Open Plan…", action: store.open).keyboardShortcut("o")
                Button("Save", action: store.save).keyboardShortcut("s")
                Button("Save As…", action: store.saveAs).keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Export Active Floor SVG…", action: store.exportSVG).keyboardShortcut("e")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: store.undo).keyboardShortcut("z")
                Button("Redo", action: store.redo).keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
                Button("Copy", action: store.copySelection).keyboardShortcut("c")
                Button("Paste", action: store.pasteSelection).keyboardShortcut("v")
                Button("Paste in Place", action: store.pasteInPlace).keyboardShortcut("v", modifiers: [.command, .shift])
                Divider()
                Button("Select All", action: store.selectAll).keyboardShortcut("a")
            }
        }
        Settings {
            AppSettingsView(store: store)
                .preferredColorScheme(.light)
                .tint(.black)
        }
    }
}

@MainActor
final class QuickPlanAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: PlanStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (store?.confirmClose() ?? true) ? .terminateNow : .terminateCancel
    }
}
#else
import Foundation
@main
struct QuickPlanUnsupportedPlatform {
    static func main() {
        print("QuickPlan’s interface requires macOS 14 or later. Run swift test to validate BlueprintCore on Linux.")
    }
}
#endif
