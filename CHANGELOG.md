# Changelog

All notable changes to Schelf are documented here. Historical version notes
live here, not in the feature list — the README describes the *current* state.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.2] — 2025

### Architecture
- **Extracted `FileCoordinator`** — a pure filesystem layer (`ingest`,
  `safeMove`, `safeCopy`, `uniqueName`, `performBatch`, `trash`,
  `recursiveSize`). `ShelfStore` is now state/UI-facing only and delegates
  all file operations. This separates *state* from *filesystem access*
  and makes file operations testable without a window or pasteboard.

### Reliability (file operations)
- **Batch copy/move is now asynchronous** — runs on a background queue, the
  UI no longer freezes on large files. Buttons disable while a batch runs.
- **Per-file error isolation** — a batch does *not* abort on the first error.
  Each file gets its own outcome (`success` / classified error). "File 8 of 10
  fails" no longer loses the first seven successes.
- **Classified errors**: `sourceMissing`, `destinationExists`,
  `permissionDenied`, `diskFull`, plus underlying Cocoa/POSIX messages.
- **Post-completion summary** in the UI — shows the *actual* state
  ("7 moved, 3 failed: • photo.jpg: permission denied …"), not the planned one.
- **Symlink handling** — symlinks are copied as links, not dereferenced.
  File packages (.app, .pages) are treated as units.
- `uniqueName` now checks the base name first (more robust; previously relied
  on callers pre-checking existence).

### Performance & resources
- **Thumbnails and file sizes computed off the main thread** — `makeItem`
  builds a placeholder, `refreshItemMetadata` loads size/thumbnail on a
  background queue and updates the item. Large files no longer block the UI.
- **Security-scope leak fixed** — `stopAllSecurityScopes()` is now called in
  `applicationWillTerminate`, paired with `startAccessing…` on load.
  Previously access tokens leaked across restarts.

### Tests
- New `Tests/SchelfTests/` suite + `run_tests.sh` runner. 32 tests covering:
  unique-name resolution, dedupe, batch copy/move with error isolation,
  symlink handling, recursive size, and trash semantics. No Xcode project
  required.

### Build & release
- **Removed ad-hoc code signing** — builds are now unsigned (as requested).
- `build.sh` icon generation warns loudly on failure (was silent).
- **GitHub Actions CI** (`.github/workflows/ci.yml`) — builds and tests on
  every push/PR.
- README corrected: signing removed, v1 persistence/drag-out contradictions
  resolved, security model documented.

### License
- Changed from "Local, private" to **MIT**.

## [2.1]

- Shelf persistence across restarts (URL bookmarks with security scope).
- Drag-out from the shelf back into Finder.
- Shake-to-open gesture.
- Sortierung (8 modes), search, bulk actions on selection.
- Open / Open With …, total size, refresh.
- Localization (English, German, French).

## [1.0]

- Initial release. Floating shelf, drag-and-drop collect, global hotkey,
  Quick Look, menu-bar app (LSUIElement). Intentionally lean — no
  persistence, no drag-out (added in 2.1+).
