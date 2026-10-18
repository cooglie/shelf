//
//  QuickLookWindowController.swift
//  Schelf
//
//  Eigenes QuickLook-Fenster via QLPreviewView (funktioniert auf macOS 11+ ohne
//  das systemweite QuickLook-UI hijacken zu müssen).
//

import AppKit
import Quartz

final class QuickLookWindowController: NSWindowController {

    private var previewView: QLPreviewView!

    convenience init() {
        let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Vorschau"
        self.init(window: window)

        previewView = QLPreviewView(frame: .zero, style: .normal)!
        previewView.autoresizingMask = [.width, .height]
        window.contentView = previewView
    }

    func show(urls: [URL]) {
        guard let first = urls.first else { return }
        previewView.previewItem = first as QLPreviewItem
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }
}
