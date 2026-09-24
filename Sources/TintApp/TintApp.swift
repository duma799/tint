#if os(macOS)
import AppKit
import SwiftUI
import TintCore

@main
struct TintApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("tint", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 1180, height: 800)

        // Always there: the current scheme, a mode switch, re-theme now.
        MenuBarExtra("tint", systemImage: "drop.fill") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
#else
/// The app is SwiftUI, so macOS only; this keeps `swift build` working elsewhere.
@main
enum TintApp {
    static func main() { print("The tint app runs on macOS.") }
}
#endif
