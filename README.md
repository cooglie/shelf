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
  > The original target was 10.15+; a native SwiftUI app isn't feasible there.
  > For 10.15 the UI would have to be rewritten entirely in AppKit.

## Build

```bash
cd Schelf
bash build.sh
```

The script:
1. Generates the app icon if not already cached (CoreGraphics via
   `make_icon.swift` → `.icns`).
2. Compiles a universal binary (arm64 + x86_64) with `swiftc`.
3. Builds the `.app` bundle and copies it to the Desktop.

The app is **unsigned** (no ad-hoc signature). On first launch macOS will
block it — choose *System Settings → Privacy & Security → Open Anyway*.

### Run the tests

```bash
bash run_tests.sh
```

Builds and runs the `FileCoordinator` test suite (no Xcode project required).
Tests cover: unique-name resolution, dedupe, batch copy/move with
error isolation, symlink handling, recursive size, and trash semantics.

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

## Project Structure

```
Schelf/
├── Sources/
│   ├── main.swift                  # @main entry, NSApplication
│   ├── AppDelegate.swift           # Status item, hotkey (⌘⇧D), lifecycle
│   ├── ShelfPanel.swift            # Floating NSPanel (always-on-top, all Spaces)
│   ├── ShelfView.swift             # SwiftUI: drop zone, grid, toolbar, QuickLook trigger
│   ├── ShelfStore.swift            # Collect, dedupe, metadata, UI-facing state (delegates FS to FileCoordinator)
│   ├── FileCoordinator.swift       # Pure filesystem layer: ingest, safeMove/Copy, uniqueName, batch, trash, size
│   ├── PasteboardReader.swift      # File URLs from NSPasteboard
│   ├── ThumbnailProvider.swift     # Image thumbnails + QLThumbnailing
│   ├── QuickLookWindowController.swift  # QLPreviewView window
│   └── Localization.swift          # EN/DE/FR language tables + L10n helper
├── Resources/
│   └── Info.plist                  # LSUIElement (menu bar), icon, min. macOS 12
├── make_icon.swift                 # Draws the app icon (CoreGraphics)
├── build.sh                        # Universal build + Desktop deployment
├── run_tests.sh                    # Builds + runs FileCoordinator tests
├── Tests/SchelfTests/              # Test suite (no Xcode project needed)
└── .github/workflows/ci.yml        # CI: build + test on every push/PR
```

## Security Model

Schelf stores *references* to collected files, not their contents. The actual
files are moved into a private storage folder
(`~/Library/Application Support/Schelf/Shelf`).

**Access scope & lifetime:**
- File-system access uses **URL bookmarks with security scope** when the source
  is outside the app's sandbox. A scope is `start`ed when a bookmark is resolved
  and `stop`ed when the app terminates or the bookmark is cleared — paired
  calls, no leaked access tokens.
- Invalid or unreachable bookmarks are **skipped**, never crash the app. Stale
  bookmarks are refreshed on load and re-persisted.
- Removing a file from the shelf trashes the storage copy (it is not deleted
  permanently); external originals are never modified by removal.

**Logging:** Schelf does not log file paths or metadata to disk.

**Performance:** thumbnails and file sizes are computed on a background queue
so large files never block the UI. Batch copy/move also runs off the main
thread; the UI shows a post-completion summary (successes + per-file failures).

**Error handling:** every file operation is treated as fallible. Batch
operations do not abort on the first error — each file gets its own outcome
(success or a classified error: missing source, permission denied, disk full,
…). The summary shows the *actual* state, not the planned one.

## Notes

- Unsigned build — on first launch choose “Open Anyway” under *System Settings
  → Privacy & Security*.
- The global hotkey needs no special permission (Carbon API).

## License

MIT License. See [`LICENSE`](LICENSE).
