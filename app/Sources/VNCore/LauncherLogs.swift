import Darwin
import Foundation

public struct LauncherLogPolicy: Sendable {
    public var days: Int
    public var totalBytes: Int64
    public var activeBytes: Int64
    public init(days: Int = 14, totalBytes: Int64 = 64 * 1024 * 1024, activeBytes: Int64 = 4 * 1024 * 1024) {
        self.days = max(1, days)
        self.totalBytes = max(1024, totalBytes)
        self.activeBytes = max(1024, activeBytes)
    }
}
public struct LauncherLog: Identifiable, Sendable {
    public var id: String { url.lastPathComponent }
    public let url: URL
    public let bytes: Int64
    public let date: Date
    public let active: Bool
}
public enum LauncherLogs {
    public static func owns(_ url: URL) -> Bool {
        url.pathExtension == "log" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }
    private static func directorySafe(_ root: URL) -> Bool {
        (try? root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])).map {
            $0.isDirectory == true && $0.isSymbolicLink != true
        } ?? false
    }
    private static func descriptor(_ url: URL, flags: Int32) throws -> Int32 {
        let fd = open(url.path, flags | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw VNError.message("无法访问启动日志：\(url.lastPathComponent)") }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            close(fd)
            throw VNError.message("启动日志不是普通文件")
        }
        return fd
    }
    public static func create(_ url: URL, header: String) throws -> FileHandle {
        guard owns(url) else { throw VNError.message("无效会话日志名") }
        let root = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard directorySafe(root) else { throw VNError.message("日志目录不可用或是链接") }
        let fd = try descriptor(url, flags: O_WRONLY | O_CREAT | O_EXCL | O_APPEND)
        // The inherited open description keeps this lock while any game descendant still owns stdout.
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
            close(fd)
            throw VNError.message("无法保护活跃日志")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(header.utf8))
            return handle
        } catch {
            try? handle.close()
            throw error
        }
    }
    public static func list(_ root: URL, protected: Set<String> = []) -> [LauncherLog] {
        guard directorySafe(root) else { return [] }
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                ])) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(2000).compactMap { url in
            guard owns(url),
                let values = try? url.resourceValues(forKeys: [
                    .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                ]), values.isSymbolicLink != true, values.isRegularFile == true,
                let fd = try? descriptor(url, flags: O_RDONLY)
            else { return nil }
            let locked = flock(fd, LOCK_EX | LOCK_NB) != 0
            close(fd)
            return LauncherLog(
                url: url, bytes: Int64(values.fileSize ?? 0), date: values.contentModificationDate ?? .distantPast,
                active: locked || protected.contains(url.path))
        }.sorted { $0.date > $1.date }
    }
    /// O_APPEND prevents inherited writers from leaving sparse holes after truncation. No pipe is installed.
    public static func boundActive(_ handle: FileHandle, maximum: Int64) throws -> Bool {
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else { throw VNError.message("无法检查日志大小") }
        guard info.st_size > max(1024, maximum) else { return false }
        guard ftruncate(handle.fileDescriptor, 0) == 0 else { throw VNError.message("无法限制日志大小") }
        try handle.write(contentsOf: Data("[VNLauncher：已达到活跃日志上限，较早输出已截短；仅启动器存活时检查。]\n".utf8))
        return true
    }
    @discardableResult public static func clean(
        _ root: URL, policy: LauncherLogPolicy, protected: Set<String> = [], allInactive: Bool = false,
        now: Date = Date(), recovery: URL? = nil
    ) throws -> [URL] {
        let entries = list(root, protected: protected)
        var total = entries.reduce(Int64(0)) { $0 + $1.bytes }
        var moved: [URL] = []
        for entry in entries.reversed() where !entry.active {
            guard
                allInactive || now.timeIntervalSince(entry.date) > Double(policy.days) * 86400
                    || total > policy.totalBytes
            else { continue }
            let fd = try descriptor(entry.url, flags: O_RDONLY)
            defer { close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { continue }
            // Recheck inode before moving: a changed file must never be selected by stale enumeration.
            var opened = stat()
            var current = stat()
            guard fstat(fd, &opened) == 0, lstat(entry.url.path, &current) == 0, opened.st_ino == current.st_ino,
                opened.st_dev == current.st_dev
            else { continue }
            if let recovery {
                try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
                guard directorySafe(recovery) else { throw VNError.message("恢复目录不可用") }
                try FileManager.default.moveItem(
                    at: entry.url, to: recovery.appendingPathComponent(entry.url.lastPathComponent))
            } else {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: &trashed)
            }
            total -= entry.bytes
            moved.append(entry.url)
        }
        return moved
    }
}
