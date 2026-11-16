import SwiftUI

/// The signed-in user's Rebrickable sets: pick the ones to add, then download them in one go.
/// Pushed from the account page, or presented from the home screen with `isSheet`.
struct RebrickableSetsView: View {
    var isSheet = false
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var owned: [OwnedSet] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var selected: Set<String> = []
    @State private var queue: [LEGOSet] = []
    @State private var total = 0
    @State private var current: LEGOSet?
    @State private var failures: [String: String] = [:]
    @State private var importTask: Task<Void, Never>?

    private var isImporting: Bool { current != nil }
    private var newSets: [OwnedSet] { owned.filter { store.build($0.id) == nil } }
    private var addedSets: [OwnedSet] { owned.filter { store.build($0.id) != nil } }

    private func matches(_ entry: OwnedSet) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        return entry.set.name.localizedCaseInsensitiveContains(text) || entry.set.setNum.localizedCaseInsensitiveContains(text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if loading {
                    ProgressView("Loading your Rebrickable sets…").frame(maxWidth: .infinity).padding(40)
                } else if let error {
                    InlineMessage(text: Text(verbatim: error))
                    Button("Try again") { Task { await load() } }.font(.subheadline.bold())
                } else if owned.isEmpty {
                    ContentUnavailableView("No sets on Rebrickable yet", systemImage: "shippingbox",
                                           description: Text("Sets you add to your collection on Rebrickable will show up here."))
                } else {
                    if owned.count > 6 {
                        SoftSearchField(prompt: "Find a set", text: $query, identifier: "rebrickableSetSearch", clearLabel: "Clear search")
                    }
                    newSection
                    addedSection
                }
            }.padding(.horizontal, 24).padding(.vertical, 12).pageWidth(820)
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom) { if !owned.isEmpty && (!newSets.isEmpty || isImporting) { actionBar } }
        .navigationTitle("Rebrickable sets").compactNavigationTitle()
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { importTask?.cancel(); dismiss() } }
            }
        }
        .task { await load() }
        .onDisappear { importTask?.cancel() }
        .animation(.snappy(duration: 0.25), value: selected)
        .animation(.snappy(duration: 0.25), value: addedSets.count)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Rebrickable sets")
                .font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-0.8)
                .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            if !loading, error == nil, !owned.isEmpty {
                Group {
                    if newSets.isEmpty { Text("All \(owned.count) sets are already here. Nice!") }
                    else { Text("Pick the sets you want to build again. We’ll gather their bricks for you.") }
                }.font(.subheadline).foregroundStyle(Palette.muted)
            }
        }
    }

    @ViewBuilder private var newSection: some View {
        let visible = newSets.filter(matches)
        if !newSets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Not added yet · \(newSets.count)")
                    Spacer()
                    let allSelected = !visible.isEmpty && visible.allSatisfy { selected.contains($0.id) }
                    Button(allSelected ? LocalizedStringKey("Clear") : LocalizedStringKey("Select all")) {
                        if allSelected { selected.subtract(visible.map(\.id)) } else { selected.formUnion(visible.map(\.id)) }
                    }
                    .font(.subheadline.weight(.semibold)).disabled(isImporting || visible.isEmpty)
                    .accessibilityIdentifier("selectAllSets")
                }
                if visible.isEmpty {
                    Text("No sets match “\(query)”.").font(.subheadline).foregroundStyle(Palette.muted)
                }
                AdaptiveCardGrid {
                    ForEach(visible) { entry in selectableRow(entry) }
                }
            }
        }
    }

    @ViewBuilder private var addedSection: some View {
        let visible = addedSets.filter(matches)
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Already in Brick by Brick · \(addedSets.count)")
                AdaptiveCardGrid {
                    ForEach(visible) { entry in
                        SetRow(set: entry.set, saved: true, showsChevron: false).opacity(0.75)
                    }
                }
            }
        }
    }

    private func selectableRow(_ entry: OwnedSet) -> some View {
        let isSelected = selected.contains(entry.id)
        let isCurrent = current?.id == entry.id
        return Button {
            if isSelected { selected.remove(entry.id) } else { selected.insert(entry.id) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    SetRow(set: entry.set, showsChevron: false)
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(isSelected ? Palette.orange : .clear, lineWidth: 2.5))
                    Group {
                        if isCurrent { ProgressView() }
                        else {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(isSelected ? Palette.orange : Palette.line)
                        }
                    }.frame(width: 32)
                }
                if entry.quantity > 1 {
                    Text("You own \(entry.quantity) copies; one checklist is kept per set.")
                        .font(.caption).foregroundStyle(Palette.muted).padding(.leading, 4)
                }
                if let failure = failures[entry.id] {
                    Label { Text(verbatim: failure) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.caption).foregroundStyle(Palette.orange).padding(.leading, 4)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text("Double-tap to select or deselect"))
    }

    // MARK: Action bar

    private var actionBar: some View {
        VStack(spacing: 10) {
            if let current {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gathering \(current.name)…").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer()
                        Text("\(total - queue.count) of \(total)").font(.subheadline.monospacedDigit())
                            .foregroundStyle(Palette.muted)
                    }
                    ProgressView(value: Double(total - queue.count - 1), total: Double(max(total, 1))).tint(Palette.orange)
                }
                Button("Stop after this set") { queue.removeAll() }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Button { startImport() } label: {
                    Label(selected.isEmpty ? LocalizedStringKey("Pick sets to add")
                                           : LocalizedStringKey("Add \(selected.count) sets"),
                          systemImage: "plus")
                }
                .buttonStyle(PrimaryButton())
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.5 : 1)
                .accessibilityIdentifier("addSelectedSets")
            }
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
        .frame(maxWidth: 820).frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Loading and importing

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { owned = try await store.client.ownedSets(userToken: store.userToken) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func startImport() {
        guard !isImporting else { return }
        let sets = newSets.map(\.set).filter { selected.contains($0.id) }
        guard !sets.isEmpty else { return }
        queue = sets
        total = sets.count
        importTask = Task { await runQueue() }
    }

    /// Downloads one set at a time and paces requests, since Rebrickable rate-limits API keys.
    @MainActor private func runQueue() async {
        defer { current = nil; queue = []; total = 0 }
        while !queue.isEmpty, !Task.isCancelled {
            let set = queue.removeFirst()
            current = set
            failures[set.id] = nil
            var attempt = 0
            while true {
                do {
                    let parts = try await store.client.inventory(for: set)
                    if store.add(set, parts: parts) { selected.remove(set.id) }
                    break
                } catch CatalogError.rateLimited where attempt < 2 {
                    attempt += 1
                    try? await Task.sleep(for: .seconds(5 * attempt))
                } catch {
                    if !Task.isCancelled { failures[set.id] = error.localizedDescription }
                    break
                }
            }
            if !queue.isEmpty { try? await Task.sleep(for: .seconds(1)) }
        }
    }
}
