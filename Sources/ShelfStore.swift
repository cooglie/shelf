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

    func add(urls: [URL], persist: Bool = true) {
        var existing = Set(items.map { $0.url })
        for url in urls where !existing.contains(url) {
            items.append(makeItem(for: url))
            existing.insert(url)
        }
        applySort()
        if persist { saveBookmarks() }
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
        if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if let d = attrs[.modificationDate] as? Date { mod = d }
        } else {
            size = 0
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let thumb = ThumbnailProvider.thumbnail(for: url, maxPixel: 160)
        addCounter += 1
        return Item(url: url, isDirectory: isDir.boolValue, sizeBytes: size,
                    modDate: mod, icon: icon, thumbnail: thumb, addedOrder: addCounter)
    }

    // MARK: - Entfernen

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveBookmarks()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        saveBookmarks()
    }

    /// Entfernt die übergebenen Items (Bulk).
    func remove(items toRemove: [Item]) {
        let ids = Set(toRemove.map { $0.id })
        items.removeAll { ids.contains($0.id) }
        saveBookmarks()
    }

    func clear() {
        items.removeAll()
        settings.clearBookmarks()
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
