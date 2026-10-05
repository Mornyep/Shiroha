import Darwin
import Foundation

public struct SaveSnapshot: Sendable {
    public let observation: SaveObservation
    public let watchedPaths: [String]
}
public enum SaveSnapshotReader {
    /// No writes, no executable deserialization, no symlink traversal. Every child
    /// is opened relative to its already-open directory with O_NOFOLLOW.
    public static func scan(directory: URL, mahoyo: Bool) throws -> SaveSnapshot {
        // Foundation standardization rewrites an existing /private/tmp to the /tmp symlink.
        // Preserve the canonical path supplied by the picker instead.
        let root = directory
        guard !root.pathComponents.contains(".."), !root.pathComponents.contains(".") else {
            throw VNError.message("请选择绝对存档目录。")
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY)
        for component in root.pathComponents.dropFirst() {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            close(fd)
            fd = next
            guard fd >= 0 else { throw VNError.message("存档目录不可访问、包含链接或已移动，请重新关联。") }
        }
        guard fd >= 0 else { throw VNError.message("存档目录不可访问或已移动，请重新关联。") }
        defer { close(fd) }
        var slots: [SaveSlotObservation] = []
        var paths = [root.path]
        var count = 0
        var total = 0
        func visit(_ directoryFD: Int32, relative: String) throws {
            guard let stream = fdopendir(dup(directoryFD)) else { throw VNError.message("无法枚举存档目录。") }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                try Task.checkCancellation()
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                count += 1
                guard count <= 128 else { throw VNError.message("目录超过 128 个条目，请选择更具体的存档文件夹。") }
                var info = stat()
                guard fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                    throw VNError.message("文件正在变化，请稍后刷新。")
                }
                if (info.st_mode & S_IFMT) == S_IFLNK { continue }
                let key = relative.isEmpty ? name : relative + "/" + name
                let child = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                guard child >= 0 else { throw VNError.message("存档文件暂不可读，请稍后刷新。") }
                defer { close(child) }
                guard fstat(child, &info) == 0 else { throw VNError.message("无法检查文件。") }
                if (info.st_mode & S_IFMT) == S_IFDIR {
                    paths.append(root.appendingPathComponent(key).path)
                    try visit(child, relative: key)
                    continue
                }
                guard (info.st_mode & S_IFMT) == S_IFREG else { continue }
                if name.hasPrefix(".") || name == "steam_autocloud.vdf" { continue }
                if mahoyo && !(name.hasPrefix("WitchOnTheHolyNight") && name.hasSuffix(".sud")) { continue }
                guard info.st_size <= 8 * 1024 * 1024, total + Int(info.st_size) <= 32 * 1024 * 1024 else {
                    throw VNError.message("存档文件超出读取范围（单个 8 MB／合计 32 MB）。")
                }
                let handle = FileHandle(fileDescriptor: child, closeOnDealloc: false)
                let data = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
                var after = stat()
                guard fstat(child, &after) == 0, after.st_size == info.st_size, data.count == info.st_size,
                    after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                    after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec
                else { throw VNError.message("存档正在写入，尚未采用此次结果。") }
                total += data.count
                paths.append(root.appendingPathComponent(key).path)
                let header = mahoyo ? MahoyoSaveHeader.parse(data) : nil
                slots.append(
                    SaveSlotObservation(
                        filename: key,
                        modifiedAt: Date(
                            timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec)
                                / 1e9), fingerprint: FileSafety.fingerprint(data), script: header?.script,
                        recordedAt: header?.date))
            }
        }
        try visit(fd, relative: "")
        slots.sort { $0.filename < $1.filename }
        let signature = slots.map { "\($0.filename)|\($0.fingerprint)|\($0.modifiedAt.timeIntervalSince1970)" }.joined(
            separator: "\n")
        return SaveSnapshot(
            observation: SaveObservation(
                fingerprint: FileSafety.fingerprint(Data(signature.utf8)), slots: slots,
                adapter: mahoyo ? "魔法使之夜 Steam · SUD 头部 v1（章节待核对）" : "通用文件变化观察（路线未识别）"), watchedPaths: paths)
    }
    public static func stable(directory: URL, mahoyo: Bool) async throws -> SaveSnapshot {
        let first = try scan(directory: directory, mahoyo: mahoyo)
        try await Task.sleep(for: .seconds(1))
        let second = try scan(directory: directory, mahoyo: mahoyo)
        guard first.observation.fingerprint == second.observation.fingerprint else {
            throw VNError.message("存档仍在变化，尚未采用此次结果。请稍后刷新。")
        }
        return second
    }
}
