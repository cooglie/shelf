//
//  ShelfPanel.swift
//  Schelf
//
//  Schwebendes, always-on-top Panel (über allen Spaces), transparente Titlebar,
//  draggable. Kapselt das SwiftUI-ShelfView als contentView.
//
//  v2: Frame-Persistenz, Opazität aus AppSettings, QuickLook über alle Items.
//

import AppKit
import SwiftUI

final class ShelfPanel: NSPanel {

    private let store: ShelfStore
    private let settings = AppSettings.shared

    init(store: ShelfStore) {
        self.store = store

        // Gespeicherten Frame laden oder Default rechts oben.
        let savedFrame = settings.panelFrame
        let frame = savedFrame ?? NSRect(x: 0, y: 0, width: 320, height: 420)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true              // immer im Vordergrund
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        updateOpacity()
        isReleasedWhenClosed = false
        hasShadow = true
        minSize = NSSize(width: 240, height: 240)
        maxSize = NSSize(width: 640, height: 1100)

        let hosting = NSHostingView(
            rootView: ShelfView(store: store)
                .environment(\.openQuickLook, OpenQuickLookAction { [weak self] url in
                    self?.presentQuickLook(for: url)
                })
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting

        // Frame nach Positionierung sichern.
        setFrameAutosaveName("SchelfPanel")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Opazität aus Settings anwenden (von ShelfView aus aufrufbar).
    func updateOpacity() {
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(settings.panelOpacity)
    }

    func show() {
        if frame.origin == .zero, settings.panelFrame == nil {
            if let screen = NSScreen.main {
                let f = NSRect(
                    x: screen.frame.maxX - frame.width - 24,
                    y: screen.frame.maxY - frame.height - 24,
                    width: frame.width,
                    height: frame.height
                )
                setFrame(f, display: true)
            }
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    func saveFrameToSettings() {
        settings.panelFrame = self.frame
    }

    // MARK: - QuickLook

    private var quickLookController: QuickLookWindowController?

    private func presentQuickLook(for url: URL) {
        if quickLookController == nil {
            quickLookController = QuickLookWindowController()
        }
        // Alle Items in Reihenfolge übergeben, das gewählte zuerst.
        var urls = store.sortedItems().map { $0.url }
        if let idx = urls.firstIndex(of: url) {
            urls.insert(urls.remove(at: idx), at: 0)
        }
        quickLookController?.show(urls: urls.isEmpty ? [url] : urls)
    }
}
