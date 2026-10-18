//
//  ShelfView.swift
//  Schelf
//
//  Hauptansicht der schwebenden Ablage: Drop-Zone, Thumbnail-Grid, Toolbar
//  (Kopieren / Verschieben / Leeren), Einzeleintrag-Kontextmenü, Fehleranzeige.
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
    @Environment(\.openQuickLook) var openQuickLook
    @State private var dropHover = false
    @State private var selection: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(background)
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
            Button { store.copyAll() } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .help("Alle gesammelten Dateien kopieren")
            .disabled(store.items.isEmpty)
            Button { store.moveAll() } label: {
                Label("Verschieben", systemImage: "arrow.right.doc")
                    .labelStyle(.iconOnly)
            }
            .help("Alle gesammelten Dateien verschieben")
            .disabled(store.items.isEmpty)
            Button { store.clear() } label: {
                Label("Leeren", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Ablage leeren (Dateien werden nicht gelöscht)")
            .disabled(store.items.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content / Drop

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.items) { item in
                        ShelfCell(item: item,
                                  selected: selection.contains(item.id),
                                  onOpen: { openQuickLook(item.url) },
                                  onRemove: { store.remove(item) })
                            .gesture(TapGesture().onEnded {
                                if selection.contains(item.id) { selection.remove(item.id) }
                                else { selection.insert(item.id) }
                            })
                    }
                }
                .padding(10)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Dateien hierher ziehen")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Sammeln, kopieren oder verschieben —\nmit ⌘⇧D jederzeit einblenden.")
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
            Text("\(store.items.count) \(store.items.count == 1 ? "Objekt" : "Objekte")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text("⌘⇧D")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - ShelfCell

private struct ShelfCell: View {
    let item: ShelfStore.Item
    let selected: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void

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
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Aus Ablage entfernen") { onRemove() }
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
