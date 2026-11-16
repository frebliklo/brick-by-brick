import SwiftUI

struct SettingsView: View {
    var isSheet = false
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill").font(.title).foregroundStyle(Palette.orange)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Brick by Brick").font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Less searching. More building.").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                    }.padding(.vertical, 12)
                }
                Section {
                    NavigationLink { CatalogConnectionView() } label: {
                        ConnectionRow(title: "LEGO catalog",
                                      status: store.isConnected ? Text("Connected") : Text("Not set up yet"),
                                      connected: store.isConnected, systemImage: "magnifyingglass")
                    }.accessibilityIdentifier("catalogSettings")
                    NavigationLink { RebrickableAccountView() } label: {
                        ConnectionRow(title: "Rebrickable sets",
                                      status: store.isSignedIn ? Text("Signed in as \(store.rebrickableUsername)") : Text("Sign in to bring in your sets"),
                                      connected: store.isSignedIn, systemImage: "shippingbox")
                    }.accessibilityIdentifier("rebrickableSettings")
                } header: { Text("Rebrickable") } footer: {
                    Text("Saved sets and checklist progress stay on this device and work offline.")
                }
                CollectionTransferSection()
                Section {
                    @Bindable var store = store
                    Picker("Theme", selection: $store.appearance) {
                        Label("System default", systemImage: "circle.lefthalf.filled").tag(AppAppearance.system)
                        Label("Light", systemImage: "sun.max").tag(AppAppearance.light)
                        Label("Dark", systemImage: "moon").tag(AppAppearance.dark)
                    }.accessibilityIdentifier("appearancePicker")
                } header: { Text("Appearance") } footer: {
                    Text("System default follows your device’s light or dark setting.")
                }
                Section {
                    @Bindable var store = store
                    Picker("App language", selection: $store.language) {
                        Text("System default").tag(AppLanguage.system)
                        Text(verbatim: "English").tag(AppLanguage.english)
                        Text(verbatim: "Dansk").tag(AppLanguage.danish)
                    }.accessibilityIdentifier("languagePicker")
                } header: { Text("Language") } footer: {
                    Text("Choose the language used in the app. System default follows your device’s language.")
                }
                Section("About your collection") {
                    Label("Progress is saved automatically", systemImage: "checkmark.shield")
                    Label("No app account required", systemImage: "person.crop.circle")
                    Label("Stored locally on this device", systemImage: "internaldrive")
                    Text("Images need an internet connection when not cached. Checklists include minifigure parts when supplied by the catalog; spare pieces are optional.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                Section {
                    Link("Catalog data & images: Rebrickable ↗", destination: URL(string: "https://rebrickable.com")!)
                    Text("An independent app for your brick collection. Not affiliated with or endorsed by the LEGO Group or Rebrickable. LEGO is a trademark of the LEGO Group.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }.desktopFormStyle().scrollContentBackground(.hidden).pageWidth(760).background(Palette.background)
                .navigationTitle("Settings").inlineNavigationTitle()
                .toolbar { if isSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        }.macSheetSize(width: 540, height: 540)
    }
}
