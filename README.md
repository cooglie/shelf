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
  > Die ursprüngliche Zielvorgabe war 10.15+; eine native SwiftUI-App ist dort nicht
  > realisierbar. Für 10.15 müsste die UI komplett in AppKit neu geschrieben werden.

## Bauen

```bash
cd Schelf
bash build.sh
```

Das Skript:
1. Erzeugt das App-Icon (CoreGraphics via `make_icon.swift` → `.icns`).
2. Kompiliert ein Universal-Binary (arm64 + x86_64) mit `swiftc`.
3. Baut das `.app`-Bundle, ad-hoc-signiert es und kopiert es auf den Desktop.

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

## Projektstruktur

```
Schelf/
├── Sources/
│   ├── main.swift                  # @main-Einstieg, NSApplication
│   ├── AppDelegate.swift           # Statusitem, Hotkey (⌘⇧D), Lebenszyklus
│   ├── ShelfPanel.swift            # Schwebendes NSPanel (always-on-top, alle Spaces)
│   ├── ShelfView.swift             # SwiftUI: Drop-Zone, Grid, Toolbar, QuickLook-Trigger
│   ├── ShelfStore.swift            # Sammeln, Dedupe, Move/Copy, Metadaten
│   ├── PasteboardReader.swift      # Datei-URLs aus NSPasteboard
│   ├── ThumbnailProvider.swift     # Bild-Thumbnails + QLThumbnailing
│   └── QuickLookWindowController.swift  # QLPreviewView-Fenster
├── Resources/
│   └── Info.plist                  # LSUIElement (Menüleiste), Icon, min. macOS 12
├── make_icon.swift                 # Zeichnet das App-Icon (CoreGraphics)
└── build.sh                        # Universal-Build + Desktop-Deployment
```

## Hinweise

- Ad-hoc signiert — beim ersten Start ggf. über *Systemeinstellungen → Datenschutz →
  Sicherheit* „Trotzdem öffnen" wählen.
- Der globale Hotkey benötigt keine Sonderberechtigung (Carbon-API).
- v1 ist bewusst schlank: keine Persistenz der Ablage über Neustarts, keine
  iCloud-Sync, kein Drag-out aus der Ablage zurück in den Finder. Solides Fundament
  für Folgeversionen.

## Lizenz

Lokal, privat.
