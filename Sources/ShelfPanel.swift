//
//  ShelfPanel.swift
//  Schelf
//
//  Schwebendes, always-on-top Panel (über allen Spaces), transparente Titlebar,
//  draggable. Kapselt das SwiftUI-ShelfView als contentView.
//

import AppKit
import SwiftUI

final class ShelfPanel: NSPanel {

    private let store: ShelfStore

    init(store: ShelfStore) {
        self.store = store
        let frame = NSRect(x: 0, y: 0, width: 320, height: 420)

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
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        isReleasedWhenClosed = false
        hasShadow = true
        minSize = NSSize(width: 240, height: 200)
        maxSize = NSSize(width: 520, height: 900)

        // SwiftUI-View einbetten.
        let hosting = NSHostingView(
            rootView: ShelfView(store: store)
                .environment(\.openQuickLook, OpenQuickLookAction { [weak self] url in
                    self?.presentQuickLook(for: url)
                })
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Zeigt das Panel an einer sinnvollen Position (rechts oben) falls noch nie positioniert.
    func show() {
        if frame.origin == .zero {
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

    // MARK: - QuickLook

    private var quickLookController: QuickLookWindowController?

    private func presentQuickLook(for url: URL) {
        if quickLookController == nil {
            quickLookController = QuickLookWindowController()
        }
        quickLookController?.show(urls: [url])
    }
}
