//
//  main.swift
//  Schelf — Schwebende Ablage für macOS.
//
//  Einstiegspunkt via @main (mit -parse-as-library werden keine Top-Level-Ausdrücke
//  akzeptiert). NSApplication wird manuell konfiguriert (Panel statt Fenster,
//  Statusitem, Carbon-Hotkey).
//

import AppKit

@main
struct SchelfMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // kein Dock-Icon
        app.run()
    }
}
