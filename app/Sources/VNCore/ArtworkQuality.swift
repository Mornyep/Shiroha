import Foundation
import ImageIO

public struct ArtworkSize: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var portrait: Bool { height > width && Double(width) / Double(height) >= 0.45 }
    public var pixels: Int { width * height }
    public var label: String { "\(width) × \(height)" }
}
public enum ArtworkQuality {
    public static func size(_ path: String?) -> ArtworkSize? {
        guard let path, let data = try? FileSafety.read(URL(fileURLWithPath: path), limit: 20 * 1024 * 1024),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0, width <= 16000,
            height <= 16000
        else { return nil }
        return ArtworkSize(width: width, height: height)
    }
    public static func improves(_ new: String, over old: String?) -> Bool {
        guard let n = size(new) else { return false }
        guard let o = size(old) else { return true }
        if n.portrait != o.portrait { return n.portrait }
        return n.pixels > o.pixels
    }
    public static func steamPosters(header: URL) -> [URL] {
        guard MetadataService.allowedImageURL(header) else { return [] }
        let base = header.deletingLastPathComponent()
        let localized = header.lastPathComponent.contains("_schinese")
        let names =
            localized
            ? [
                "library_600x900_2x_schinese.jpg", "library_600x900_schinese_2x.jpg", "library_600x900_schinese.jpg",
                "library_600x900_2x.jpg", "library_600x900.jpg",
            ] : ["library_600x900_2x.jpg", "library_600x900.jpg"]
        return names.map { base.appendingPathComponent($0) }
    }
}
