import SwiftUI

/// Settings section: sign in to Rebrickable to bring in the sets you've already logged there.
struct RebrickableAccountSection: View {
    @Environment(AppStore.self) private var store
    @State private var username = ""
    @State private var password = ""
    @State private var signingIn = false
    @State private var message: String?
    @State private var showImport = false

    var body: some View {
        Section {
            if store.isSignedIn {
                Label("Signed in as \(store.rebrickableUsername)", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Palette.green)
                Button("Import my Rebrickable sets", systemImage: "square.and.arrow.down") { showImport = true }
                    .accessibilityIdentifier("importRebrickableSets")
                Button("Sign out of Rebrickable", role: .destructive) {
                    do { try store.signOut(); message = nil } catch { message = error.localizedDescription }
                }
            } else {
                TextField("Username or email", text: $username)
                    .textContentType(.username).autocorrectionDisabled().disableMobileAutocapitalization()
                    .accessibilityIdentifier("rebrickableUsername")
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("rebrickablePassword")
                Button {
                    signingIn = true
                } label: {
                    HStack {
                        Text("Sign in")
                        Spacer()
                        if signingIn { ProgressView() } else { Image(systemName: "arrow.right") }
                    }
                }.disabled(signingIn || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
            if let message { Text(verbatim: message).font(.footnote).foregroundStyle(Palette.muted) }
        } header: { Text("Your Rebrickable sets") } footer: {
            Text("Optional. Your password is sent once to Rebrickable to get a sign-in token; only the token is kept, in this device’s Keychain. Signed up with Google or Facebook? Set a password on Rebrickable first.")
        }
        .sheet(isPresented: $showImport) { RebrickableImportView() }
        .task(id: signingIn) {
            guard signingIn else { return }
            defer { signingIn = false }
            do {
                let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
                let token = try await store.client.signIn(username: name, password: password)
                try Task.checkCancellation()
                try store.saveSignIn(username: name, token: token)
                password = ""
                message = nil
                showImport = true
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }
}

/// Lists the signed-in user's Rebrickable sets and downloads their inventories into My sets.
struct RebrickableImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var owned: [OwnedSet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var queue: [LEGOSet] = []
    @State private var current: LEGOSet?
    @State private var failures: [String: String] = [:]
    @State private var importTask: Task<Void, Never>?

    private var newSets: [LEGOSet] { owned.map(\.set).filter { store.build($0.id) == nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if loading { ProgressView("Loading your Rebrickable sets…").frame(maxWidth: .infinity).padding(30) }
                    if let error {
                        InlineMessage(text: Text(verbatim: error))
                        Button("Try again") { Task { await load() } }.font(.subheadline.bold())
                    }
                    if !loading, error == nil {
                        if owned.isEmpty {
                            ContentUnavailableView("No sets on Rebrickable yet", systemImage: "shippingbox",
                                                   description: Text("Sets you add to your collection on Rebrickable will show up here."))
                        } else {
                            Text("\(owned.count) sets on Rebrickable · \(newSets.count) not yet in Brick by Brick")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                            Button {
                                startImport(newSets)
                            } label: {
                                if let current {
                                    HStack { ProgressView().tint(.white); Text("Gathering \(current.name)… (\(queue.count) left)") }
                                } else { Label("Add all new sets", systemImage: "square.and.arrow.down") }
                            }.buttonStyle(PrimaryButton()).disabled(newSets.isEmpty || current != nil)
                                .accessibilityIdentifier("importAllSets")
                            ForEach(owned) { entry in row(entry) }
                        }
                    }
                }.padding(24).pageWidth(700)
            }
            .background(Palette.background)
            .navigationTitle("Rebrickable sets").inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { importTask?.cancel(); dismiss() } } }
            .task { await load() }
            .onDisappear { importTask?.cancel() }
        }.macSheetSize(width: 560, height: 620)
    }

    private func row(_ entry: OwnedSet) -> some View {
        let saved = store.build(entry.id) != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                SetRow(set: entry.set, saved: saved, showsChevron: false)
                if !saved {
                    Button { startImport([entry.set]) } label: {
                        if current?.id == entry.id { ProgressView() } else { Image(systemName: "plus.circle.fill").font(.title2) }
                    }.buttonStyle(.plain).foregroundStyle(Palette.orange).disabled(current != nil)
                        .accessibilityLabel(Text("Add \(entry.set.name)"))
                }
            }
            if entry.quantity > 1 {
                Text("You own \(entry.quantity) copies; one checklist is kept per set.").font(.caption).foregroundStyle(Palette.muted)
            }
            if let failure = failures[entry.id] {
                Text(verbatim: failure).font(.caption).foregroundStyle(Palette.orange)
            }
        }
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { owned = try await store.client.ownedSets(userToken: store.userToken) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func startImport(_ sets: [LEGOSet]) {
        guard current == nil, !sets.isEmpty else { return }
        queue = sets
        importTask = Task { await runQueue() }
    }

    /// Downloads one set at a time and paces requests, since Rebrickable rate-limits API keys.
    @MainActor private func runQueue() async {
        defer { current = nil; queue = [] }
        while !queue.isEmpty, !Task.isCancelled {
            let set = queue.removeFirst()
            current = set
            failures[set.id] = nil
            var attempt = 0
            while true {
                do {
                    let parts = try await store.client.inventory(for: set)
                    store.add(set, parts: parts)
                    break
                } catch CatalogError.rateLimited where attempt < 2 {
                    attempt += 1
                    try? await Task.sleep(for: .seconds(5 * attempt))
                } catch {
                    if !Task.isCancelled { failures[set.id] = error.localizedDescription }
                    break
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
