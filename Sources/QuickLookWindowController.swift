//
//  QuickLookWindowController.swift
//  Schelf
//
//  Eigenes QuickLook-Fenster via QLPreviewView.
//  v2: Navigation durch mehrere Items (← / →), Indexanzeige im Titel.
//

import AppKit
import Quartz

final class QuickLookWindowController: NSWindowController, NSWindowDelegate {

    private var previewView: QLPreviewView!
    private var urls: [URL] = []
    private var index: Int = 0

    convenience init() {
        let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Vorschau"
        window.titlebarAppearsTransparent = true
        self.init(window: window)

        previewView = QLPreviewView(frame: .zero, style: .normal)!
        previewView.autoresizingMask = [.width, .height]
        window.contentView = previewView
        window.delegate = self
    }

    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.index = 0
        showCurrent()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private func showCurrent() {
        guard urls.indices.contains(index) else { return }
        previewView.previewItem = urls[index] as QLPreviewItem
        updateTitle()
    }

    private func updateTitle() {
        if urls.count > 1 {
            window?.title = "Vorschau — \(index + 1) / \(urls.count)"
        } else {
            window?.title = "Vorschau"
        }
    }

    private func navigate(_ delta: Int) {
        let next = index + delta
        guard urls.indices.contains(next) else { return }
        index = next
        showCurrent()
    }

    // MARK: Tastatur

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case NSEvent.SpecialKey.leftArrow:  navigate(-1)
        case NSEvent.SpecialKey.rightArrow: navigate(1)
        default: super.keyDown(with: event)
        }
    }

    func windowDidResize(_ notification: Notification) { /* QLPreviewView handled auto */ }
}
