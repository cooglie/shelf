//
//  ShelfStore.swift
//  Schelf
//
//  Hält die gesammelten Dateien (URLs). Liefert Thumbnails + Metadaten für die UI,
//  führt Kopieren/Verschieben aus und beobachtet das Dateisystem.
//
//  v2: Persistenz (Bookmarks), Sortierung, Refresh, Bulk-Aktionen für Auswahl,
//      Öffnen / Öffnen mit …, Gesamtgröße, Drag-out-Support.
//

import AppKit
import Combine
import Foundation

final class ShelfStore: ObservableObject {

    /// Physischer Storage-Ordner für abgelegte Dateien.
    /// (~/Library/Application Support/Schelf/Shelf)
    private let storageDir: URL = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Schelf/Shelf", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

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

    private let pasteboardReader = PasteboardReader()
    private var addCounter = 0
    private var bag = Set<AnyCancellable>()

    /// Merkt sich für eine Ingest-Aktion die Ziel-→Quelle-Zuordnung, um sie
    /// rückgängig zu machen (Datei zurück an den Ursprungsort verschieben).
    struct IngestUndo {
        let moves: [(stored: URL, original: URL)]   // stored = neuer Pfad im Storage
        var count: Int { moves.count }
    }

    let settings = AppSettings.shared

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
    /// (Original wird aus der Quelle entfernt). Fehler werden nicht mehr silent
    /// geschluckt, sondern in `lastError` gemeldet; die betreffende Datei wird
    /// dann gar nicht aufgenommen (keine halbfertigen Referenzen).
    func add(urls: [URL], persist: Bool = true) {
        var existing = Set(items.map { $0.url })
        var undoMoves: [(URL, URL)] = []   // (stored, original)
        var errors: [String] = []

        for url in urls {
            // Bereits im Storage → nur referenzieren, nichts verschieben.
            if url.path.hasPrefix(storageDir.path) {
                if !existing.contains(url) {
                    items.append(makeItem(for: url))
                    existing.insert(url)
                }
                continue
            }
            do {
                let stored = try ingest(url: url)
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
        let fm = FileManager.default
        var errors: [String] = []
        var undoneURLs: Set<URL> = []

        for move in undo.moves {
            do {
                // Ursprung ggf. uniquifizieren, falls inzwischen belegt.
                let original = fm.fileExists(atPath: move.original.path)
                    ? uniqueName(for: move.original, in: move.original.deletingLastPathComponent())
                    : move.original
                try fm.moveItem(at: move.stored, to: original)
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

    /// Verschiebt eine Datei/Ordner sicher in den Schelf-Storage.
    /// - Existiert die Quelle nicht → Fehler (kein silent nil).
    /// - Existiert das Ziel schon → automatischer eindeutiger Name (keine Überschreibung).
    /// - Wirft bei Zugriffs-/Volume-Fehlern, damit der Aufrufer entscheidet.
    private func ingest(url: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        // Bereits im Storage → unverändert übernehmen.
        if url.path.hasPrefix(storageDir.path) { return url }

        let dest = storageDir.appendingPathComponent(url.lastPathComponent)
        let finalDest = fm.fileExists(atPath: dest.path) ? uniqueName(for: url, in: storageDir) : dest
        try safeMove(from: url, to: finalDest)
        return finalDest
    }

    // MARK: - Sichere Dateioperationen

    /// Sicheres Verschieben: verweigert Überschreiben, prüft Quelle, wirft bei Fehler.
    private func safeMove(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw OperationError.destinationExists
        }
        try fm.moveItem(at: source, to: destination)
    }

    /// Sicheres Kopieren: verweigert Überschreiben, prüft Quelle, wirft bei Fehler.
    private func safeCopy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw OperationError.destinationExists
        }
        try fm.copyItem(at: source, to: destination)
    }

    /// Datei-Picker (für den +-Button).
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

    private func makeItem(for url: URL) -> Item {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let size: Int64
        var mod = Date()
        if exists {
            // Verzeichnisse: rekursive Summe über alle Inhalte (sonst 0).
            size = isDir.boolValue ? recursiveSize(of: url)
                                   : ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
            if let d = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date { mod = d }
        } else {
            size = 0
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let thumb = ThumbnailProvider.thumbnail(for: url, maxPixel: 160)
        addCounter += 1
        return Item(url: url, isDirectory: isDir.boolValue, sizeBytes: size,
                    modDate: mod, icon: icon, thumbnail: thumb, addedOrder: addCounter)
    }

    /// Rekursive Größe eines Verzeichnisses (Bytes über alle regulären Dateien).
    private func recursiveSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let v = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               v.isRegularFile == true, let s = v.fileSize {
                total += Int64(s)
            }
        }
        return total
    }

    // MARK: - Entfernen

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveBookmarks()
    }

    func remove(_ item: Item) {
        trash(url: item.url)
        items.removeAll { $0.id == item.id }
        saveBookmarks()
    }

    /// Entfernt die übergebenen Items (Bulk).
    func remove(items toRemove: [Item]) {
        let ids = Set(toRemove.map { $0.id })
        for it in toRemove { trash(url: it.url) }
        items.removeAll { ids.contains($0.id) }
        saveBookmarks()
    }

    func clear() {
        for it in items { trash(url: it.url) }
        items.removeAll()
        settings.clearBookmarks()
    }

    /// Datei aus dem Schelf-Storage in den Papierkorb verschieben.
    /// Externe (nur referenzierte) Dateien werden nicht gelöscht.
    private func trash(url: URL) {
        guard url.path.hasPrefix(storageDir.path) else { return }
        var resultURL: NSURL?
        try? FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
    }

    // MARK: - Refresh

    /// Metadaten & Thumbnails neu einlesen.
    func refresh() {
        let urls = items.map { $0.url }
        items = urls.map { makeItem(for: $0) }
        applySort()
        saveBookmarks()
    }

    // MARK: - Verschieben / Kopieren

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

    private func performBatch(targets: [Item], to dest: URL, copy: Bool) {
        let fm = FileManager.default
        var errors: [String] = []
        var doneURLs: Set<URL> = []

        for item in targets {
            let dst = dest.appendingPathComponent(item.url.lastPathComponent)
            do {
                let finalDest = fm.fileExists(atPath: dst.path)
                    ? uniqueName(for: item.url, in: dest)
                    : dst
                if copy {
                    try safeCopy(from: item.url, to: finalDest)
                } else {
                    try safeMove(from: item.url, to: finalDest)
                }
                doneURLs.insert(item.url)
            } catch {
                // Einzelne Datei fehlerhaft → nicht abbrechen, sondern sammeln.
                errors.append("\(item.displayName): \(error.localizedDescription)")
            }
        }

        if !copy {
            // Verschobene Dateien aus dem Schelf-Storage entfernen (falls sie dort lagen).
            for u in doneURLs { trash(url: u) }
            items.removeAll { doneURLs.contains($0.url) }
            saveBookmarks()
        }
        // Fehler einzeln behandeln: Nutzer erfährt, welche geklappt haben und welche nicht.
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func uniqueName(for src: URL, in dir: URL) -> URL {
        let name = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty
                ? dir.appendingPathComponent("\(name) \(i)")
                : dir.appendingPathComponent("\(name) \(i).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
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
