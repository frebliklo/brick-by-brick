import SwiftUI

struct SettingsView: View {
    var isSheet = false
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message: String?
    @State private var validating = false
    @State private var confirmDisconnect = false

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
                    Label(store.isConnected ? LocalizedStringKey("Catalog connected") : LocalizedStringKey("Connect your catalog"), systemImage: store.isConnected ? "checkmark.circle.fill" : "link")
                        .foregroundStyle(store.isConnected ? Palette.green : Palette.ink)
                    Text("Use a free Rebrickable API key to search LEGO sets and download their complete brick inventories.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Link("1. Create a free Rebrickable account ↗", destination: URL(string: "https://rebrickable.com/register/")!)
                    Link("2. Get a key from Rebrickable’s API page ↗", destination: URL(string: "https://rebrickable.com/api/")!)
                    SecureField("3. Paste your API key", text: $key)
                        .textContentType(.password).autocorrectionDisabled().disableMobileAutocapitalization()
                        .accessibilityIdentifier("apiKeyInput")
                    Button {
                        validating = true
                    } label: {
                        HStack {
                            Text(store.isConnected ? LocalizedStringKey("Verify and update key") : LocalizedStringKey("Connect catalog"))
                            Spacer()
                            if validating { ProgressView() } else { Image(systemName: "arrow.right") }
                        }
                    }.disabled(validating || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let message { Text(message).font(.footnote).foregroundStyle(Palette.muted) }
                    if store.isConnected {
                        Button("Disconnect catalog", role: .destructive) { confirmDisconnect = true }
                    }
                } header: { Text("Rebrickable catalog") } footer: {
                    Text("Your key is stored in this device’s Keychain and sent only to Rebrickable. Saved sets and checklist progress remain available offline.")
                }
                if store.isConnected { RebrickableAccountSection() }
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
                .task(id: validating) {
                    guard validating else { return }
                    do {
                        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        _ = try await CatalogClient(apiKey: cleaned).search("31124")
                        try Task.checkCancellation()
                        try store.saveKey(cleaned)
                        key = ""
                        message = Localization.string("Connected. You’re ready to find your sets.")
                    } catch { if !Task.isCancelled { message = error.localizedDescription } }
                    validating = false
                }
                .confirmationDialog("Disconnect the catalog? Your saved checklists will stay on this device.", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                    Button("Disconnect", role: .destructive) {
                        do { try store.saveKey(""); message = nil; key = "" }
                        catch { message = error.localizedDescription }
                    }
                }
        }.macSheetSize(width: 540, height: 540)
    }
}
