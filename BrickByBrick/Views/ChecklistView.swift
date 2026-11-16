import SwiftUI

struct ChecklistView: View {
    let buildID: String
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var filter = PartFilter.all
    @State private var colorID: Int?
    @State private var showSpares = false
    @State private var showFilters = false
    @State private var confirmReset = false
    @State private var editingPart: InventoryPart?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum PartFilter: String, CaseIterable {
        case all = "All bricks", missing = "Still missing", found = "Found"
        var title: LocalizedStringKey { LocalizedStringKey(rawValue) }
        var systemImage: String {
            switch self {
            case .all: "square.grid.2x2.fill"
            case .missing: "circle.dashed"
            case .found: "checkmark.circle.fill"
            }
        }
    }

    private var panelAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var hasFilters: Bool { !query.isEmpty || filter != .all || colorID != nil }

    var body: some View {
        Group {
            if let build = store.build(buildID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        boardHeader(build)
                        if showFilters {
                            filterControls(build)
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .offset(y: -10)),
                                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
                        }
                        let visible = filtered(build)
                        if visible.isEmpty {
                            ContentUnavailableView(filter == .missing && build.isComplete ? LocalizedStringKey("Every brick accounted for!") : LocalizedStringKey("No bricks here"),
                                                   systemImage: filter == .missing && build.isComplete ? "checkmark.seal" : "square.stack.3d.up",
                                                   description: Text("Try another filter or clear your search."))
                        }
                        AdaptiveCardGrid(minimumCardWidth: 300, maximumColumns: 6) {
                            ForEach(visible) { part in
                                BrickBoardCard(part: part, count: build.count(for: part),
                                               update: { store.update(buildID, part: part, count: $0) },
                                               edit: { editingPart = part })
                            }
                        }
                        if build.parts.contains(where: \.isSpare) {
                            Toggle("Include spare pieces", isOn: $showSpares).font(.subheadline)
                            Text("Spares are optional and don’t affect build progress.").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }.padding(22).pageWidth(1680)
                }.background(Palette.background)
                    .navigationTitle(build.set.name).compactNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button("Reset checklist", systemImage: "arrow.counterclockwise", role: .destructive) { confirmReset = true }
                            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Checklist options")
                        }
                    }
                    .confirmationDialog("Reset all found quantities for this set?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("Reset checklist", role: .destructive) { store.reset(buildID) }
                    }
                    .sheet(item: $editingPart) { part in
                        QuantitySheet(part: part, current: build.count(for: part)) { count in
                            store.update(buildID, part: part, count: count)
                        }.presentationDetents([.medium, .large])
                    }
            } else {
                ContentUnavailableView("Set not in your collection", systemImage: "square.stack.3d.up")
            }
        }
    }

    private func boardHeader(_ build: SavedBuild) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(build.set.name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Palette.muted)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    boardTitle(build)
                    Spacer(minLength: 16)
                    filterButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    boardTitle(build)
                    filterButton
                }
            }
            ProgressView(value: build.progress).tint(Palette.green).accessibilityHidden(true)
            Text("\(build.foundCount) of \(build.totalCount) pieces found")
                .font(.subheadline).foregroundStyle(Palette.muted).monospacedDigit()
                .accessibilityIdentifier("buildProgress")
        }
    }

    private func boardTitle(_ build: SavedBuild) -> some View {
        Text(build.isComplete ? LocalizedStringKey("You found them all!") : LocalizedStringKey("Find these bricks"))
            .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var filterButton: some View {
        Button { withAnimation(panelAnimation) { showFilters.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .overlay(alignment: .topTrailing) {
                        if hasFilters {
                            Circle().fill(Palette.orange).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Palette.orangeTint, lineWidth: 2)).offset(x: 4, y: -3)
                        }
                    }
                Text(hasFilters ? LocalizedStringKey("Filters on") : LocalizedStringKey("Search & filters"))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    .rotationEffect(.degrees(showFilters ? -180 : 0))
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.orange)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(Palette.orangeTint, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("boardFilters")
        .accessibilityValue(showFilters ? LocalizedStringKey("Expanded") : LocalizedStringKey("Collapsed"))
    }

    private func filterControls(_ build: SavedBuild) -> some View {
        let palette = colors(build)
        let selectedName = colorID.flatMap { id in palette.first { $0.id == id }?.name }
        return VStack(alignment: .leading, spacing: 20) {
            SoftSearchField(prompt: "Find a part or color", text: $query,
                            identifier: "partSearch", clearLabel: "Clear part search", recessed: true)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    panelHeading("Show bricks")
                    Spacer(minLength: 12)
                    // Always laid out, so showing it never pushes the bricks down.
                    Button { query = ""; filter = .all; colorID = nil } label: {
                        Label("Clear filters", systemImage: "xmark.circle")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.orange).frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hasFilters ? 1 : 0).disabled(!hasFilters)
                    .accessibilityHidden(!hasFilters)
                    .animation(.easeOut(duration: 0.15), value: hasFilters)
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(PartFilter.allCases, id: \.self) { option in
                        ChoiceChip(title: option.title, systemImage: option.systemImage, selected: filter == option) {
                            filter = option
                        }
                    }
                }
            }
            if palette.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        panelHeading("Colors")
                        Group {
                            if let selectedName { Text(verbatim: selectedName) } else { Text("All colors") }
                        }
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(Palette.muted)
                        .contentTransition(.opacity)
                    }
                    ColorSwatchPicker(colors: palette, selection: $colorID)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func panelHeading(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(.headline, design: .rounded)).foregroundStyle(Palette.ink)
    }

    private func colors(_ build: SavedBuild) -> [BrickColor] {
        Array(Set(build.parts.map(\.color))).sorted { $0.name < $1.name }
    }

    private func filtered(_ build: SavedBuild) -> [InventoryPart] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return build.parts.filter { part in
            (showSpares || !part.isSpare) && (colorID == nil || part.color.id == colorID) &&
            (filter == .all || (filter == .found ? build.count(for: part) == part.quantity : build.count(for: part) < part.quantity)) &&
            (text.isEmpty || "\(part.part.name) \(part.part.partNum) \(part.color.name) \(part.elementId ?? "")".localizedCaseInsensitiveContains(text))
        }
    }
}

struct BrickBoardCard: View {
    let part: InventoryPart
    let count: Int
    let update: (Int) -> Void
    let edit: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 72
    private var complete: Bool { count == part.quantity }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    partImage.frame(minWidth: 140)
                    remaining.fixedSize(horizontal: true, vertical: false)
                }
                VStack(spacing: 12) {
                    partImage
                    remaining
                }
            }
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(part.part.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: part.color.rgb)).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1)).accessibilityHidden(true)
                        Text(part.color.name).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    if part.isSpare { Text("Spare").font(.caption).foregroundStyle(Palette.muted) }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Set quantity…", systemImage: "number", action: edit)
                    Button(complete ? LocalizedStringKey("Clear found pieces") : LocalizedStringKey("Mark all found"), systemImage: complete ? "arrow.counterclockwise" : "checkmark") {
                        update(complete ? 0 : part.quantity)
                    }.accessibilityIdentifier("check-\(part.id)")
                    Text("Part #\(part.part.partNum)")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.muted).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Options for \(part.color.name) \(part.part.name)")
                .accessibilityIdentifier("part-options-\(part.id)")
            }
            HStack(spacing: 12) {
                Button { update(count - 1) } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 22, weight: .medium))
                        .frame(width: 56, height: 60)
                        .background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))
                }
                .foregroundStyle(Palette.muted).disabled(count == 0)
                .accessibilityLabel("Undo one \(part.color.name) \(part.part.name)")
                .accessibilityIdentifier("undo-\(part.id)")
                if complete {
                    Label("\(part.quantity) found", systemImage: "checkmark")
                        .font(.system(.headline, design: .rounded)).foregroundStyle(Palette.green)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    Button { update(count + 1) } label: {
                        Label("Found 1", systemImage: "plus")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .foregroundStyle(.white)
                            .background(Palette.green, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Found one \(part.color.name) \(part.part.name)")
                    .accessibilityIdentifier("plus-\(part.id)")
                }
            }.buttonStyle(.plain)
        }
        .padding(20)
        .background(complete ? Palette.greenTint : Palette.surface, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brick-card-\(part.id)")
    }

    private var partImage: some View {
        PartImage(part: part).frame(maxWidth: .infinity).frame(height: 150)
    }

    private var remaining: some View {
        VStack(spacing: 2) {
            if complete {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 58))
                    .foregroundStyle(Palette.green)
                Text("All found").font(.system(.headline, design: .rounded)).foregroundStyle(Palette.green)
            } else {
                Text("\(part.quantity - count)")
                    .font(.system(size: min(countSize, typeSize.isAccessibilitySize ? 110 : 90), weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(Palette.ink)
                Text("to find").font(.system(.headline, design: .rounded)).foregroundStyle(Palette.ink)
            }
        }.frame(minWidth: 88, minHeight: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) of \(part.quantity) found. \(part.color.name) \(part.part.name)")
            .accessibilityValue(complete ? LocalizedStringKey("All found") : LocalizedStringKey("\(part.quantity - count) to find"))
            .accessibilityIdentifier("quantity-\(part.id)")
    }
}

struct QuantitySheet: View {
    let part: InventoryPart
    let save: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    init(part: InventoryPart, current: Int, save: @escaping (Int) -> Void) {
        self.part = part; self.save = save; _value = State(initialValue: String(current))
    }
    private var valid: Bool { Int(value).map { (0...part.quantity).contains($0) } ?? false }
    private func commit() {
        guard let number = Int(value), valid else { return }
        save(number); dismiss()
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(part.part.name).font(.headline)
                    Text(part.color.name).foregroundStyle(.secondary)
                    TextField("Found", text: $value).quantityKeyboard().accessibilityIdentifier("quantityInput")
                        .onSubmit(commit)
                } footer: { Text("Enter a quantity from 0 to \(part.quantity).") }
            }.desktopFormStyle().navigationTitle("Pieces found").inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: commit).disabled(!valid)
                    }
                }
        }.macSheetSize(width: 440, height: 300)
    }
}
