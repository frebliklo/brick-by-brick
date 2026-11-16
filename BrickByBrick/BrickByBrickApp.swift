import SwiftUI

@main
struct BrickByBrickApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        #if os(macOS)
        Window("Brick by Brick", id: "main") {
            appContent.frame(minWidth: 640, minHeight: 540)
        }
        .defaultSize(width: 1040, height: 800)
        .windowResizability(.contentMinSize)
        Settings {
            SettingsView().environment(store)
                .environment(\.locale, store.locale)
                .tint(Palette.orange)
                .frame(width: 640, height: 700)
        }
        #else
        WindowGroup {
            appContent
        }
        #endif
    }

    private var appContent: some View {
        RootView()
            .environment(store)
            .tint(Palette.orange)
            .appearance(store.appearance)
            .alert("Couldn’t save your collection", isPresented: Binding(
                get: { store.storageError != nil },
                set: { if !$0 { store.storageError = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(verbatim: store.storageError ?? "")
            }
            .environment(\.locale, store.locale)
    }
}

struct RootView: View {
    var body: some View { SetsView() }
}

private extension View {
    /// On macOS the app-wide appearance also covers the Settings window and sheets,
    /// and reliably returns to the system setting.
    @ViewBuilder func appearance(_ appearance: AppAppearance) -> some View {
        #if os(macOS)
        onChange(of: appearance, initial: true) { _, value in
            NSApp.appearance = switch value {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        #else
        preferredColorScheme(appearance.colorScheme)
        #endif
    }
}
