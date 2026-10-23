# Schelf — Floating Shelf for macOS

A floating, always-on-top shelf: drag files in, collect them, copy or move them
as a batch, show previews — all from an elegant, native SwiftUI panel toggled by
a global shortcut (⌘⇧D).

## Features (v2)

### New in v2 (15 Features)

1. **Shelf persistence** — contents survive restarts (URL bookmarks).
2. **Multi-select** — select multiple files via click; bulk actions act only on the selection.
3. **Search / filter** — live filter by name.
4. **Sorting** — name, size, date, added (↕).
5. **Drag-out** — drag files out of the shelf back into Finder or other apps.
6. **Opacity slider** — adjust background transparency (30–100%).
7. **Total size** — sum of the shelf shown in the footer.
8. **QuickLook navigation** — ← / → steps through all previews.
9. **Open** — open a file in its default app (context menu).
10. **Open With…** — app picker via file picker.
11. **Frame persistence** — panel position & size are saved.
12. **Settings** — window with opacity, persistence, login-start, hotkey info.
13. **+ button** — add files via NSOpenPanel.
14. **Refresh** — re-read metadata & thumbnails.
15. **Keyboard** — ⌫ removes selection, ⎋ clears selection.

### New in v2.1

- **Language selection** — choose between **English** (default), **Deutsch** and
  **Français** in Settings. The entire UI — toolbar, menus, alerts, status-bar
  menu, About panel — switches live, no restart required. The choice persists
  across restarts.

### Features (v1, still included)

- **Drag files onto a floating shelf** — drag & drop from Finder or any app;
  multiple files at once; duplicates are detected.
- **Move or copy as a batch** — one click moves/copies the entire shelf contents
  into a chosen folder (`NSOpenPanel`). Name conflicts are resolved uniquely
  (`Name 2.ext` …). Moved files are removed from the shelf, copied ones stay.
- **Previews for images and documents** — images are decoded directly
  (thumbnail via `CGImageSource`), other files via `QuickLookThumbnailing`.
  Double-click opens the full QuickLook preview (`QLPreviewView`).
- **Open the shelf via global shortcut** — **⌘⇧D** toggles the panel,
  registered system-wide via Carbon `RegisterEventHotKey`.
- **Elegant, native SwiftUI design** — floating `NSPanel` with transparent
  titlebar, always-on-top across all Spaces, draggable, thumbnail grid with
  context menus (Preview · Reveal in Finder · Remove), status-bar icon.

## System Requirements

- **macOS 12 (Monterey) or newer** — SwiftUI needs Big Sur; the native modifiers
  used here (`.foregroundStyle`, `.alert(message:)`) need Monterey. Runs on both
  Apple Silicon (arm64) and Intel Macs (x86_64).
## Build

```bash
cd Schelf
bash build.sh
```

The script:
1. Generates the app icon (CoreGraphics via `make_icon.swift` → `.icns`).
2. Compiles a universal binary (arm64 + x86_64) with `swiftc`.
3. Builds the `.app` bundle, and copies it to the Desktop.

No Xcode project needed — just the Command Line Tools.

```bash
open ~/Desktop/Schelf.app
```

## Usage

| Action | How |
|---|---|
| Toggle shelf | **⌘⇧D** (global) or status-bar menu |
| Add a file | Drag onto the panel |
| Open preview | Double-click a thumbnail |
| Reveal in Finder | Right-click → “Reveal in Finder” |
| Copy all | 📄 button top-right → choose folder |
| Move all | → button top-right → choose folder |
| Clear shelf | 🗑 button (files are not deleted) |
| Quit | Status-bar menu → “Quit Schelf” |


## Notes

- on first launch you may need to choose “Open Anyway” under
  *System Settings → Privacy & Security*.
- The global hotkey needs no special permission (Carbon API).
- v1 is intentionally lean: no shelf persistence across restarts, no iCloud
  sync, no drag-out from the shelf back into Finder. A solid foundation for
  follow-up versions.

## License

Local, private.



# Schelf — Schwebende Ablage für macOS

Eine schwebende, immer im Vordergrund liegende Ablage: Dateien reinziehen, sammeln,
als Stapel kopieren oder verschieben, Vorschauen anzeigen — alles aus einem eleganten,
nativem SwiftUI-Panel, das per globalem Shortcut (⌘⇧D) ein- und ausgeblendet wird.

## Funktionen (v2)

### Neu in v2 (15 Features)

1. **Ablage-Persistenz** — Inhalte bleiben über Neustarts erhalten (URL-Bookmarks).
2. **Multi-Select** — mehrere Dateien per Klick auswählen, Bulk-Aktionen wirken nur auf die Auswahl.
3. **Suche/Filter** — nach Name live filtern.
4. **Sortierung** — Name, Größe, Datum, Hinzugefügt (↕).
5. **Drag-out** — Dateien aus der Ablage zurück in Finder/andere Apps ziehen.
6. **Opazitäts-Regler** — Hintergrund-Transparenz einstellen (30–100 %).
7. **Gesamtgröße** — Summe der Ablage im Footer.
8. **QuickLook-Navigation** — ← / → blättert durch alle Vorschauen.
9. **Öffnen** — Datei in Standard-App öffnen (Kontextmenü).
10. **Öffnen mit …** — App-Wähler über Datei-Picker.
11. **Frame-Persistenz** — Position & Größe des Panels werden gespeichert.
12. **Einstellungen** — Fenster mit Opazität, Persistenz, Login-Start, Hotkey-Info.
13. **+ Button** — Dateien über NSOpenPanel hinzufügen.
14. **Refresh** — Metadaten & Thumbnails neu einlesen.
15. **Tastatur** — ⌫ entfernt Auswahl, ⎋ hebt Auswahl auf.

### Funktionen (v1, weiterhin enthalten)

- **Dateien auf eine schwebende Ablage ziehen** — Drag & Drop aus dem Finder oder
  beliebigen Apps; mehrere Dateien gleichzeitig; Duplikate werden erkannt.
- **Gesammelt verschieben oder kopieren** — ein Klick verschiebt/kopiert den gesamten
  Ablage-Inhalt in einen gewählten Ordner (`NSOpenPanel`). Namenskonflikte werden
  automatisch eindeutig aufgelöst (`Name 2.ext` …). Verschobene Dateien werden aus
  der Ablage entfernt, kopierte bleiben.
- **Vorschauen für Bilder und Dokumente** — Bilder werden direkt dekodiert
  (Thumbnail via `CGImageSource`), andere Dateien via `QuickLookThumbnailing`.
  Doppelklick öffnet die vollständige QuickLook-Vorschau (`QLPreviewView`).
- **Ablage per globalem Shortcut öffnen** — **⌘⇧D** blendet das Panel ein/aus,
  systemweit registriert via Carbon `RegisterEventHotKey`.
- **Elegantes, natives SwiftUI-Design** — schwebendes `NSPanel` mit transparenter
  Titlebar, always-on-top über allen Spaces, draggable, Thumbnail-Grid mit
  Kontextmenüs (Vorschau · Im Finder zeigen · Entfernen), Statusleisten-Icon.

## Systemanforderungen

- **macOS 12 (Monterey) oder neuer** — SwiftUI benötigt Big Sur, die hier genutzten
  nativen Modifikatoren (`.foregroundStyle`, `.alert(message:)`) Monterey. Damit
  laufen sowohl Apple Silicon (arm64) als auch Intel-Macs (x86_64).

## Bauen

```bash
cd Schelf
bash build.sh
```

Das Skript:
1. Erzeugt das App-Icon (CoreGraphics via `make_icon.swift` → `.icns`).
2. Kompiliert ein Universal-Binary (arm64 + x86_64) mit `swiftc`.
3. Baut das `.app`-Bundle, und kopiert es auf den Desktop.

Kein Xcode-Projekt nötig — nur die Command Line Tools.

```bash
open ~/Desktop/Schelf.app
```

## Bedienung

| Aktion | Wie |
|---|---|
| Ablage ein-/ausblenden | **⌘⇧D** (global) oder Statusleisten-Menü |
| Datei hinzufügen | Auf das Panel ziehen |
| Vorschau öffnen | Doppelklick auf Thumbnail |
| Im Finder zeigen | Rechtsklick → „Im Finder zeigen" |
| Alle kopieren | 📄-Button oben rechts → Ordner wählen |
| Alle verschieben | →-Button oben rechts → Ordner wählen |
| Ablage leeren | 🗑-Button (Dateien werden nicht gelöscht) |
| Beenden | Statusleisten-Menü → „Schelf beenden" |



## Hinweise

- beim ersten Start ggf. über *Systemeinstellungen → Datenschutz →
  Sicherheit* „Trotzdem öffnen" wählen.
- Der globale Hotkey benötigt keine Sonderberechtigung (Carbon-API).
- v1 ist bewusst schlank: keine Persistenz der Ablage über Neustarts, keine
  iCloud-Sync, kein Drag-out aus der Ablage zurück in den Finder. Solides Fundament
  für Folgeversionen.

## Lizenz

Lokal, privat.
