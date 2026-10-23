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
    private let shakeDetector = ShakeDetector()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ShelfStore()

        panel = ShelfPanel(store: store)
        panel.orderOut(nil)

        setupStatusItem()
        registerHotkey()
        setupShakeDetector()

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
        shakeDetector.stop()
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

        statusItem.menu = makeMenu()
    }

    /// Baut das Statusleisten-Menü (lokalisiert) neu auf.
    /// Wird auch beim Sprachwechsel aufgerufen.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.string(.menuToggle, settings.hotkey.label),
                     action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string(.menuAddFile), action: #selector(addFiles), keyEquivalent: "")
        menu.addItem(withTitle: L10n.string(.menuRefresh), action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: L10n.string(.menuClear), action: #selector(clearShelf), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string(.menuAbout), action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string(.menuQuit), action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func addFiles() { store.addViaPicker() }
    @objc private func refresh() { store.refresh() }
    @objc private func clearShelf() { store.clear() }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: L10n.string(.appName),
            .applicationVersion: "2.1",
            .credits: L10n.string(.aboutCredits)
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

    // MARK: - Shake-to-open

    /// Schütteln der Maus öffnet das Panel (nur wenn es gerade versteckt ist).
    /// Nur aktiv, wenn in den Einstellungen `shakeToOpen` eingeschaltet ist.
    private func setupShakeDetector() {
        shakeDetector.onShake = { [weak self] in
            guard let self = self, self.panel.isVisible == false else { return }
            self.panel.show()
        }
        if settings.shakeToOpen {
            shakeDetector.start()
        }
        // Live auf Änderungen reagieren: Monitor starten/stoppen.
        NotificationCenter.default.addObserver(
            self, selector: #selector(shakeToOpenChanged(_:)),
            name: AppSettings.shakeToOpenChanged, object: nil)

        // Bei Sprachwechsel: Menü und About-Texte neu aufbauen.
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageChanged),
            name: L10n.languageChanged, object: nil)
    }

    @objc private func languageChanged() {
        // Statusleisten-Menü lokalisiert neu aufbauen.
        statusItem.menu = makeMenu()
    }

    @objc private func shakeToOpenChanged(_ note: Notification) {
        let enabled = (note.userInfo?["enabled"] as? Bool) ?? false
        if enabled {
            shakeDetector.start()
        } else {
            shakeDetector.stop()
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
