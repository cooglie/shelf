//
//  ShelfStore.swift
//  Schelf
//
//  Hält die gesammelten Dateien (Zustand: Items, Sortierung, Suche, Auswahl).
//  Dateisystemzugriffe werden an FileCoordinator delegiert (v2.2: Trennung
//  Zustand vs. Dateisystem). Batch-Operationen laufen asynchron und liefern
//  eine BatchResult-Zusammenfassung für die UI.
//
//  v2: Persistenz (Bookmarks), Sortierung, Refresh, Bulk-Aktionen für Auswahl,
//      Öffnen / Öffnen mit …, Gesamtgröße, Drag-out-Support.
//

import AppKit
import Combine
import Foundation

final class ShelfStore: ObservableObject {

    /// Eine Ablage-Datei mit zwischengespeicherten Metadaten.
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var displayName: String { url.lastPathComponent }
        var isDirectory: Bool
        var sizeBytes: Int64
        var modDate: Date
        var icon: NSImage?
        var thumbnail: NSImage? // nur für Bilder
        var addedOrder: Int
    }

    enum OperationError: LocalizedError {
        case destinationExists
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .destinationExists: return L10n.string(.errorDestExists)
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    @Published private(set) var items: [Item] = []
    @Published var lastError: String?
    @Published var searchText: String = ""
    /// Zuletzt verschobene (Ingest-) Aktion; nil sobald Undo nicht mehr möglich.
    @Published private(set) var lastUndoableIngest: IngestUndo?
    /// Zusammenfassung des letzten Batch-Laufs (für Post-Completion-UI). nil = keiner/verworben.
    @Published private(set) var lastBatchResult: BatchResult?

    /// Verwirft die letzte Batch-Zusammenfassung (UI „OK" im Summary-Alert).
    func dismissBatchResult() { lastBatchResult = nil }
    /// Läuft gerade ein Batch? (für UI-Spinner / Button-Disable).
    @Published private(set) var isBatchRunning: Bool = false

    private let pasteboardReader = PasteboardReader()
    private let fileCoordinator = FileCoordinator()
    private var addCounter = 0
    private var bag = Set<AnyCancellable>()

    /// Merkt sich für eine Ingest-Aktion die Ziel-→Quelle-Zuordnung, um sie
    /// rückgängig zu machen (Datei zurück an den Ursprungsort verschieben).
    struct IngestUndo {
        let moves: [(stored: URL, original: URL)]   // stored = neuer Pfad im Storage
        var count: Int { moves.count }
    }

    let settings = AppSettings.shared

    /// Storage-Ordner (exposed für UI/Persistenz-Prüfungen).
    var storageDir: URL { fileCoordinator.storageDir }

    init() {
        // Sortierung live anwenden.
        settings.sortChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySort() }
            .store(in: &bag)

        // Persistenz beim Start wiederherstellen.
        if settings.persistShelf {
            let urls = settings.loadBookmarks()
            if !urls.isEmpty { add(urls: urls, persist: false) }
        }
    }

    // MARK: - Sortierung

    func sortedItems() -> [Item] {
        let filtered = searchText.isEmpty
            ? items
            : items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        return filtered
    }

    private func applySort() {
        items.sort(by: ShelfStore.compare(settings.sort))
        objectWillChange.send()
    }

    private static func compare(_ s: ShelfSort) -> (Item, Item) -> Bool {
        switch s {
        case .addedDesc: return { $0.addedOrder > $1.addedOrder }
        case .addedAsc:  return { $0.addedOrder < $1.addedOrder }
        case .nameAsc:   return { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameDesc:  return { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .sizeDesc:  return { $0.sizeBytes > $1.sizeBytes }
        case .sizeAsc:   return { $0.sizeBytes < $1.sizeBytes }
        case .dateDesc:  return { $0.modDate > $1.modDate }
        case .dateAsc:   return { $0.modDate < $1.modDate }
        }
    }

    // MARK: - Gesamtgröße

    var totalCount: Int { items.count }
    var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    // MARK: - Hinzufügen (Drop / Pasteboard / Picker)

    func addFromPasteboard(_ pb: NSPasteboard) {
        guard let urls = pasteboardReader.fileURLs(from: pb) else { return }
        add(urls: urls)
    }

    /// Dateien in die Ablage aufnehmen — physisch in den Schelf-Storage verschieben
    /// (Original wird aus der Quelle entfernt). Fehler werden pro Datei gemeldet;
    /// die betreffende Datei wird dann gar nicht aufgenommen (keine halbfertigen Referenzen).
    func add(urls: [URL], persist: Bool = true) {
        var existing = Set(items.map { $0.url })
        var undoMoves: [(URL, URL)] = []   // (stored, original)
        var errors: [String] = []

        for url in urls {
            // Bereits im Storage → nur referenzieren, nichts verschieben.
            if fileCoordinator.isInsideStorage(url) {
                if !existing.contains(url) {
                    items.append(makeItem(for: url))
                    existing.insert(url)
                }
                continue
            }
            do {
                let stored = try fileCoordinator.ingest(url: url)
                guard !existing.contains(stored) else { continue }
                items.append(makeItem(for: stored))
                existing.insert(stored)
                undoMoves.append((stored, url))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !undoMoves.isEmpty {
            lastUndoableIngest = IngestUndo(moves: undoMoves.map {
                (stored: $0.0, original: $0.1)
            })
        }
        applySort()
        if persist { saveBookmarks() }
        if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
    }

    /// Macht die letzte Ingest-Aktion rückgängig: verschiebt die Dateien aus dem
    /// Schelf-Storage zurück an ihren Ursprungsort und entfernt sie aus der Ablage.
    func undoLastAdd() {
        guard let undo = lastUndoableIngest, !undo.moves.isEmpty else { return }
        var errors: [String] = []
        var undoneURLs: Set<URL> = []

        for move in undo.moves {
            do {
                // Ursprung ggf. uniquifizieren, falls inzwischen belegt.
                let original = FileManager.default.fileExists(atPath: move.original.path)
                    ? fileCoordinator.uniqueName(for: move.original, in: move.original.deletingLastPathComponent())
                    : move.original
                try fileCoordinator.safeMove(from: move.stored, to: original)
                undoneURLs.insert(move.stored)
            } catch {
                errors.append("\(move.stored.lastPathComponent): \(error.localizedDescription)")
            }
        }

        items.removeAll { undoneURLs.contains($0.url) }
        lastUndoableIngest = nil
        saveBookmarks()
        if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
    }

    // MARK: - Datei-Picker (für den +-Button).

    func addViaPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.string(.pickerAddPrompt)
        panel.title = L10n.string(.pickerAddTitle)
        panel.begin { [weak self] resp in
            guard resp == .OK else { return }
            self?.add(urls: panel.urls)
        }
    }

    // MARK: - Item-Erzeugung (Metadaten + Thumbnail)

    /// Baut ein Item synchron (Placeholder; Thumbnail/Size werden asynchron nachgeladen
    /// via refreshItemMetadata). Wird auch beim initialen Laden verwendet.
    private func makeItem(for url: URL) -> Item {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let icon = exists ? NSWorkspace.shared.icon(forFile: url.path) : nil
        addCounter += 1
        return Item(url: url, isDirectory: isDir.boolValue, sizeBytes: 0,
                    modDate: Date(), icon: icon, thumbnail: nil, addedOrder: addCounter)
    }

    /// Liest Größe + Modifikationsdatum (off-main) und aktualisiert das Item.
    func refreshItemMetadata(_ item: Item) {
        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var size: Int64 = 0
            var mod = Date()
            var isDir = false
            var isDirB: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirB) {
                isDir = isDirB.boolValue
                if isDir {
                    size = self?.fileCoordinator.recursiveSize(of: url) ?? 0
                } else {
                    size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
                }
                if let d = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date { mod = d }
            }
            let thumb = ThumbnailProvider.thumbnail(for: url, maxPixel: 160)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[idx].sizeBytes = size
                    self.items[idx].modDate = mod
                    self.items[idx].isDirectory = isDir
                    self.items[idx].thumbnail = thumb
                    self.objectWillChange.send()
                }
            }
        }
    }

    // MARK: - Entfernen

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveBookmarks()
    }

    func remove(_ item: Item) {
        fileCoordinator.trash(url: item.url)
        items.removeAll { $0.id == item.id }
        saveBookmarks()
    }

    /// Entfernt die übergebenen Items (Bulk).
    func remove(items toRemove: [Item]) {
        let ids = Set(toRemove.map { $0.id })
        for it in toRemove { fileCoordinator.trash(url: it.url) }
        items.removeAll { ids.contains($0.id) }
        saveBookmarks()
    }

    func clear() {
        for it in items { fileCoordinator.trash(url: it.url) }
        items.removeAll()
        settings.clearBookmarks()
    }

    // MARK: - Refresh

    /// Metadaten & Thumbnails neu einlesen (asynchron, off-main).
    func refresh() {
        let urls = items.map { $0.url }
        // Placeholder neu aufbauen, dann Metadaten asynchron nachladen.
        items = urls.map { makeItem(for: $0) }
        applySort()
        saveBookmarks()
        for item in items {
            refreshItemMetadata(item)
        }
    }

    // MARK: - Verschieben / Kopieren (asynchron, mit Zusammenfassung)

    /// Alle oder nur die Auswahl (wenn nicht leer) kopieren/verschieben.
    func moveAll(selected: [Item]? = nil) { runBatch(copy: false, selected: selected) }
    func copyAll(selected: [Item]? = nil) { runBatch(copy: true, selected: selected) }

    private func runBatch(copy: Bool, selected: [Item]?) {
        let targets = selected?.isEmpty == false ? selected! : items
        guard !targets.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = copy ? L10n.string(.copyPrompt) : L10n.string(.movePrompt)
        panel.title = copy ? L10n.string(.copyTitle) : L10n.string(.moveTitle)

        panel.begin { [weak self] resp in
            guard resp == .OK, let dest = panel.url else { return }
            guard let self = self else { return }
            // Vorab-Bestätigung: Quelle, Ziel, Anzahl + Modus anzeigen.
            let verb = copy ? L10n.string(.copy) : L10n.string(.move)
            let msg = String(format: L10n.string(.batchConfirmMsg),
                             targets.count, dest.path, verb)
            let alert = NSAlert()
            alert.messageText = copy ? L10n.string(.confirmCopy) : L10n.string(.confirmMove)
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: verb)
            alert.addButton(withTitle: L10n.string(.cancel))
            if alert.runModal() == .alertFirstButtonReturn {
                self.performBatch(targets: targets, to: dest, copy: copy)
            }
        }
    }

    /// Batch asynchron ausführen (UI nicht blockieren), dann Zusammenfassung setzen.
    private func performBatch(targets: [Item], to dest: URL, copy: Bool) {
        isBatchRunning = true
        let sources = targets.map { $0.url }
        let coordinator = fileCoordinator
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = coordinator.performBatch(sources: sources, to: dest, copy: copy)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBatchRunning = false
                self.lastBatchResult = result

                if !copy {
                    // Erfolgreich verschobene Dateien aus dem Storage entfernen.
                    let movedURLs = Set(result.succeeded.map { $0.source })
                    for u in movedURLs { self.fileCoordinator.trash(url: u) }
                    self.items.removeAll { movedURLs.contains($0.url) }
                    self.saveBookmarks()
                }
                // Fehler zusätzlich ins lastError (für das bestehende Fehler-Alert).
                if result.failureCount > 0 {
                    self.lastError = result.failed.map {
                        "\($0.source.lastPathComponent): \($0.error?.errorDescription ?? "")"
                    }.joined(separator: "\n")
                }
            }
        }
    }

    // MARK: - Öffnen

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func openWith(_ item: Item) {
        // Datei im Finder selektieren + „Öffnen mit“-Panel via Services.
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        // Generisches App-Wahl-Panel.
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.prompt = L10n.string(.openWithPrompt)
        panel.title = L10n.string(.openWithTitle, item.displayName)
        panel.begin { resp in
            guard resp == .OK, let chosenApp = panel.url else { return }
            NSWorkspace.shared.open([item.url], withApplicationAt: chosenApp,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Persistenz

    private func saveBookmarks() {
        settings.saveBookmarks(items.map { $0.url })
    }
}
