//
//  AppSettings.swift
//  Schelf
//
//  v2: Zentrale, persistente Einstellungen (UserDefaults-backed).
//  Panel-Opazität, Hotkey, Login-Start, Shelf-Frame, Sortierung, Ablage-Persistenz.
//

import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Konfigurierbarer globaler Hotkey.
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32          // Carbon-Modifier-Flags (cmdKey/shiftKey/…)
    var label: String              // menschenlesbar, z. B. "⌘⇧D"

    static let defaultHotkey = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(cmdKey) | UInt32(shiftKey),
        label: "⌘⇧D"
    )
}

/// Sortierreihenfolge der Ablage.
enum ShelfSort: String, Codable, CaseIterable, Identifiable {
    case addedDesc, addedAsc, nameAsc, nameDesc, sizeDesc, sizeAsc, dateDesc, dateAsc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .addedDesc: return "Zuletzt hinzugefügt"
        case .addedAsc:  return "Zuerst hinzugefügt"
        case .nameAsc:   return "Name ↑"
        case .nameDesc:  return "Name ↓"
        case .sizeDesc:  return "Größe ↓"
        case .sizeAsc:   return "Größe ↑"
        case .dateDesc:  return "Änderungsdatum ↓"
        case .dateAsc:   return "Änderungsdatum ↑"
        }
    }
}

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let opacity       = "schelf.panelOpacity"
        static let hotkey        = "schelf.hotkey"
        static let launchAtLogin = "schelf.launchAtLogin"
        static let showAtLaunch  = "schelf.showAtLaunch"
        static let frame         = "schelf.panelFrame"
        static let sort          = "schelf.sort"
        static let persistShelf  = "schelf.persistShelf"
        static let bookmarks     = "schelf.shelfBookmarks"
    }

    // MARK: Published

    @Published var panelOpacity: Double {
        didSet {
            defaults.set(panelOpacity, forKey: Key.opacity)
        }
    }
    @Published var hotkey: HotkeyConfig { didSet { saveHotkey() } }
    @Published var launchAtLogin: Bool  { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin); applyLaunchAtLogin() } }
    @Published var showAtLaunch: Bool   { didSet { defaults.set(showAtLaunch, forKey: Key.showAtLaunch) } }
    @Published var panelFrame: NSRect?  { didSet { saveFrame() } }
    @Published var sort: ShelfSort      { didSet { defaults.set(sort.rawValue, forKey: Key.sort) } }
    @Published var persistShelf: Bool   { didSet { defaults.set(persistShelf, forKey: Key.persistShelf) } }

    let sortChanged = PassthroughSubject<Void, Never>()

    private var bag = Set<AnyCancellable>()

    /// Aktive Security-Scoped-Zugriffe; beim Beenden oder Überschreiben freigegeben.
    private var activeSecurityScopes: [URL] = []

    // MARK: Init

    private init() {
        var opacity = defaults.object(forKey: Key.opacity) as? Double ?? 0.92
        if opacity < 0.30 { opacity = 0.30 }
        if opacity > 1.0  { opacity = 1.0 }
        panelOpacity = opacity

        if let data = defaults.data(forKey: Key.hotkey),
           let cfg = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            hotkey = cfg
        } else {
            hotkey = .defaultHotkey
        }

        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        showAtLaunch  = defaults.object(forKey: Key.showAtLaunch) as? Bool ?? true
        persistShelf  = defaults.object(forKey: Key.persistShelf) as? Bool ?? true

        if let s = defaults.string(forKey: Key.sort), let v = ShelfSort(rawValue: s) {
            sort = v
        } else {
            sort = .addedDesc
        }

        if let data = defaults.data(forKey: Key.frame),
           let v = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) {
            panelFrame = v.rectValue
        } else {
            panelFrame = nil
        }

        $sort.removeDuplicates().sink { [weak self] _ in self?.sortChanged.send() }.store(in: &bag)
    }

    // MARK: Launch at Login

    private func applyLaunchAtLogin() {
        let bundlePath = Bundle.main.bundlePath
        // SMAppService (macOS 13+) bevorzugen, falls verfügbar; sonst klassischer Login-Item.
        if #available(macOS 13.0, *) {
            if let _ = Bundle.main.bundleIdentifier {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    return
                } catch {
                    // Fällt auf den AppleScript-Pfad zurück.
                }
            }
        }
        setLoginItemLegacy(enable: launchAtLogin, bundlePath: bundlePath)
    }

    private func setLoginItemLegacy(enable: Bool, bundlePath: String) {
        let verb = enable ? "add" : "delete"
        let script = """
        tell application "System Events"
            if not (exists login item whose path is "\(bundlePath)") and "\(verb)" is "add" then
                make login item at end with properties {path:"\(bundlePath)", hidden:false}
            else if (exists login item whose path is "\(bundlePath)") and "\(verb)" is "delete" then
                delete (login item whose path is "\(bundlePath)")
            end if
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    // MARK: Persistenz-Helper

    func saveFrame() {
        guard let rect = panelFrame else { return }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: NSValue(rect: rect),
                                                        requiringSecureCoding: true) {
            defaults.set(data, forKey: Key.frame)
        }
    }

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: Key.hotkey)
        }
    }

    // MARK: Ablage-Bookmarks (Persistenz)

    func saveBookmarks(_ urls: [URL]) {
        guard persistShelf else { return }
        var data: [Data] = []
        for u in urls {
            if let b = try? u.bookmarkData(options: [.withSecurityScope],
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil) {
                data.append(b)
            }
        }
        defaults.set(data, forKey: Key.bookmarks)
    }

    /// Lädt persistierte Bookmarks und startet Security-Scoped-Zugriffe.
    /// Stale Bookmarks werden erneuert und neu gespeichert. Zugriffsentzug
    /// (startAccessing… == false) wird behandelt — die URL wird übersprungen.
    func loadBookmarks() -> [URL] {
        guard persistShelf,
              let arr = defaults.array(forKey: Key.bookmarks) as? [Data] else { return [] }
        var urls: [URL] = []
        var refreshed: [Data] = []
        var anyStale = false

        for b in arr {
            var stale = false
            guard let u = try? URL(resolvingBookmarkData: b,
                                   options: [.withSecurityScope],
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale) else { continue }
            // Paarige Nutzung: start nur, wenn es gelingt; stop erfolgt via stopAllSecurityScopes().
            guard u.startAccessingSecurityScopedResource() else {
                // Berechtigung entzogen / nicht erneuerbar → überspringen, nicht crashen.
                continue
            }
            activeSecurityScopes.append(u)
            urls.append(u)

            if stale {
                anyStale = true
                if let nb = try? u.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) {
                    refreshed.append(nb)
                } else {
                    refreshed.append(b)   // Erneuerung fehlgeschlagen → alte Bookmark behalten.
                }
            } else {
                refreshed.append(b)
            }
        }
        if anyStale { defaults.set(refreshed, forKey: Key.bookmarks) }
        return urls
    }

    /// Beendet alle aktiven Security-Scoped-Zugriffe (paarig zu startAccessing…).
    /// Beim App-Start vorherige Scopes freigeben, bevor neue geladen werden.
    func stopAllSecurityScopes() {
        for u in activeSecurityScopes {
            u.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopes.removeAll()
    }

    func clearBookmarks() {
        stopAllSecurityScopes()
        defaults.removeObject(forKey: Key.bookmarks)
    }
}
