//
//  ShelfView.swift
//  Schelf
//
//  Hauptansicht der schwebenden Ablage: Drop-Zone, Thumbnail-Grid, Toolbar,
//  Einzeleintrag-Kontextmenü, Fehleranzeige.
//
//  v2: Multi-Select + Bulk-Aktionen, Suche, Sortierung, Drag-out, Tastatur,
//      +-Button, Refresh, Opazitäts-Regler, Öffnen / Öffnen mit …, Gesamtgröße.
//

import AppKit
import SwiftUI

/// Environment-Key, um QuickLook aus beliebigen Subviews anzustoßen.
private struct OpenQuickLookKey: EnvironmentKey {
    static let defaultValue = OpenQuickLookAction { _ in }
}
struct OpenQuickLookAction {
    let perform: (URL) -> Void
    func callAsFunction(_ url: URL) { perform(url) }
}
extension EnvironmentValues {
    var openQuickLook: OpenQuickLookAction {
        get { self[OpenQuickLookKey.self] }
        set { self[OpenQuickLookKey.self] = newValue }
    }
}

struct ShelfView: View {

    @ObservedObject var store: ShelfStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openQuickLook) var openQuickLook

    @State private var dropHover = false
    @State private var selection: Set<UUID> = []
    @State private var showSettings = false

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbarRow
            Divider()
            content
            Divider()
            footer
        }
        .background(background)
        .opacity(settings.panelOpacity)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .alert("Fehler beim Verschieben/Kopieren",
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Schelf")
                .font(.system(size: 13, weight: .semibold))
            Spacer()

            Button { store.addViaPicker() } label: {
                Label("Hinzufügen", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .help("Dateien über Picker hinzufügen")
            Button { store.refresh() } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help("Metadaten neu einlesen")

            Divider().frame(height: 14)

            Button { store.copyAll(selected: selectedItems) } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .help(bulkHelp("Auswahl kopieren", "Alle kopieren"))
            .disabled(store.items.isEmpty)

            Button { store.moveAll(selected: selectedItems) } label: {
                Label("Verschieben", systemImage: "arrow.right.doc")
                    .labelStyle(.iconOnly)
            }
            .help(bulkHelp("Auswahl verschieben", "Alle verschieben"))
            .disabled(store.items.isEmpty)

            Button {
                if selection.isEmpty {
                    store.clear()
                } else {
                    store.remove(items: selectedItems)
                    selection.removeAll()
                }
            } label: {
                Label("Leeren", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help(bulkHelp("Auswahl entfernen", "Ablage leeren"))
            .disabled(store.items.isEmpty)

            Button { showSettings = true } label: {
                Label("Einstellungen", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .help("Einstellungen")
            .popover(isPresented: $showSettings) { settingsPopover }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Toolbar (Suche + Sortierung)

    private var toolbarRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Filtern…", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { }
            if !store.searchText.isEmpty {
                Button { store.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 12)
            Picker("", selection: $settings.sort) {
                ForEach(ShelfSort.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Content / Drop

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            gridContent
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.sortedItems()) { item in
                    cell(for: item)
                }
            }
            .padding(10)
        }
        .focusable()
    }

    // MARK: - Tastatur (NSEvent Local Monitor)

    @State private var keyMonitor: Any?

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) as NSEvent?
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard NSApp.keyWindow != nil else { return event }
        switch event.keyCode {
        case 51: // Backspace/Delete
            if !selection.isEmpty {
                store.remove(items: selectedItems)
                selection.removeAll()
                return nil
            }
        case 53: // Escape
            if !selection.isEmpty {
                selection.removeAll()
                return nil
            }
        default:
            break
        }
        return event
    }

    private func cell(for item: ShelfStore.Item) -> some View {
        ShelfCell(item: item,
                  selected: selection.contains(item.id),
                  onOpen: { openQuickLook(item.url) },
                  onRemove: {
                      store.remove(item)
                      selection.remove(item.id)
                  },
                  onOpenDefault: { store.open(item) },
                  onOpenWith: { store.openWith(item) },
                  onToggleSelect: { toggleSelect(item.id) })
            .gesture(TapGesture().onEnded { toggleSelect(item.id) })
            .gesture(TapGesture(count: 2).onEnded { openQuickLook(item.url) })
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Dateien hierher ziehen")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Sammeln, kopieren oder verschieben —\nmit \(settings.hotkey.label) jederzeit einblenden.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTarget)
    }

    private var background: some View {
        Color.clear
            .background(dropTarget)
    }

    private var dropTarget: some View {
        DropArea { pasteboard in
            store.addFromPasteboard(pasteboard)
        } hoverChanged: { hover in
            dropHover = hover
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(dropHover ? Color.accentColor.opacity(0.6) : Color.clear,
                              lineWidth: 2)
                .padding(4)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(store.totalCount) \(store.totalCount == 1 ? "Objekt" : "Objekte")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if store.totalSizeBytes > 0 {
                Text("· " + formatBytes(store.totalSizeBytes))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if !selection.isEmpty {
                Text("· \(selection.count) ausgewählt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            Spacer()
            Text(settings.hotkey.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Settings-Popover

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Einstellungen")
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Opazität: \(Int(settings.panelOpacity * 100))%")
                    .font(.system(size: 11))
                Slider(value: $settings.panelOpacity, in: 0.3...1.0, step: 0.02)
                    .frame(width: 220)
            }

            Toggle("Ablage über Neustarts behalten", isOn: $settings.persistShelf)
                .font(.system(size: 11))
            Toggle("Beim Start anzeigen", isOn: $settings.showAtLaunch)
                .font(.system(size: 11))
            Toggle("Bei Anmeldung starten", isOn: $settings.launchAtLogin)
                .font(.system(size: 11))

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Globaler Hotkey")
                    .font(.system(size: 11, weight: .medium))
                HStack {
                    Text(settings.hotkey.label)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button("Zurücksetzen") {
                        settings.hotkey = .defaultHotkey
                    }
                    .font(.system(size: 11))
                }
                Text("Hotkey-Neuzuweisung via Tastatur-Recorder folgt in v3.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    // MARK: - Selection Helpers

    private var selectedItems: [ShelfStore.Item] {
        store.items.filter { selection.contains($0.id) }
    }

    private func toggleSelect(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) }
        else { selection.insert(id) }
    }

    private func bulkHelp(_ selectionText: String, _ allText: String) -> String {
        selection.isEmpty ? allText : selectionText
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - ShelfCell (v2: Drag-out + Kontextmenü)

private struct ShelfCell: View {
    let item: ShelfStore.Item
    let selected: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onOpenDefault: () -> Void
    let onOpenWith: () -> Void
    let onToggleSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                thumbnail
                if selected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .frame(width: 72, height: 72)
            .cornerRadius(8)

            Text(item.displayName)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 72)
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Vorschau") { onOpen() }
            Button("Öffnen") { onOpenDefault() }
            Button("Öffnen mit …") { onOpenWith() }
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Aus Ablage entfernen") { onRemove() }
        }
        // Drag-out: Datei zurück in Finder/ andere Apps ziehen.
        .onDrag {
            let provider = NSItemProvider(object: item.url as NSURL)
            return provider
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let thumb = item.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture(count: 2) { onOpen() }
        } else if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .onTapGesture(count: 2) { onOpen() }
        } else {
            Image(systemName: "doc")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - DropArea (NSView-Representable)

private struct DropArea: NSViewRepresentable {
    let onDrop: (NSPasteboard) -> Void
    let hoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> DropView {
        let v = DropView()
        v.onDrop = onDrop
        v.hoverChanged = hoverChanged
        return v
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onDrop = onDrop
        nsView.hoverChanged = hoverChanged
    }

    final class DropView: NSView {
        var onDrop: ((NSPasteboard) -> Void)?
        var hoverChanged: ((Bool) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            registerForDraggedTypes([.fileURL])
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            hoverChanged?(true)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            hoverChanged?(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            hoverChanged?(false)
            onDrop?(sender.draggingPasteboard)
            return true
        }
    }
}
