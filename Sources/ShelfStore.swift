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
            case .destinationExists: return "Eine Datei mit diesem Namen existiert im Ziel bereits."
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    @Published private(set) var items: [Item] = []
    @Published var lastError: String?
    @Published var searchText: String = ""

    private let pasteboardReader = PasteboardReader()
    private var addCounter = 0
    private var bag = Set<AnyCancellable>()

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
    /// (Original wird aus der Quelle entfernt). Bei Verzeichnissen/ungleichem Volume
    /// über FileManager move (cross-volume automatisch Copy+Delete).
    func add(urls: [URL], persist: Bool = true) {
        var existing = Set(items.map { $0.url })
        for url in urls {
            let stored = ingest(url: url)
            guard let stored = stored, !existing.contains(stored) else { continue }
            items.append(makeItem(for: stored))
            existing.insert(stored)
        }
        applySort()
        if persist { saveBookmarks() }
    }

    /// Verschiebt eine Datei/Ordner in den Schelf-Storage. Liefert die neue URL zurück.
    /// Befindet sich die Quelle bereits im Storage, wird sie unverändert übernommen.
    private func ingest(url: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        // Bereits im Storage? Nicht nochmal verschieben.
        if url.path.hasPrefix(storageDir.path) { return url }

        let dest = storageDir.appendingPathComponent(url.lastPathComponent)
        let finalDest = fm.fileExists(atPath: dest.path) ? uniqueName(for: url, in: storageDir) : dest
        do {
            try fm.moveItem(at: url, to: finalDest)
            return finalDest
        } catch {
            // Cross-Volume oder keine Rechte: kein Ingest möglich — Quelle bleibt unverändert,
            // wir referenzieren nur (Fallback, damit Drag-in nie still fehlschlägt).
            return url
        }
    }

    /// Datei-Picker (für den +-Button).
    func addViaPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Zur Ablage hinzufügen"
        panel.title = "Dateien auswählen"
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
        panel.prompt = copy ? "Hierher kopieren" : "Hierher verschieben"
        panel.title = copy ? "Ablage kopieren nach …" : "Ablage verschieben nach …"

        panel.begin { [weak self] resp in
            guard resp == .OK, let dest = panel.url else { return }
            self?.performBatch(targets: targets, to: dest, copy: copy)
        }
    }

    private func performBatch(targets: [Item], to dest: URL, copy: Bool) {
        let fm = FileManager.default
        var errors: [String] = []
        var doneURLs: Set<URL> = []

        for item in targets {
            let dst = dest.appendingPathComponent(item.url.lastPathComponent)
            do {
                if fm.fileExists(atPath: dst.path) {
                    let unique = uniqueName(for: item.url, in: dest)
                    if copy {
                        try fm.copyItem(at: item.url, to: unique)
                    } else {
                        try fm.moveItem(at: item.url, to: unique)
                    }
                } else {
                    if copy {
                        try fm.copyItem(at: item.url, to: dst)
                    } else {
                        try fm.moveItem(at: item.url, to: dst)
                    }
                }
                doneURLs.insert(item.url)
            } catch {
                errors.append("\(item.displayName): \(error.localizedDescription)")
            }
        }

        if !copy {
            // Verschobene Dateien aus dem Schelf-Storage entfernen (falls sie dort lagen).
            for u in doneURLs { trash(url: u) }
            items.removeAll { doneURLs.contains($0.url) }
            saveBookmarks()
        }
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
        panel.prompt = "Öffnen mit"
        panel.title = "App wählen, um \(item.displayName) zu öffnen"
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
