//
//  ShakeDetector.swift
//  Schelf
//
//  Globaler Monitor für schnelle Maus-Richtungswechsel ("Shake").
//  Erkennt mehrfaches, schnelles Hin-und-Her (horizontal ODER vertikal)
//  innerhalb eines kurzen Zeitfensters und feuert onShake.
//

import AppKit

final class ShakeDetector {

    /// Wird beim erkannten Shake (im main-Thread) aufgerufen.
    var onShake: (() -> Void)?

    private var monitor: Any?
    private var enabled = false

    // Erkennungs-Parameter
    private let minAmplitude: CGFloat = 18          // Mindest-Auslenkung pro Achse (px)
    private let maxInterval: TimeInterval = 0.35    // max. Zeit zwischen zwei Richtungswechseln
    private let reversalsNeeded = 3                 // Anzahl Richtungswechsel für einen Shake

    // Zustand
    private var lastX: CGFloat?
    private var lastY: CGFloat?
    private var lastDirX: Int = 0       // -1 / 0 / 1
    private var lastDirY: Int = 0
    private var lastReversalTime: Date?
    private var reversalCount = 0
    private var lastFireTime: Date?

    func start() {
        guard !enabled else { return }
        enabled = true
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        guard let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
        enabled = false
        reset()
    }

    private func reset() {
        lastX = nil; lastY = nil
        lastDirX = 0; lastDirY = 0
        lastReversalTime = nil
        reversalCount = 0
    }

    private func handle(_ event: NSEvent) {
        // Nur auswerten, wenn das Schelf-Panel gerade NICHT sichtbar ist
        // (Shake öffnet; ein weiterer Shake schließt nicht versehentlich).
        // Die Sichtbarkeitsprüfung übernimmt der Aufrufer via onShake-Closure.
        let p = NSEvent.mouseLocation   // Bildschirmkoordinaten (global)
        let now = Date()

        guard let lx = lastX, let ly = lastY else {
            lastX = p.x; lastY = p.y
            return
        }

        let dx = p.x - lx
        let dy = p.y - ly
        lastX = p.x; lastY = p.y

        // Dominante Achse bestimmen
        let dirX: Int = abs(dx) > 2 ? (dx > 0 ? 1 : -1) : 0
        let dirY: Int = abs(dy) > 2 ? (dy > 0 ? 1 : -1) : 0

        var reversal = false

        if dirX != 0 && dirX != lastDirX && lastDirX != 0 && abs(dx) >= minAmplitude {
            reversal = true
            lastDirX = dirX
            lastDirY = 0
        } else if dirX != 0 {
            lastDirX = dirX
        }

        if !reversal, dirY != 0 && dirY != lastDirY && lastDirY != 0 && abs(dy) >= minAmplitude {
            reversal = true
            lastDirY = dirY
            lastDirX = 0
        } else if dirY != 0 {
            lastDirY = dirY
        }

        guard reversal else { return }

        // Zeitfenster prüfen
        if let t = lastReversalTime, now.timeIntervalSince(t) > maxInterval {
            reversalCount = 0
        }
        reversalCount += 1
        lastReversalTime = now

        if reversalCount >= reversalsNeeded {
            // Entprellen: max. ein Shake pro Sekunde.
            if let last = lastFireTime, now.timeIntervalSince(last) < 1.0 { return }
            lastFireTime = now
            reversalCount = 0
            DispatchQueue.main.async { [weak self] in self?.onShake?() }
        }
    }
}
