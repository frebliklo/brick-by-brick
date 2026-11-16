import SwiftUI

/// The one home screen: your saved sets, plus search to add another.
struct SetsView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var results: [LEGOSet] = []
    @State private var nextPage: URL?
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var message: String?
    @State private var didSearch = false
    @State private var sheet: PresentedSheet?
    @State private var importError: String?
    @State private var importTask: Task<Void, Never>?
    @State private var removal: SavedBuild?
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    private var isSearchingCatalog: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private enum PresentedSheet: Identifiable {
        case settings, rebrickable, collection(CollectionArchive)
        var id: String {
            switch self {
            case .settings: "settings"
            case .rebrickable: "rebrickable"
            case .collection(let archive): "collection-\(archive.exportedAt.timeIntervalSince1970)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader

                    if !store.builds.isEmpty, !isSearchingCatalog {
                        Text("Your sets")
                            .font(.system(size: 35, weight: .bold, design: .rounded)).tracking(-1.1)
                            .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Every build starts\nwith a little finding.")
                                .font(.system(size: 35, weight: .bold, design: .rounded)).tracking(-1.1)
                                .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                            Text("Find your set. Gather your bricks. Build again.")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                    }

                    SoftSearchField(prompt: store.builds.isEmpty ? "Set name or number" : "Add a set by name or number",
                                    text: $query, large: true, identifier: "setSearch", clearLabel: "Clear search")

                    if !store.isConnected {
                        Button { sheet = .settings } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "link").font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Connect the LEGO catalog").font(.subheadline.bold())
                                    Text("Add your free Rebrickable API key").font(.caption)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.foregroundStyle(Palette.green).padding(17)
                                .background(Palette.greenTint, in: RoundedRectangle(cornerRadius: 17))
                        }.buttonStyle(.plain)
                    }

                    if store.isSignedIn, !isSearchingCatalog {
                        Button { sheet = .rebrickable } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "shippingbox.fill").font(.title2).foregroundStyle(.white)
                                    .frame(width: 48, height: 48).background(Palette.orange, in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Your Rebrickable sets").font(.headline).foregroundStyle(Palette.ink)
                                    Text("Pick sets you own to add here").font(.subheadline).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            }
                            .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line))
                            .contentShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("homeRebrickableSets")
                    }

                    if isSearchingCatalog {
                        if store.isConnected { searchResults }
                        else { InlineMessage(text: Text("Connect the catalog to search real LEGO sets by name or the number on your box.")) }
                    } else if store.builds.isEmpty {
                        introduction
                    } else {
                        savedSets
                    }
                }.padding(.horizontal, 24).padding(.bottom, 28).pageWidth(1400)
            }
            .background(Palette.background).hideMobileNavigationBar()
            .navigationDestination(for: LEGOSet.self) { SetDetailView(set: $0) }
            .sheet(item: $sheet) { item in
                switch item {
                case .settings: SettingsView(isSheet: true)
                case .rebrickable: NavigationStack { RebrickableSetsView(isSheet: true) }
                case .collection(let archive): CollectionImportView(archive: archive)
                }
            }
            .onOpenURL { url in
                importTask?.cancel()
                importTask = Task {
                    do {
                        let archive = try await Task.detached { try CollectionArchive.read(from: url) }.value
                        try Task.checkCancellation()
                        sheet = .collection(archive)
                    } catch {
                        if !Task.isCancelled { importError = error.localizedDescription }
                    }
                }
            }
            .alert("Couldn’t transfer collection", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(verbatim: importError ?? "") }
            .task(id: "\(query)|\(store.apiKey)") { await search() }
            .confirmationDialog("Remove this set and its saved progress?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                Button("Remove set", role: .destructive) { if let removal { store.remove(removal.id) }; removal = nil }
            }
        }
    }

    private var pageHeader: some View {
        HStack {
            Label("brick by brick", systemImage: "square.stack.3d.up.fill")
                .font(.system(.headline, design: .rounded)).foregroundStyle(Palette.ink)
            Spacer()
            Button {
                #if os(macOS)
                openSettings()
                #else
                sheet = .settings
                #endif
            } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("appSettings")
            .help(Text("Settings"))
        }.padding(.top, 12)
    }

    private var savedSets: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveCardGrid {
                ForEach(store.builds) { build in
                    NavigationLink { ChecklistView(buildID: build.id) } label: {
                        SavedBuildCard(build: build)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("saved-set-\(build.id)")
                        .contextMenu { Button("Remove set", systemImage: "trash", role: .destructive) { removal = build } }
                }
            }
            Group {
                #if os(macOS)
                Text("Saved on this Mac. Right-click a set to remove it.")
                #else
                Text("Saved on this device. Long-press a set to remove it.")
                #endif
            }.font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrickScene().frame(maxWidth: .infinity)
            HStack {
                Eyebrow(text: "A little practice")
                Spacer()
                Text("NO ACCOUNT NEEDED").font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            NavigationLink(value: SampleCatalog.set) { SetRow(set: SampleCatalog.set, saved: store.build(SampleCatalog.set.id) != nil) }
                .buttonStyle(.plain).accessibilityIdentifier("sampleSet")
            Text("Try the checklist with an original sample build. This is not an official LEGO set.")
                .font(.caption).foregroundStyle(Palette.muted).padding(.horizontal, 2)
        }.pageWidth(820)
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Find your next rebuild")
            if isSearching { ProgressView("Searching the catalog…").frame(maxWidth: .infinity).padding(30) }
            if let message {
                InlineMessage(text: Text(verbatim: message))
                Button("Try again") { Task { await search() } }.font(.subheadline.bold())
            }
            AdaptiveCardGrid {
                ForEach(results) { set in
                    NavigationLink(value: set) { SetRow(set: set, saved: store.build(set.id) != nil) }.buttonStyle(.plain)
                }
            }
            if didSearch && !isSearching && message == nil && results.isEmpty {
                ContentUnavailableView("No sets found", systemImage: "magnifyingglass",
                                       description: Text("Try a different name or the set number printed on your box."))
            }
            if let nextPage {
                Button { Task { await loadMore(nextPage) } } label: {
                    if isLoadingMore { ProgressView() } else { Text("Show more sets") }
                }.frame(maxWidth: .infinity).padding().disabled(isLoadingMore)
            }
        }
    }

    @MainActor private func search() async {
        let searchQuery = query
        results = []; nextPage = nil; message = nil; didSearch = false
        guard store.isConnected, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(400))
            let page = try await store.client.search(searchQuery)
            try Task.checkCancellation()
            guard query == searchQuery else { return }
            results = page.results; nextPage = page.next; didSearch = true; isSearching = false
        } catch {
            guard !Task.isCancelled, query == searchQuery else { return }
            message = error.localizedDescription; isSearching = false
        }
    }

    @MainActor private func loadMore(_ url: URL) async {
        let searchQuery = query
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await store.client.search(searchQuery, next: url)
            guard query == searchQuery, nextPage == url else { return }
            let existing = Set(results.map(\.id))
            results += page.results.filter { !existing.contains($0.id) }
            nextPage = page.next
        } catch {
            guard query == searchQuery else { return }
            message = error.localizedDescription
        }
    }
}

struct SetDetailView: View {
    let set: LEGOSet
    @Environment(AppStore.self) private var store
    @State private var loading = false
    @State private var error: String?
    @State private var openChecklist = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if set.isSample { BrickScene().frame(maxWidth: .infinity) }
                else {
                    CatalogImage(url: set.setImgUrl).frame(height: 240).frame(maxWidth: .infinity)
                        .imageWell(cornerRadius: 26)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: set.isSample ? LocalizedStringKey("Practice collection") : LocalizedStringKey("Set \(set.setNum)"))
                    Text(set.name).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(Palette.ink)
                    Text("\(set.numParts) pieces · \(String(set.year))").foregroundStyle(Palette.muted)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Label("A place for every piece", systemImage: "checklist").font(.headline)
                    Text("Get a visual checklist of every brick and color. Count pieces as you find them, and pick up exactly where you left off.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Label("Your progress saves on this device", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(Palette.green)
                }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                if set.isSample { InlineMessage(text: Text("This original sample has 32 pieces. It demonstrates the checklist and is not an official LEGO set inventory.")) }
                if let error { InlineMessage(text: Text(verbatim: error)) }
                Button {
                    if store.build(set.id) != nil { openChecklist = true }
                    else { loading = true }
                } label: {
                    if loading { HStack { ProgressView().tint(.white); Text("Gathering the parts list…") } }
                    else { Label(store.build(set.id) == nil ? LocalizedStringKey("Start finding bricks") : LocalizedStringKey("Continue checklist"), systemImage: "arrow.right") }
                }.buttonStyle(PrimaryButton()).disabled(loading).accessibilityIdentifier("startChecklist")
                if !set.isSample {
                    Link("Inventory provided by Rebrickable ↗", destination: URL(string: "https://rebrickable.com/sets/\(set.setNum)/")!)
                        .font(.caption).frame(maxWidth: .infinity)
                }
            }.padding(24).pageWidth(700)
        }.background(Palette.background).navigationTitle("Your next build").compactNavigationTitle()
            .navigationDestination(isPresented: $openChecklist) { ChecklistView(buildID: set.id) }
            .task(id: loading) {
                guard loading else { return }
                do {
                    error = nil
                    let parts = set.isSample ? SampleCatalog.parts : try await store.client.inventory(for: set)
                    try Task.checkCancellation()
                    if store.add(set, parts: parts) { openChecklist = true }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                loading = false
            }
    }
}
