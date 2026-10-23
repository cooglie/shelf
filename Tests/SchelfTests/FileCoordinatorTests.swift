//
//  FileCoordinatorTests.swift
//  Schelf
//
//  Eigenständiger Test-Runner (kein XCTest/Xcode-Projekt nötig).
//  Wird via `swift test` (siehe run_tests.sh) gegen FileCoordinator.swift gebaut.
//  Testbar ohne Fenster/Pasteboard — genau die Trennung, die Prio 2 fordert.
//

import Foundation

private var failures: Int = 0
private var passes: Int = 0

func assert(_ condition: Bool, _ msg: String,
            file: String = #file, line: Int = #line) {
    if condition { passes += 1 }
    else {
        failures += 1
        print("  ✗ FAIL: \(msg)  (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String,
                               file: String = #file, line: Int = #line) {
    assert(a == b, "\(msg) — expected \(b), got \(a)", file: file, line: line)
}

private func section(_ name: String) { print("\n— \(name)") }

// MARK: - Tests

func testUniqueName() {
    section("uniqueName: Konflikt, Extension, Zähler")
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("schelf-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Storage-Dir UND ein separates Quell-Verzeichnis (sonst sind Quell-
    // dateien bereits „inside storage" und uniqueName schlägt sofort an).
    let storage = tmp.appendingPathComponent("storage", isDirectory: true)
    try? FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    let ext = tmp.appendingPathComponent("ext", isDirectory: true)
    try? FileManager.default.createDirectory(at: ext, withIntermediateDirectories: true)
    let coord = FileCoordinator(storageDir: storage)

    // 1. No conflict → original name.
    let src1 = ext.appendingPathComponent("photo.jpg")
    try? "x".write(to: src1, atomically: true, encoding: .utf8)
    let u1 = coord.uniqueName(for: src1, in: storage)
    assertEqual(u1.lastPathComponent, "photo.jpg", "no conflict keeps name")

    // 2. Create photo.jpg in storage → next should be "photo 2.jpg".
    let existing = storage.appendingPathComponent("photo.jpg")
    try? "y".write(to: existing, atomically: true, encoding: .utf8)
    let u2 = coord.uniqueName(for: src1, in: storage)
    assertEqual(u2.lastPathComponent, "photo 2.jpg", "first conflict → 2")

    // 3. Create "photo 2.jpg" → next should be "photo 3.jpg".
    try? "z".write(to: storage.appendingPathComponent("photo 2.jpg"), atomically: true, encoding: .utf8)
    let u3 = coord.uniqueName(for: src1, in: storage)
    assertEqual(u3.lastPathComponent, "photo 3.jpg", "second conflict → 3")

    // 4. No extension.
    let noext = ext.appendingPathComponent("README")
    try? "r".write(to: noext, atomically: true, encoding: .utf8)
    // Beide belegt → nächster freier Name ist "README 3".
    try? "r1".write(to: storage.appendingPathComponent("README"), atomically: true, encoding: .utf8)
    try? "r2".write(to: storage.appendingPathComponent("README 2"), atomically: true, encoding: .utf8)
    let u4 = coord.uniqueName(for: noext, in: storage)
    assertEqual(u4.lastPathComponent, "README 3", "no extension conflict")
}

func testSafeMoveCopy() throws {
    section("safeMove / safeCopy: Quelle fehlt, Ziel existiert")
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("schelf-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let coord = FileCoordinator(storageDir: tmp)
    let src = tmp.appendingPathComponent("a.txt")
    try? "hello".write(to: src, atomically: true, encoding: .utf8)
    let dst = tmp.appendingPathComponent("b.txt")

    // copy succeeds, source stays.
    try? coord.safeCopy(from: src, to: dst)
    assert(FileManager.default.fileExists(atPath: src.path), "copy keeps source")
    assert(FileManager.default.fileExists(atPath: dst.path), "copy creates dest")

    // copy again → destinationExists.
    var threwDest = false
    do { try coord.safeCopy(from: src, to: dst) }
    catch FileOpError.destinationExists { threwDest = true }
    catch {}
    assert(threwDest, "copy over existing → destinationExists")

    // move: source gone, dest present.
    try? coord.safeMove(from: src, to: tmp.appendingPathComponent("c.txt"))
    assert(!FileManager.default.fileExists(atPath: src.path), "move removes source")

    // missing source.
    var threwMissing = false
    do { try coord.safeMove(from: tmp.appendingPathComponent("nope.txt"),
                            to: tmp.appendingPathComponent("d.txt")) }
    catch FileOpError.sourceMissing { threwMissing = true }
    catch {}
    assert(threwMissing, "missing source → sourceMissing")
}

func testIngest() throws {
    section("ingest: Verschiebung + Dedupe im Storage")
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("schelf-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Storage getrennt vom Quell-Verzeichnis (sonst ist die Quelle bereits
    // „inside storage" und ingest verschiebt nicht).
    let storage = tmp.appendingPathComponent("storage", isDirectory: true)
    try? FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    let src = tmp.appendingPathComponent("src", isDirectory: true)
    try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    let coord = FileCoordinator(storageDir: storage)

    // Externe Datei → wird ins Storage verschoben.
    let ext = src.appendingPathComponent("ext.txt")
    try? "data".write(to: ext, atomically: true, encoding: .utf8)
    let stored = try coord.ingest(url: ext)
    assert(!FileManager.default.fileExists(atPath: ext.path), "ingest moves source out")
    assert(FileManager.default.fileExists(atPath: stored.path), "ingest places in storage")
    assert(coord.isInsideStorage(stored), "stored path is inside storage")

    // Zweite gleichnamige Datei → unique.
    let ext2 = src.appendingPathComponent("ext.txt")
    try? "data2".write(to: ext2, atomically: true, encoding: .utf8)
    let stored2 = try coord.ingest(url: ext2)
    assert(stored2.lastPathComponent == "ext 2.txt", "second ingest uniquified")
    assert(stored != stored2, "different stored paths")

    // Bereits im Storage → unverändert.
    let r3 = try coord.ingest(url: stored)
    assertEqual(r3.path, stored.path, "in-storage returned unchanged")
}

func testBatch() {
    section("performBatch: 8/10 Erfolg, Fehlerisolierung, kein Abbruch")
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("schelf-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let coord = FileCoordinator(storageDir: tmp)
    let dest = tmp.appendingPathComponent("dest", isDirectory: true)
    try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

    // 10 Quellen; 2 davon löschen wir vorab → sourceMissing.
    var sources: [URL] = []
    for i in 1...10 {
        let f = tmp.appendingPathComponent("f\(i).txt")
        try? "x\(i)".write(to: f, atomically: true, encoding: .utf8)
        sources.append(f)
    }
    // Zwei entfernen, um Fehler zu provozieren.
    try? FileManager.default.removeItem(at: sources[2])
    try? FileManager.default.removeItem(at: sources[7])

    let result = coord.performBatch(sources: sources, to: dest, copy: true)

    assertEqual(result.totalCount, 10, "all 10 attempted")
    assertEqual(result.successCount, 8, "8 succeeded")
    assertEqual(result.failureCount, 2, "2 failed")
    assert(result.failed.allSatisfy { $0.error == .sourceMissing },
           "failures are sourceMissing")
    // Erfolgreiche Dateien liegen im Ziel.
    for o in result.succeeded {
        assert(FileManager.default.fileExists(atPath: o.destination.path),
               "succeeded file present at dest")
    }
    // Zusammenfassung enthält "8" und "failed".
    let s = result.summary()
    assert(s.contains("8") && s.lowercased().contains("failed"),
           "summary reports counts: \(s)")
}

func testSymlink() {
    section("Symlink: wird als Link kopiert, nicht dereferenziert")
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("schelf-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let coord = FileCoordinator(storageDir: tmp)
    let target = tmp.appendingPathComponent("target.txt")
    try? "real".write(to: target, atomically: true, encoding: .utf8)
    let link = tmp.appendingPathComponent("link.txt")
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let dest = tmp.appendingPathComponent("copied-link.txt")
    do {
        try coord.safeCopy(from: link, to: dest)
        // Kopiertes sollte ein Symlink sein.
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let type = attrs[.type] as? FileAttributeType
        assert(type == .typeSymbolicLink, "symlink copied as symlink, not dereferenced")
    } catch {
        assert(false, "symlink copy threw: \(error)")
    }
}

func testRecursiveSize() {
    section("recursiveSize: Verzeichnis-Summe über reguläre Dateien")
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("schelf-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let coord = FileCoordinator(storageDir: tmp)
    let sub = tmp.appendingPathComponent("sub", isDirectory: true)
    try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try? "aaaa".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8) // 4
    try? "bb".write(to: sub.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)   // 2
    let size = coord.recursiveSize(of: tmp)
    assertEqual(size, 6, "recursive size sums nested files")
}

func testTrash() {
    section("trash: nur Storage-interne Dateien werden gelöscht")
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("schelf-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Storage getrennt vom Quell-Verzeichnis.
    let storage = tmp.appendingPathComponent("storage", isDirectory: true)
    try? FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    let src = tmp.appendingPathComponent("src", isDirectory: true)
    try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    let coord = FileCoordinator(storageDir: storage)

    // Externe Datei → trash ignoriert (löscht nicht).
    let ext = src.appendingPathComponent("ext.txt")
    try? "x".write(to: ext, atomically: true, encoding: .utf8)
    coord.trash(url: ext)
    assert(FileManager.default.fileExists(atPath: ext.path),
           "trash leaves external files untouched")

    // Storage-interne Datei → wird entfernt (via trashItem).
    let inside = storage.appendingPathComponent("inside.txt")
    try? "y".write(to: inside, atomically: true, encoding: .utf8)
    coord.trash(url: inside)
    assert(!FileManager.default.fileExists(atPath: inside.path),
           "trash removes storage-internal file")
}

// MARK: - Runner

@main
struct TestRunner {
    static func main() throws {
        print("=== Schelf FileCoordinator Tests ===")
        testUniqueName()
        try testSafeMoveCopy()
        try testIngest()
        testBatch()
        testSymlink()
        testRecursiveSize()
        testTrash()
        print("\n=== Result: \(passes) passed, \(failures) failed ===")
        if failures > 0 { exit(1) }
    }
}
