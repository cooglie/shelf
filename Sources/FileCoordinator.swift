//
//  FileCoordinator.swift
//  Schelf
//
//  Isoliert ALLE Dateisystemoperationen. Wirft bei Fehlern, hat kein UI-Wissen,
//  keine Zustandsverwaltung. ShelfStore delegiert hierher.
//
//  v2.2: Extrahiert aus ShelfStore, um das God-Object aufzulösen
//  (Zustand vs. Dateisystem vs. UI sauber trennen).
//

import Foundation

/// Fehler bei Dateioperationen — explizit, damit UI/Aufrufer differenzieren kann.
enum FileOpError: LocalizedError, Equatable {
    /// Quelldatei existiert nicht (mehr).
    case sourceMissing
    /// Ziel existiert bereits — Überschreiben wird verweigert.
    case destinationExists
    /// Berechtigung verweigert (readonly / Sandbox / ACL).
    case permissionDenied
    /// Ziellaufwerk voll.
    case diskFull
    /// Zugrundeliegender Cocoa/Foundation-Fehler.
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing:      return "File no longer exists."
        case .destinationExists:  return "A file with this name already exists at the destination."
        case .permissionDenied:   return "Permission denied."
        case .diskFull:           return "The destination volume is full."
        case .underlying(let s):  return s
        }
    }

    /// Klassifiziert einen rohen Foundation/Cocoa-Fehler.
    static func from(_ error: Error) -> FileOpError {
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileNoSuchFile:       return .sourceMissing
            case .fileWriteOutOfSpace:  return .diskFull
            case .fileWriteNoPermission,
                 .fileReadNoPermission:  return .permissionDenied
            default: break
            }
        }
        // POSIX-Layer (z. B. ENOSPC, EACCES bei manchen Volumes).
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            switch ns.code {
            case Int(ENOSPC):  return .diskFull
            case Int(EACCES),
                 Int(EPERM):   return .permissionDenied
            case Int(ENOENT):  return .sourceMissing
            default: break
            }
        }
        return .underlying(error.localizedDescription)
    }
}

/// Ergebnis einer einzelnen Datei-Operation innerhalb eines Batches.
struct FileOpOutcome: Equatable {
    enum Result: Equatable { case success, failure }
    let source: URL
    let destination: URL        // tatsächliches Ziel (ggf. uniquifiziert)
    let result: Result
    let error: FileOpError?     // nil bei Erfolg

    var succeeded: Bool { result == .success }
}

/// Zusammenfassung eines gesamten Batch-Laufs (Kopieren/Verschieben).
struct BatchResult: Equatable {
    let operation: BatchOperation
    let destination: URL
    let outcomes: [FileOpOutcome]

    var succeeded: [FileOpOutcome] { outcomes.filter { $0.succeeded } }
    var failed: [FileOpOutcome]    { outcomes.filter { !$0.succeeded } }
    var successCount: Int { succeeded.count }
    var failureCount: Int { failed.count }
    var totalCount: Int   { outcomes.count }

    /// Menschliche Zusammenfassung für die Post-Completion-UI.
    func summary() -> String {
        let verb = operation == .copy ? "copied" : "moved"
        var lines: [String] = []
        if failureCount == 0 {
            lines.append("\(successCount) \(pluralize(successCount, "file", "files")) \(verb).")
        } else {
            lines.append("\(successCount) \(verb), \(failureCount) failed:")
            for f in failed {
                lines.append("  • \(f.source.lastPathComponent): \(f.error?.errorDescription ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func pluralize(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? one : many
    }
}

enum BatchOperation { case copy, move }

/// Reine Dateisystem-Schicht. Kein Zustand, keine UI, wirft bei Fehlern.
/// Testbar ohne Fenster/Pasteboard.
final class FileCoordinator {

    let storageDir: URL

    init(storageDir: URL? = nil) {
        if let dir = storageDir {
            self.storageDir = dir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return
        }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Schelf/Shelf", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageDir = dir
    }

    // MARK: - Sichere Einzeloperationen

    /// Sicheres Verschieben: verweigert Überschreiben, prüft Quelle, wirft bei Fehler.
    func safeMove(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw FileOpError.sourceMissing
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw FileOpError.destinationExists
        }
        do {
            try fm.moveItem(at: source, to: destination)
        } catch {
            throw FileOpError.from(error)
        }
    }

    /// Sicheres Kopieren: verweigert Überschreiben, prüft Quelle, wirft bei Fehler.
    /// Symlinks werden als Links kopiert (nicht dereferenziert).
    func safeCopy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw FileOpError.sourceMissing
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw FileOpError.destinationExists
        }
        do {
            try fm.copyItem(at: source, to: destination)
        } catch {
            throw FileOpError.from(error)
        }
    }

    /// Verschiebt eine Datei/Ordner sicher in den Schelf-Storage.
    /// - Existiert die Quelle nicht → Fehler.
    /// - Existiert das Ziel schon → automatischer eindeutiger Name.
    func ingest(url: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw FileOpError.sourceMissing
        }
        if isInsideStorage(url) { return url }

        let dest = storageDir.appendingPathComponent(url.lastPathComponent)
        let finalDest = fm.fileExists(atPath: dest.path) ? uniqueName(for: url, in: storageDir) : dest
        try safeMove(from: url, to: finalDest)
        return finalDest
    }

    /// Eindeutigen Namen finden: zuerst den Basisnamen, dann "Name 2.ext",
    /// "Name 3.ext" … — ohne Überschreiben. Prüft den Basisnamen zuerst,
    /// damit der Aufruf auch sicher ist, wenn noch kein Konflikt vorliegt.
    func uniqueName(for src: URL, in dir: URL) -> URL {
        let name = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        let base = ext.isEmpty
            ? dir.appendingPathComponent(name)
            : dir.appendingPathComponent("\(name).\(ext)")
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        var i = 2
        while true {
            let candidate = ext.isEmpty
                ? dir.appendingPathComponent("\(name) \(i)")
                : dir.appendingPathComponent("\(name) \(i).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    // MARK: - Batch (Kopieren/Verschieben) — synchron, fehlerisolierend

    /// Führt einen Batch-Lauf aus. Bricht bei Einzelfehler NICHT ab — jede Datei
    /// bekommt ihr eigenes Outcome. Aufrufer sieht successes & failures separat.
    /// Aufrufer entscheidet über Queue (main vs. background).
    func performBatch(sources: [URL], to dest: URL, copy: Bool) -> BatchResult {
        let fm = FileManager.default
        var outcomes: [FileOpOutcome] = []

        for src in sources {
            let dst = dest.appendingPathComponent(src.lastPathComponent)
            let finalDest = fm.fileExists(atPath: dst.path)
                ? uniqueName(for: src, in: dest)
                : dst
            do {
                if copy {
                    try safeCopy(from: src, to: finalDest)
                } else {
                    try safeMove(from: src, to: finalDest)
                }
                outcomes.append(FileOpOutcome(source: src, destination: finalDest,
                                              result: .success, error: nil))
            } catch let opErr as FileOpError {
                outcomes.append(FileOpOutcome(source: src, destination: finalDest,
                                              result: .failure, error: opErr))
            } catch {
                let mapped = FileOpError.from(error)
                outcomes.append(FileOpOutcome(source: src, destination: finalDest,
                                              result: .failure, error: mapped))
            }
        }
        return BatchResult(operation: copy ? .copy : .move,
                           destination: dest, outcomes: outcomes)
    }

    // MARK: - Papierkorb / Größe

    /// Datei aus dem Schelf-Storage in den Papierkorb verschieben.
    /// Externe (nur referenzierte) Dateien werden nicht gelöscht.
    func trash(url: URL) {
        guard isInsideStorage(url) else { return }
        var resultURL: NSURL?
        try? FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
    }

    /// Rekursive Größe eines Verzeichnisses (Bytes über alle regulären Dateien).
    func recursiveSize(of url: URL) -> Int64 {
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

    // MARK: - Helper

    func isInsideStorage(_ url: URL) -> Bool {
        url.path.hasPrefix(storageDir.path)
    }
}
