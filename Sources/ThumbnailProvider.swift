//
//  ThumbnailProvider.swift
//  Schelf
//
//  Erzeugt Thumbnails für Bilder (direkt via NSImage) und liefert sonst nil
//  (die UI fällt auf das Datei-Icon zurück). QuickLook-Thumbnail-API (macOS 10.15+)
//  wird für Non-Image-Dateien genutzt, sofern verfügbar.
//

import AppKit
import Foundation
import QuickLookThumbnailing

enum ThumbnailProvider {

    /// Liefert ein Thumbnail für die Datei, max. `maxPixel` Pixel auf der langen Seite.
    static func thumbnail(for url: URL, maxPixel: Int) -> NSImage? {
        // Bilder direkt dekodieren — schärfster und schnellster Pfad.
        if isImage(url) {
            return downsampledImage(url: url, maxPixel: maxPixel)
        }

        // Fallback: QLThumbnailGenerator (PDFs, Text, Office, etc.).
        return qlThumbnail(url: url, maxPixel: maxPixel)
    }

    private static func isImage(_ url: URL) -> Bool {
        let utType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        return utType?.conforms(to: .image) ?? false
    }

    private static func downsampledImage(url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func qlThumbnail(url: URL, maxPixel: Int) -> NSImage? {
        // QuickLookThumbnailing ist asynchron — wir versuchen einen synchronen
        // Best-Effort mit kurzer Semaphor, fallen sonst auf nil zurück.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maxPixel, height: maxPixel),
            scale: scale,
            representationTypes: .all
        )

        let sem = DispatchSemaphore(value: 0)
        var result: NSImage?

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
            if let rep = rep {
                let sz = NSSize(width: rep.contentRect.width, height: rep.contentRect.height)
                result = NSImage(cgImage: rep.cgImage, size: sz)
            }
            _ = error
            sem.signal()
        }

        _ = sem.wait(timeout: .now() + 1.5)
        return result
    }
}
