//
//  AppDelegate.swift
//  Schelf
//
//  Verwaltet: Statusleisten-Item, schwebendes ShelfPanel, globalen Hotkey,
//  Lebenszyklus der App.
//
//  v2: Konfigurierbarer Hotkey (aus AppSettings), Frame-Persistenz beim Schließen,
//      Sortierung/Persistenz-Wiederherstellung, Statusleisten-Menü erweitert.
//

import AppKit
import Carbon.HIToolbox
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var panel: ShelfPanel!
    private var hotKeyId: UInt32 = 0
    private var hotKeyRef: EventHotKeyRef?
    private var store: ShelfStore!
    private let settings = AppSettings.shared
    private var bag = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ShelfStore()

        panel = ShelfPanel(store: store)
        panel.orderOut(nil)

        setupStatusItem()
        registerHotkey()

        // Bei Sortierungs- oder Persistenzänderungen reagieren.
        settings.$panelOpacity
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panel.updateOpacity() }
            .store(in: &bag)

        // Beim ersten Start Shelf einmal kurz anzeigen, damit der Nutzer ihn findet.
        if settings.showAtLaunch {
            togglePanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotkey()
        panel.saveFrameToSettings()
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
        menu.addItem(withTitle: "Schelf ein-/ausblenden (\(settings.hotkey.label))",
                     action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Datei hinzufügen …", action: #selector(addFiles), keyEquivalent: "")
        menu.addItem(withTitle: "Ablage aktualisieren", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: "Ablage leeren", action: #selector(clearShelf), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Über Schelf", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Schelf beenden", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func addFiles() { store.addViaPicker() }
    @objc private func refresh() { store.refresh() }
    @objc private func clearShelf() { store.clear() }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Schelf",
            .applicationVersion: "2.0",
            .credits: "Schwebende Ablage für macOS."
        ])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.saveFrameToSettings()
            panel.orderOut(nil)
        } else {
            panel.show()
        }
    }

    // MARK: - Globaler Hotkey (konfigurierbar)

    func registerHotkey() {
        unregisterHotkey()

        hotKeyId = 1
        let cfg = settings.hotkey
        let modifierMask = cfg.modifiers
        let keyCode = cfg.keyCode

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

        RegisterEventHotKey(keyCode, modifierMask,
                            EventHotKeyID(signature: OSType(0x5343484C), id: hotKeyId),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
