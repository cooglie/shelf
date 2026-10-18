//
//  AppDelegate.swift
//  Schelf
//
//  Verwaltet: Statusleisten-Item, schwebendes ShelfPanel, globalen Hotkey (⌘⇧D),
//  Lebenszyklus der App.
//

import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var panel: ShelfPanel!
    private var hotKeyId: UInt32 = 0
    private var hotKeyRef: EventHotKeyRef?
    private var store: ShelfStore!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ShelfStore()

        panel = ShelfPanel(store: store)
        panel.orderOut(nil) // versteckt starten

        setupStatusItem()
        registerHotkey()

        // Beim ersten Start Shelf einmal kurz anzeigen, damit der Nutzer ihn findet.
        togglePanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotkey()
    }

    // MARK: - Statusleisten-Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "tray.and.arrow.down",
                accessibilityDescription: "Schelf"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Schelf ein-/ausblenden (⌘⇧D)", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ablage leeren", action: #selector(clearShelf), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Schelf beenden", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func clearShelf() {
        store.clear()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.show()
        }
    }

    // MARK: - Globaler Hotkey (⌘⇧D)

    private func registerHotkey() {
        hotKeyId = 1
        let modifierMask: UInt32 =
            UInt32(cmdKey) | UInt32(shiftKey) // ⌘⇧
        let keyCode: UInt32 = UInt32(kVK_ANSI_D)

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData = userData else { return noErr }
                let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { me.togglePanel() }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            nil
        )

        RegisterEventHotKey(keyCode, modifierMask, EventHotKeyID(signature: OSType(0x5343484C), id: hotKeyId),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
