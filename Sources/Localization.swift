//
//  Localization.swift
//  Schelf
//
//  Einfaches, selbstständiges Lokalisierungssystem (ohne .lproj-Bundles):
//  - Language-Enum (EN = Default, DE, FR)
//  - String-Tabellen pro Sprache
//  - L10n-Helper mit Live-Aktualisierung (objectWillChange) bei Sprachwechsel
//
//  Alle UI-Strings laufen über L10n.string(.key). ShelfSort-Labels über
//  ShelfSort.localizedName(for:).
//

import Foundation
import Combine

// MARK: - Sprache

enum Language: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case german  = "de"
    case french  = "fr"

    var id: String { rawValue }

    /// Anzeigename in der jeweiligen Landessprache (für den Sprach-Picker).
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german:  return "Deutsch"
        case .french:  return "Français"
        }
    }
}

// MARK: - Lokalisierungs-Schlüssel

/// Alle übersetzbaren Strings der App.
enum L10nKey: String {
    // App / generisch
    case appName = "appName"
    case ok = "ok"
    case cancel = "cancel"

    // Header / Toolbar
    case addFiles = "addFiles"
    case addFilesHelp = "addFilesHelp"
    case refresh = "refresh"
    case refreshHelp = "refreshHelp"
    case copy = "copy"
    case copySelectedHelp = "copySelectedHelp"
    case copyAllHelp = "copyAllHelp"
    case move = "move"
    case moveSelectedHelp = "moveSelectedHelp"
    case moveAllHelp = "moveAllHelp"
    case clear = "clear"
    case removeSelectedHelp = "removeSelectedHelp"
    case clearShelfHelp = "clearShelfHelp"
    case settings = "settings"
    case filterPlaceholder = "filterPlaceholder"

    // Empty State
    case emptyTitle = "emptyTitle"
    case emptyHint = "emptyHint"

    // Footer
    case objectSingular = "objectSingular"
    case objectPlural = "objectPlural"
    case selectedCount = "selectedCount"

    // Settings-Popover
    case settingsTitle = "settingsTitle"
    case opacityLabel = "opacityLabel"
    case keepAcrossRestarts = "keepAcrossRestarts"
    case showAtLaunch = "showAtLaunch"
    case launchAtLogin = "launchAtLogin"
    case shakeToOpen = "shakeToOpen"
    case globalHotkey = "globalHotkey"
    case resetHotkey = "resetHotkey"
    case hotkeyHint = "hotkeyHint"
    case language = "language"

    // Kontextmenü
    case preview = "preview"
    case open = "open"
    case openWith = "openWith"
    case revealInFinder = "revealInFinder"
    case removeFromShelf = "removeFromShelf"

    // ShelfStore: Picker / Panels / Alerts
    case pickerAddPrompt = "pickerAddPrompt"
    case pickerAddTitle = "pickerAddTitle"
    case copyPrompt = "copyPrompt"
    case movePrompt = "movePrompt"
    case copyTitle = "copyTitle"
    case moveTitle = "moveTitle"
    case confirmCopy = "confirmCopy"
    case confirmMove = "confirmMove"
    case batchConfirmMsg = "batchConfirmMsg"
    case openWithPrompt = "openWithPrompt"
    case openWithTitle = "openWithTitle"

    // Fehler
    case errorMoveCopyTitle = "errorMoveCopyTitle"
    case errorDestExists = "errorDestExists"

    // Batch-Zusammenfassung
    case batchSummaryTitle = "batchSummaryTitle"
    case batchAllOk = "batchAllOk"
    case batchPartial = "batchPartial"
    case batchRunning = "batchRunning"

    // Statusleisten-Menü
    case menuToggle = "menuToggle"
    case menuAddFile = "menuAddFile"
    case menuRefresh = "menuRefresh"
    case menuClear = "menuClear"
    case menuAbout = "menuAbout"
    case menuQuit = "menuQuit"
    case aboutCredits = "aboutCredits"

    // Sortier-Labels
    case sortAddedDesc = "sortAddedDesc"
    case sortAddedAsc  = "sortAddedAsc"
    case sortNameAsc   = "sortNameAsc"
    case sortNameDesc  = "sortNameDesc"
    case sortSizeDesc  = "sortSizeDesc"
    case sortSizeAsc   = "sortSizeAsc"
    case sortDateDesc  = "sortDateDesc"
    case sortDateAsc   = "sortDateAsc"
}

// MARK: - Tabellen

private let tableEN: [L10nKey: String] = [
    .appName: "Schelf",
    .ok: "OK",
    .cancel: "Cancel",

    .addFiles: "Add",
    .addFilesHelp: "Add files via picker",
    .refresh: "Refresh",
    .refreshHelp: "Re-read metadata",
    .copy: "Copy",
    .copySelectedHelp: "Copy selection",
    .copyAllHelp: "Copy all",
    .move: "Move",
    .moveSelectedHelp: "Move selection",
    .moveAllHelp: "Move all",
    .clear: "Clear",
    .removeSelectedHelp: "Remove selection",
    .clearShelfHelp: "Clear shelf",
    .settings: "Settings",
    .filterPlaceholder: "Filter…",

    .emptyTitle: "Drop files here",
    .emptyHint: "Collect, copy or move —\nsummon anytime with %@.",

    .objectSingular: "item",
    .objectPlural: "items",
    .selectedCount: "%d selected",

    .settingsTitle: "Settings",
    .opacityLabel: "Opacity: %d%%",
    .keepAcrossRestarts: "Keep shelf across restarts",
    .showAtLaunch: "Show at launch",
    .launchAtLogin: "Launch at login",
    .shakeToOpen: "Shake mouse to open Schelf",
    .globalHotkey: "Global Hotkey",
    .resetHotkey: "Reset",
    .hotkeyHint: "Reassigning the hotkey via keyboard recorder is coming in v3.",
    .language: "Language",

    .preview: "Preview",
    .open: "Open",
    .openWith: "Open With…",
    .revealInFinder: "Reveal in Finder",
    .removeFromShelf: "Remove from Shelf",

    .pickerAddPrompt: "Add to Shelf",
    .pickerAddTitle: "Select files",
    .copyPrompt: "Copy here",
    .movePrompt: "Move here",
    .copyTitle: "Copy shelf to…",
    .moveTitle: "Move shelf to…",
    .confirmCopy: "Confirm Copy",
    .confirmMove: "Confirm Move",
    .batchConfirmMsg: "%d item(s) to\n%@\n%@?",
    .openWithPrompt: "Open with",
    .openWithTitle: "Choose app to open %@",

    .errorMoveCopyTitle: "Error moving/copying",
    .errorDestExists: "A file with this name already exists at the destination.",

    .batchSummaryTitle: "Batch complete",
    .batchAllOk: "%d file(s) copied successfully.",
    .batchPartial: "%d succeeded, %d failed.",
    .batchRunning: "Working…",

    .menuToggle: "Toggle Schelf (%@)",
    .menuAddFile: "Add file…",
    .menuRefresh: "Refresh shelf",
    .menuClear: "Clear shelf",
    .menuAbout: "About Schelf",
    .menuQuit: "Quit Schelf",
    .aboutCredits: "Floating shelf for macOS.",

    .sortAddedDesc: "Newest first",
    .sortAddedAsc:  "Oldest first",
    .sortNameAsc:   "Name ↑",
    .sortNameDesc:  "Name ↓",
    .sortSizeDesc:  "Size ↓",
    .sortSizeAsc:   "Size ↑",
    .sortDateDesc:  "Date modified ↓",
    .sortDateAsc:   "Date modified ↑",
]

private let tableDE: [L10nKey: String] = [
    .appName: "Schelf",
    .ok: "OK",
    .cancel: "Abbrechen",

    .addFiles: "Hinzufügen",
    .addFilesHelp: "Dateien über Picker hinzufügen",
    .refresh: "Aktualisieren",
    .refreshHelp: "Metadaten neu einlesen",
    .copy: "Kopieren",
    .copySelectedHelp: "Auswahl kopieren",
    .copyAllHelp: "Alle kopieren",
    .move: "Verschieben",
    .moveSelectedHelp: "Auswahl verschieben",
    .moveAllHelp: "Alle verschieben",
    .clear: "Leeren",
    .removeSelectedHelp: "Auswahl entfernen",
    .clearShelfHelp: "Ablage leeren",
    .settings: "Einstellungen",
    .filterPlaceholder: "Filtern…",

    .emptyTitle: "Dateien hierher ziehen",
    .emptyHint: "Sammeln, kopieren oder verschieben —\nmit %@ jederzeit einblenden.",

    .objectSingular: "Objekt",
    .objectPlural: "Objekte",
    .selectedCount: "%d ausgewählt",

    .settingsTitle: "Einstellungen",
    .opacityLabel: "Opazität: %d%%",
    .keepAcrossRestarts: "Ablage über Neustarts behalten",
    .showAtLaunch: "Beim Start anzeigen",
    .launchAtLogin: "Bei Anmeldung starten",
    .shakeToOpen: "Maus schütteln öffnet Schelf",
    .globalHotkey: "Globaler Hotkey",
    .resetHotkey: "Zurücksetzen",
    .hotkeyHint: "Hotkey-Neuzuweisung via Tastatur-Recorder folgt in v3.",
    .language: "Sprache",

    .preview: "Vorschau",
    .open: "Öffnen",
    .openWith: "Öffnen mit …",
    .revealInFinder: "Im Finder zeigen",
    .removeFromShelf: "Aus Ablage entfernen",

    .pickerAddPrompt: "Zur Ablage hinzufügen",
    .pickerAddTitle: "Dateien auswählen",
    .copyPrompt: "Hierher kopieren",
    .movePrompt: "Hierher verschieben",
    .copyTitle: "Ablage kopieren nach …",
    .moveTitle: "Ablage verschieben nach …",
    .confirmCopy: "Kopieren bestätigen",
    .confirmMove: "Verschieben bestätigen",
    .batchConfirmMsg: "%d Objekt(e) nach \n%@\n%@?",
    .openWithPrompt: "Öffnen mit",
    .openWithTitle: "App wählen, um %@ zu öffnen",

    .errorMoveCopyTitle: "Fehler beim Verschieben/Kopieren",
    .errorDestExists: "Eine Datei mit diesem Namen existiert im Ziel bereits.",

    .batchSummaryTitle: "Stapel abgeschlossen",
    .batchAllOk: "%d Datei(en) erfolgreich kopiert.",
    .batchPartial: "%d erfolgreich, %d fehlgeschlagen.",
    .batchRunning: "Arbeite…",

    .menuToggle: "Schelf ein-/ausblenden (%@)",
    .menuAddFile: "Datei hinzufügen …",
    .menuRefresh: "Ablage aktualisieren",
    .menuClear: "Ablage leeren",
    .menuAbout: "Über Schelf",
    .menuQuit: "Schelf beenden",
    .aboutCredits: "Schwebende Ablage für macOS.",

    .sortAddedDesc: "Zuletzt hinzugefügt",
    .sortAddedAsc:  "Zuerst hinzugefügt",
    .sortNameAsc:   "Name ↑",
    .sortNameDesc:  "Name ↓",
    .sortSizeDesc:  "Größe ↓",
    .sortSizeAsc:   "Größe ↑",
    .sortDateDesc:  "Änderungsdatum ↓",
    .sortDateAsc:   "Änderungsdatum ↑",
]

private let tableFR: [L10nKey: String] = [
    .appName: "Schelf",
    .ok: "OK",
    .cancel: "Annuler",

    .addFiles: "Ajouter",
    .addFilesHelp: "Ajouter des fichiers via le sélecteur",
    .refresh: "Actualiser",
    .refreshHelp: "Relire les métadonnées",
    .copy: "Copier",
    .copySelectedHelp: "Copier la sélection",
    .copyAllHelp: "Tout copier",
    .move: "Déplacer",
    .moveSelectedHelp: "Déplacer la sélection",
    .moveAllHelp: "Tout déplacer",
    .clear: "Vider",
    .removeSelectedHelp: "Retirer la sélection",
    .clearShelfHelp: "Vider l'étagère",
    .settings: "Réglages",
    .filterPlaceholder: "Filtrer…",

    .emptyTitle: "Déposez des fichiers ici",
    .emptyHint: "Collecter, copier ou déplacer —\ninvoquez à tout moment avec %@.",

    .objectSingular: "objet",
    .objectPlural: "objets",
    .selectedCount: "%d sélectionné(s)",

    .settingsTitle: "Réglages",
    .opacityLabel: "Opacité : %d%%",
    .keepAcrossRestarts: "Conserver l'étagère entre les redémarrages",
    .showAtLaunch: "Afficher au lancement",
    .launchAtLogin: "Lancer à la connexion",
    .shakeToOpen: "Secouer la souris pour ouvrir Schelf",
    .globalHotkey: "Raccourci global",
    .resetHotkey: "Réinitialiser",
    .hotkeyHint: "La réassignation du raccourci via enregistreur clavier arrive en v3.",
    .language: "Langue",

    .preview: "Aperçu",
    .open: "Ouvrir",
    .openWith: "Ouvrir avec…",
    .revealInFinder: "Afficher dans le Finder",
    .removeFromShelf: "Retirer de l'étagère",

    .pickerAddPrompt: "Ajouter à l'étagère",
    .pickerAddTitle: "Choisir des fichiers",
    .copyPrompt: "Copier ici",
    .movePrompt: "Déplacer ici",
    .copyTitle: "Copier l'étagère vers…",
    .moveTitle: "Déplacer l'étagère vers…",
    .confirmCopy: "Confirmer la copie",
    .confirmMove: "Confirmer le déplacement",
    .batchConfirmMsg: "%d objet(s) vers\n%@\n%@ ?",
    .openWithPrompt: "Ouvrir avec",
    .openWithTitle: "Choisir l'app pour ouvrir %@",

    .errorMoveCopyTitle: "Erreur lors du déplacement/copie",
    .errorDestExists: "Un fichier avec ce nom existe déjà à la destination.",

    .batchSummaryTitle: "Lot terminé",
    .batchAllOk: "%d fichier(s) copié(s) avec succès.",
    .batchPartial: "%d réussi(s), %d échoué(s).",
    .batchRunning: "En cours…",

    .menuToggle: "Afficher/Masquer Schelf (%@)",
    .menuAddFile: "Ajouter un fichier…",
    .menuRefresh: "Actualiser l'étagère",
    .menuClear: "Vider l'étagère",
    .menuAbout: "À propos de Schelf",
    .menuQuit: "Quitter Schelf",
    .aboutCredits: "Étagère flottante pour macOS.",

    .sortAddedDesc: "Dernier ajouté",
    .sortAddedAsc:  "Premier ajouté",
    .sortNameAsc:   "Nom ↑",
    .sortNameDesc:  "Nom ↓",
    .sortSizeDesc:  "Taille ↓",
    .sortSizeAsc:   "Taille ↑",
    .sortDateDesc:  "Date de modification ↓",
    .sortDateAsc:   "Date de modification ↑",
]

private func table(for lang: Language) -> [L10nKey: String] {
    switch lang {
    case .english: return tableEN
    case .german:  return tableDE
    case .french:  return tableFR
    }
}

// MARK: - L10n

/// Zentraler Lokalisierungs-Helper. Als ObservableObject, damit SwiftUI-Views
/// und AppSettings bei Sprachwechsel live neu rendern.
final class L10n: ObservableObject {

    static let shared = L10n()

    /// Wird gesendet, wenn die Sprache geändert wird.
    static let languageChanged = Notification.Name("schelf.languageChanged")

    /// Aktuelle Sprache. Direkt nach `AppSettings.language` gespiegelt, damit
    /// Views, die L10n beobachten, live aktualisieren.
    @Published var language: Language = .english

    private var bag = Set<AnyCancellable>()

    private init() {
        // Sprache aus AppSettings übernehmen und synchron halten.
        let s = AppSettings.shared
        language = s.language

        s.$language
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] lang in
                guard let self = self else { return }
                self.language = lang
                NotificationCenter.default.post(name: Self.languageChanged, object: nil, userInfo: ["language": lang])
            }
            .store(in: &bag)
    }

    /// Übersetzten String für einen Schlüssel holen.
    static func string(_ key: L10nKey) -> String {
        table(for: shared.language)[key] ?? tableEN[key] ?? key.rawValue
    }

    /// Übersetzten String mit einem Format-Argument.
    static func string(_ key: L10nKey, _ arg: CVarArg) -> String {
        let fmt = string(key)
        return String(format: fmt, arguments: [arg])
    }

    /// Übersetzten String mit mehreren Format-Argumenten.
    static func string(_ key: L10nKey, _ args: CVarArg...) -> String {
        let fmt = string(key)
        return String(format: fmt, arguments: args)
    }
}
