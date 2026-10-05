import Foundation

public struct BackupManifest: Codable, Sendable {
    public let created: Date
    public let hashes: [String: String]
}
public enum SaveBackup {
    // Never overwrite source or existing destination. User must pause the game before invoking.
    public static func copyAndVerify(source: URL, destination: URL, includeHidden: Bool = false) throws
        -> BackupManifest
    {
        guard !FileManager.default.fileExists(atPath: destination.path), !FileSafety.contained(destination, in: source),
            !FileSafety.contained(source, in: destination)
        else { throw VNError.message("备份/恢复必须选择全新的独立目录") }
        guard (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw VNError.message("源目录不存在")
        }
        let listing = try FileSafety.walk(source, maximum: 10000, includeHidden: includeHidden)
        guard !listing.limited else { throw VNError.message("超过备份文件上限") }
        var hashes: [String: String] = [:]
        var total = 0
        // No symlinks copied, and bounded reads. A partial destination remains clearly incomplete on error.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for url in listing.files {
            try Task.checkCancellation()
            let base = source.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            guard parts.starts(with: base) else { throw VNError.message("源路径越界") }
            let relative = parts.dropFirst(base.count).joined(separator: "/")
            let data = try FileSafety.read(url, limit: 128 * 1024 * 1024)
            total += data.count
            guard total <= 1024 * 1024 * 1024 else { throw VNError.message("超过 1 GiB 备份上限；保留不完整副本供检查") }
            let target = destination.appendingPathComponent(relative)
            guard FileSafety.contained(target, in: destination) else { throw VNError.message("目标越界") }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .withoutOverwriting)
            let hash = FileSafety.fingerprint(data)
            guard FileSafety.fingerprint(try FileSafety.read(target, limit: 128 * 1024 * 1024)) == hash,
                FileSafety.fingerprint(try FileSafety.read(url, limit: 128 * 1024 * 1024)) == hash
            else { throw VNError.message("源文件变化或副本校验失败；副本未验收") }
            hashes[relative] = hash
        }
        let after = try FileSafety.walk(source, maximum: 10000, includeHidden: includeHidden)
        guard !after.limited,
            Set(after.files.map { $0.resolvingSymlinksInPath().path })
                == Set(listing.files.map { $0.resolvingSymlinksInPath().path })
        else { throw VNError.message("备份期间源目录发生变化，副本未验收") }
        try verifyContents(source: source, destination: destination, hashes: hashes)
        return BackupManifest(created: Date(), hashes: hashes)
    }

    static func verifyContents(source: URL, destination: URL, hashes: [String: String]) throws {
        // Recheck early files after the last copy; a matching path list alone cannot detect writes.
        for (relative, hash) in hashes {
            try Task.checkCancellation()
            guard
                FileSafety.fingerprint(
                    try FileSafety.read(source.appendingPathComponent(relative), limit: 128 * 1024 * 1024)) == hash,
                FileSafety.fingerprint(
                    try FileSafety.read(destination.appendingPathComponent(relative), limit: 128 * 1024 * 1024)) == hash
            else {
                throw VNError.message("备份期间文件内容发生变化，副本未验收")
            }
        }
    }
}
