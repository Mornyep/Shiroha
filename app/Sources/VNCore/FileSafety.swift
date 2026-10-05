import CryptoKit
import Foundation

public enum FileSafety {
    public static func contained(_ url: URL, in root: URL) -> Bool {
        let r = root.standardizedFileURL.resolvingSymlinksInPath().path
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        return p == r || p.hasPrefix(r + "/")
    }
    public static func read(_ url: URL, limit: Int = 32 * 1024 * 1024) throws -> Data {
        let attr = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attr.isRegularFile == true, (attr.fileSize ?? Int.max) <= limit else {
            throw VNError.message("文件不是普通文件或超过读取上限：\(url.lastPathComponent)")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw VNError.message("读取达到安全上限") }
        return data
    }
    public static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func walk(_ root: URL, maximum: Int = 4000, includeHidden: Bool = false) throws -> (
        files: [URL], limited: Bool
    ) {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        var enumerationError: Error?
        guard
            let iterator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: includeHidden ? [] : [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                })
        else { throw VNError.message("无法读取目录") }
        var files: [URL] = []
        var visited = 0
        for case let url as URL in iterator {
            try Task.checkCancellation()
            visited += 1
            if visited > maximum { return (files, true) }
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true || !contained(url, in: root) {
                iterator.skipDescendants()
                continue
            }
            if values.isRegularFile == true { files.append(url) }
        }
        if let enumerationError { throw enumerationError }
        return (files, false)
    }
}
