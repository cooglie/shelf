//
//  ShelfStore.swift
//  Schelf
//
//  Hält die gesammelten Dateien (URLs). Liefert Thumbnails + Metadaten für die UI,
//  führt Kopieren/Verschieben aus und beobachtet das Dateisystem.
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
        var icon: NSImage?
        var thumbnail: NSImage? // nur für Bilder
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

    private let pasteboardReader = PasteboardReader()

    // MARK: - Hinzufügen (Drop / Pasteboard)

    func addFromPasteboard(_ pb: NSPasteboard) {
        guard let urls = pasteboardReader.fileURLs(from: pb) else { return }
        add(urls: urls)
    }

    func add(urls: [URL]) {
        var existing = Set(items.map { $0.url })
        for url in urls where !existing.contains(url) {
            items.append(makeItem(for: url))
            existing.insert(url)
        }
    }

    private func makeItem(for url: URL) -> Item {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let size: Int64
        if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let s = attrs[.size] as? NSNumber {
            size = s.int64Value
        } else {
            size = 0
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let thumb = ThumbnailProvider.thumbnail(for: url, maxPixel: 160)
        return Item(url: url, isDirectory: isDir.boolValue, sizeBytes: size, icon: icon, thumbnail: thumb)
    }

    // MARK: - Entfernen

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    // MARK: - Verschieben / Kopieren (gesammelt)

    /// Öffnet einen Ordner-Wähler und verschiebt/kopiert alle Ablage-Dateien dorthin.
    func moveAll() { runBatch(copy: false) }
    func copyAll() { runBatch(copy: true) }

    private func runBatch(copy: Bool) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = copy ? "Hierher kopieren" : "Hierher verschieben"
        panel.title = copy ? "Ablage kopieren nach …" : "Ablage verschieben nach …"

        panel.begin { [weak self] resp in
            guard resp == .OK, let dest = panel.url else { return }
            self?.performBatch(to: dest, copy: copy)
        }
    }

    private func performBatch(to dest: URL, copy: Bool) {
        let fm = FileManager.default
        var errors: [String] = []
        var doneURLs: Set<URL> = []

        for item in items {
            let dst = dest.appendingPathComponent(item.url.lastPathComponent)
            do {
                if fm.fileExists(atPath: dst.path) {
                    // Eindeutigen Namen erzeugen.
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

        // Verschobene Dateien aus der Ablage nehmen; kopierte bleiben.
        if !copy {
            items.removeAll { doneURLs.contains($0.url) }
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
}
