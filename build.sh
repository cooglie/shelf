#!/bin/bash
#
# build.sh — Kompiliert Schelf (Universal Binary: arm64 + x86_64, macOS 12+)
# und baut das .app-Bundle inkl. Icon. Legt das fertige App auf den Desktop.
#
# Sicherheit:
#   - Kein automatisches Entfernen der Quarantäne-Markierung (Gatekeeper-Schutz
#     bleibt intakt). Lokale Builds sind ohnehin nicht quarantäne-markiert.
#   - rm -rf nur gegen validierte, eindeutige Pfade innerhalb des Build-Ordners.
#   - Ziel auf dem Desktop wird erst nach erfolgreichem Build atomar ersetzt.
#
# Nutzung:  cd Schelf && bash build.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SRC="$ROOT/Sources"
BUILD="$ROOT/.build"
APP_BUNDLE="$BUILD/Schelf.app"
DEPLOY="12.0"
DEPLOY_X86="12.0"

# Frameworks, die wir brauchen.
FRAMEWORKS="-framework AppKit -framework SwiftUI -framework Foundation -framework Quartz -framework QuickLookThumbnailing -framework Carbon -framework Combine -framework ServiceManagement"

echo "=== Schelf Build (Universal: arm64 + x86_64, macOS $DEPLOY+) ==="
echo "SDK: $SDK"
echo ""

# --- Pfad-Validierung vor jedem Löschen ---
# APP_BUNDLE muss strikt innerhalb von BUILD liegen; weder leer noch ein Symlink.
safe_rm() {
    local target="$1"
    local parent="$2"
    if [[ -z "$target" || -z "$parent" ]]; then
        echo "safe_rm: leerer Pfad — abgebrochen." >&2; exit 1
    fi
    # Kanonischen Parent-Pfad bilden.
    local real_parent
    real_parent="$(cd "$parent" 2>/dev/null && pwd -P)" || {
        echo "safe_rm: Parent existiert nicht ($parent) — abgebrochen." >&2; exit 1
    }
    case "$target/" in
        "$real_parent/"*) : ;;   # OK: target liegt unter parent
        *) echo "safe_rm: '$target' liegt nicht unter '$real_parent' — abgebrochen." >&2; exit 1 ;;
    esac
    if [[ -L "$target" ]]; then
        echo "safe_rm: '$target' ist ein Symlink — abgebrochen." >&2; exit 1
    fi
    rm -rf "$target"
}

mkdir -p "$BUILD"
safe_rm "$APP_BUNDLE" "$BUILD"

# Swift-Quellen sammeln.
SOURCES=$(find "$SRC" -name '*.swift' | sort)
echo "Quellen:"
echo "$SOURCES" | sed 's/^/  /'
echo ""

# --- Icon vorab bauen (.icns) ---
build_icon() {
    local ICNS="$ROOT/Resources/AppIcon.icns"
    local ICONSET="$ROOT/Resources/icon.iconset"
    local SRC_IMG="$ROOT/Resources/icon-source.png"
    if [[ -f "$ICNS" ]]; then
        echo "🎨 Icon vorhanden: $ICNS"
        return
    fi
    if [[ ! -f "$SRC_IMG" ]]; then
        echo "🎨 Erzeuge Icon-Quelle via CoreGraphics (make_icon.swift) …"
        swift "$ROOT/make_icon.swift" "$SRC_IMG" || {
            echo "⚠️  WARNUNG: Icon-Erzeugung fehlgeschlagen — Bundle wird OHNE Icon gebaut." >&2
            echo "⚠️  Release mit fehlendem Icon sollte nicht veröffentlicht werden." >&2
            return
        }
    fi
    echo "🎨 Erzeuge .icns aus $SRC_IMG …"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    sips -z 16 16     "$SRC_IMG" --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICONSET/icon_16x16.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$SRC_IMG" --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICONSET/icon_32x32.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$SRC_IMG" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICONSET/icon_128x128.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$SRC_IMG" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICONSET/icon_256x256.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$SRC_IMG" --out "$ICONSET/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICONSET/icon_512x512.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$ICNS"
    rm -rf "$ICONSET"
    echo "✅ $ICNS"
}
build_icon

# --- Apple Silicon (arm64) ---
echo "Kompiliere arm64 (Apple Silicon)…"
swiftc -parse-as-library \
    -target arm64-apple-macosx$DEPLOY \
    -sdk "$SDK" -O \
    $FRAMEWORKS \
    $SOURCES \
    -o "$BUILD/Schelf.arm64"
echo "✅ arm64"

# --- Intel (x86_64) ---
echo "Kompiliere x86_64 (Intel)…"
swiftc -parse-as-library \
    -target x86_64-apple-macosx$DEPLOY_X86 \
    -sdk "$SDK" -O \
    $FRAMEWORKS \
    $SOURCES \
    -o "$BUILD/Schelf.x86_64"
echo "✅ x86_64"

# --- Universal Binary ---
echo "Füge zu Universal Binary zusammen (lipo)…"
lipo -create -output "$BUILD/Schelf" "$BUILD/Schelf.arm64" "$BUILD/Schelf.x86_64"
echo "✅ Universal:"
lipo -archs "$BUILD/Schelf"

# --- .app-Bundle ---
echo ""
echo "Baue .app-Bundle…"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD/Schelf" "$APP_BUNDLE/Contents/MacOS/Schelf"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# --- Auf den Desktop legen (erst nach erfolgreichem Build ersetzen) ---
DESKTOP="$(cd "$HOME/Desktop" && pwd -P)"
TARGET="$DESKTOP/Schelf.app"
echo ""
echo "Lege App auf den Desktop…"
# Nur das eigene App-Bundle überschreiben; Validierung, dass der Pfad stimmt.
if [[ -z "$TARGET" || "$TARGET" != "$DESKTOP/Schelf.app" || -L "$TARGET" ]]; then
    echo "Unerwarteter Zielpfad: '$TARGET' — abgebrochen." >&2; exit 1
fi
# Bestehendes Ziel nach Backup verschieben (atomar), dann Neues kopieren.
if [[ -d "$TARGET" ]]; then
    mv "$TARGET" "$TARGET.replacing.$$.tmp"
fi
# ditto kopiert das Bundle sauber (Resource-Forks/Metadaten intakt).
ditto "$APP_BUNDLE" "$TARGET"
# Erfolg prüfen: Executable muss vorhanden sein.
if [[ -f "$TARGET/Contents/MacOS/Schelf" ]]; then
    rm -rf "$TARGET.replacing.$$.tmp" 2>/dev/null || true
else
    echo "Build-Output fehlt im Ziel — altes Ziel wiederhergestellt." >&2
    rm -rf "$TARGET"
    [[ -d "$TARGET.replacing.$$.tmp" ]] && mv "$TARGET.replacing.$$.tmp" "$TARGET"
    exit 1
fi

echo ""
echo "✅ Fertig: $TARGET"
echo "   Architekturen: $(lipo -archs "$TARGET/Contents/MacOS/Schelf")"
echo ""
echo "Starten:  open \"$TARGET\""
