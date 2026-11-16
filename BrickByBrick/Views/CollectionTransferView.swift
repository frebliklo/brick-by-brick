import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let brickByBrickCollection = UTType(exportedAs: "com.brickbybrick.collection", conformingTo: .json)
}

struct CollectionDocument: FileDocument, Transferable {
    let data: Data
    static var readableContentTypes: [UTType] { [.brickByBrickCollection] }

    init(archive: CollectionArchive) throws { data = try archive.encoded() }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ArchiveError.invalid }
        _ = try CollectionArchive.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .brickByBrickCollection) { document in
            let manager = FileManager.default
            let root = manager.temporaryDirectory.appendingPathComponent("CollectionTransfers", isDirectory: true)
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            // Keep active shares available; discard only old app-created snapshots.
            let staleDate = Date.now.addingTimeInterval(-86_400)
            for directory in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
                if let created = try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate, created < staleDate {
                    try? manager.removeItem(at: directory)
                }
            }
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("BrickByBrick-collection.brickbybrick")
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
            .suggestedFileName("BrickByBrick-collection.brickbybrick")
    }
}

struct CollectionTransferSection: View {
    @Environment(AppStore.self) private var store
    @State private var showImporter = false
    @State private var incoming: CollectionArchive?
    @State private var outgoing: ExportSnapshot?
    @State private var reading = false
    @State private var error: String?

    private struct ExportSnapshot: Identifiable {
        let id = UUID()
        let document: CollectionDocument
    }

    var body: some View {
        Section {
            Button {
                do { outgoing = ExportSnapshot(document: try CollectionDocument(archive: CollectionArchive(builds: store.builds))) }
                catch { self.error = error.localizedDescription }
            } label: { Label("Export collection", systemImage: "square.and.arrow.up") }
                .disabled(store.builds.isEmpty)
                .accessibilityIdentifier("exportCollection")
            Button { showImporter = true } label: {
                Label("Import collection", systemImage: "square.and.arrow.down")
            }.disabled(reading).accessibilityIdentifier("importCollection")
            if reading { ProgressView("Reading collection…") }
        } header: { Text("Transfer your collection") } footer: {
            Text("Move saved sets and progress between your devices with AirDrop or a file. Your API key and settings aren’t included. Transfers are manual; devices don’t sync automatically.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.brickByBrickCollection]) { result in
            switch result {
            case .success(let url):
                reading = true
                Task {
                    do { incoming = try await Task.detached { try CollectionArchive.read(from: url) }.value }
                    catch { self.error = error.localizedDescription }
                    reading = false
                }
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .sheet(item: $outgoing) { snapshot in CollectionExportView(document: snapshot.document) }
        .sheet(item: $incoming) { archive in CollectionImportView(archive: archive) }
        .alert("Couldn’t transfer collection", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: error ?? "") }
    }
}

private struct CollectionExportView: View {
    let document: CollectionDocument
    @Environment(\.dismiss) private var dismiss
    @State private var showExporter = false
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShareLink(item: document, preview: SharePreview("Brick by Brick collection")) {
                        Label("Share collection…", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("shareCollection")
                    Button { showExporter = true } label: {
                        Label("Save collection to file…", systemImage: "folder")
                    }.accessibilityIdentifier("saveCollectionFile")
                    if saved { Label("Collection file saved", systemImage: "checkmark.circle") }
                } footer: {
                    Text("Choose AirDrop to send this snapshot to another device. On that device, open the file in Brick by Brick or choose Import collection in Settings.")
                }
                Section {
                    Text("The file contains your saved sets, inventories, and progress. It isn’t password-protected, so share it only with people you choose. Your API key isn’t included. Part images aren’t included and may need an internet connection.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
            }.desktopFormStyle()
                .navigationTitle("Export collection").inlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .macSheetSize(width: 540, height: 420)
        .fileExporter(isPresented: $showExporter, document: document, contentType: .brickByBrickCollection,
                      defaultFilename: "BrickByBrick-collection") { result in
            switch result {
            case .success: saved = true
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .alert("Couldn’t transfer collection", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: error ?? "") }
    }
}

struct CollectionImportView: View {
    let archive: CollectionArchive
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var existingSets: CollectionArchive.ExistingSets = .keep
    @State private var error: String?

    private var existingIDs: Set<String> { Set(store.builds.map(\.id)) }
    private var overlappingCount: Int { archive.builds.filter { existingIDs.contains($0.id) }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Sets in file", value: archive.builds.count.formatted())
                    LabeledContent("Already on this device", value: overlappingCount.formatted())
                    LabeledContent("Exported") { Text(archive.exportedAt, format: .dateTime.day().month().year().hour().minute()) }
                }
                if overlappingCount > 0 {
                    Section {
                        Picker("For sets already saved", selection: $existingSets) {
                            Text("Keep this device’s progress").tag(CollectionArchive.ExistingSets.keep)
                            Text("Use the file’s progress").tag(CollectionArchive.ExistingSets.replace)
                        }.accessibilityIdentifier("importConflictPolicy")
                        Text(existingSets == .keep
                             ? LocalizedStringKey("Existing sets stay unchanged. Only new sets are added.")
                             : LocalizedStringKey("Matching sets and their progress will be replaced by the file’s copy, even if it has less progress. Other sets stay unchanged."))
                            .font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
                Section("Sets to import") {
                    ForEach(archive.builds) { build in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: build.set.name).font(.headline)
                            Text("\(build.foundCount) of \(build.totalCount) found").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
                if archive.builds.isEmpty { Text("This collection file contains no sets.") }
            }.desktopFormStyle()
                .navigationTitle("Import collection").inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            if store.importCollection(archive, existingSets: existingSets) { dismiss() }
                            else { error = store.storageError; store.storageError = nil }
                        }.disabled(archive.builds.isEmpty).accessibilityIdentifier("confirmCollectionImport")
                    }
                }
        }.macSheetSize(width: 580, height: 560)
            .alert("Couldn’t save your collection", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(verbatim: error ?? "") }
    }
}
