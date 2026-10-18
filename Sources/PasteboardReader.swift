//
//  PasteboardReader.swift
//  Schelf
//
//  Liest Datei-URLs aus einem NSPasteboard (Finder-Drag, Kopieren).
//

import AppKit

final class PasteboardReader {
    func fileURLs(from pb: NSPasteboard) -> [URL]? {
        let classes: [AnyClass] = [NSURL.self, NSPasteboardItem.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

        guard let items = pb.readObjects(forClasses: classes, options: options) as? [URL],
              !items.isEmpty else {
            return nil
        }
        return items
    }
}
