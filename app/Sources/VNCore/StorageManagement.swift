import Foundation

public struct SaveCandidate: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let reason: String
    public let fileCount: Int
    public let bytes: Int64
}
public struct StorageScan: Sendable {
    public let gameID: UUID
    public let directory: String
    public let bytes: Int64
    public let fingerprint: String
    public let candidates: [SaveCandidate]
    public let warnings: [String]
}
public struct SaveArchive: Codable, Sendable {
    public let source: String
    public let destination: String
    public let manifest: BackupManifest
}
public struct StorageReceipt: Codable, Sendable {
    public let gameID: UUID
    public let gameDirectory: String
    public let created: Date
    public let archives: [SaveArchive]
    public let inventoryFingerprint: String
}
public enum StorageManagement {
    static func inventory(_ root: URL) throws -> (bytes: Int64, fingerprint: String, files: [URL]) {
        guard root.standardizedFileURL.path == root.resolvingSymlinksInPath().path else {
            throw VNError.message("游戏目录经过符号链接，需重新定位实际目录")
        }
        var enumerationFailed = false
        guard
            let iterator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
                ], options: [],
                errorHandler: { _, _ in
                    enumerationFailed = true
                    return false
                })
        else { throw VNError.message("无法读取目录") }
        var rows: [String] = []
        var files: [URL] = []
        var total: Int64 = 0
        var count = 0
        for case let url as URL in iterator {
            try Task.checkCancellation()
            count += 1
            guard count <= 100000 else { throw VNError.message("文件太多，扫描不完整，不能用于卸载预览") }
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
            ])
            guard values.isSymbolicLink != true else { throw VNError.message("目录内含符号链接，无法完整判断归属；请使用原安装器处理") }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                total += size
                files.append(url)
                rows.append(url.path + "|\(size)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
            }
        }
        guard !enumerationFailed else { throw VNError.message("部分目录无权读取，扫描不完整，停止卸载") }
        return (total, FileSafety.fingerprint(Data(rows.sorted().joined(separator: "\n").utf8)), files)
    }
    public static func validateRoot(game: Game, library: [Game]) throws -> URL {
        let root = URL(fileURLWithPath: game.workingDirectory).standardizedFileURL
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let denied = [
            "/", "/Users", "/Applications", "/System", "/Library", "/Volumes", home.path,
            home.appendingPathComponent("Documents").path, home.appendingPathComponent("Downloads").path,
            home.appendingPathComponent("Desktop").path, CrossOver.bottlesRoot.path,
        ]
        let protectedNames: Set<String> = [
            "users", "applications", "library", "application support", "documents", "downloads", "desktop", "pictures",
            "movies", "music", "volumes", "bottles", "crossover", "drive_c", "windows", "system32", "steam",
            "steamapps", "common", "program files", "program files (x86)",
        ]
        guard !protectedNames.contains(root.lastPathComponent.lowercased()),
            !fm.fileExists(atPath: root.appendingPathComponent("cxbottle.conf").path), !denied.contains(root.path),
            root.pathComponents.count >= 4, root.path == root.resolvingSymlinksInPath().path,
            (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { throw VNError.message("此目录不能作为独立游戏本体，未允许卸载") }
        guard
            !library.contains(where: {
                $0.id != game.id && !$0.isUtility
                    && (FileSafety.contained(URL(fileURLWithPath: $0.workingDirectory), in: root)
                        || FileSafety.contained(root, in: URL(fileURLWithPath: $0.workingDirectory)))
            })
        else { throw VNError.message("此目录与其他库项共用，无法只删除这款游戏") }
        if game.kind == .steam {
            guard !game.steamAppID.isEmpty, game.steamAppID.allSatisfy({ $0.isASCII && $0.isNumber }),
                root.deletingLastPathComponent().lastPathComponent == "common",
                root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "steamapps"
            else { throw VNError.message("未确认 Steam 游戏独立目录") }
            let manifest = root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
                "appmanifest_\(game.steamAppID).acf")
            let text = String(decoding: try FileSafety.read(manifest, limit: 256 * 1024), as: UTF8.self)
            func value(_ key: String) -> String? {
                let re = try? NSRegularExpression(pattern: "\"" + key + "\"\\s*\"([^\"]*)\"")
                guard let match = re?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                    let range = Range(match.range(at: 1), in: text)
                else { return nil }
                return String(text[range])
            }
            guard value("appid") == game.steamAppID, value("installdir") == root.lastPathComponent else {
                throw VNError.message("Steam 清单与目录不一致，不能卸载")
            }
        } else {
            guard FileSafety.contained(URL(fileURLWithPath: game.executable), in: root),
                URL(fileURLWithPath: game.executable).pathExtension.lowercased() == "exe",
                fm.fileExists(atPath: game.executable),
                !["drive_c", "windows", "system32", "steam", "common", "program files", "program files (x86)"].contains(
                    root.lastPathComponent.lowercased())
            else { throw VNError.message("工作目录不是可确认的独立游戏目录") }
        }
        return root
    }
    public static func scan(game: Game, library: [Game], additional: [String] = []) throws -> StorageScan {
        let root = try validateRoot(game: game, library: library)
        let listing = try inventory(root)
        let markers: Set<String> = [
            "save", "saves", "savedata", "savedate", "savedgame", "savedgames", "savegame", "savegames", "savedgames",
            "存档", "セーブ",
        ]
        var folders: [String: String] = [:]
        for file in listing.files {
            var parent = file.deletingLastPathComponent()
            while parent.path != root.path && FileSafety.contained(parent, in: root) {
                if markers.contains(parent.lastPathComponent.lowercased()) { folders[parent.path] = "游戏目录中的存档命名线索" }
                parent.deleteLastPathComponent()
            }
        }
        if let selected = game.saveDirectory { folders[selected] = "你在作品配置确认的存档位置" }
        for path in additional { folders[path] = "本次手动补充" }
        if game.kind == .steam {
            let userdata = URL(fileURLWithPath: game.executable).deletingLastPathComponent().appendingPathComponent(
                "userdata")
            for user
                in ((try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? [])
                .prefix(100)
            {
                let target = user.appendingPathComponent(game.steamAppID).appendingPathComponent("remote")
                if FileSafety.contained(target, in: userdata), FileManager.default.fileExists(atPath: target.path) {
                    folders[target.path] = "Steam userdata / App ID / remote；不保证云端已同步"
                }
            }
        }
        let paths = folders.keys.sorted().filter { path in
            !folders.keys.contains { other in other != path && path.hasPrefix(other + "/") }
        }
        let candidates = try paths.map { path in
            let content = try inventory(URL(fileURLWithPath: path))
            return SaveCandidate(
                id: String(FileSafety.fingerprint(Data(path.utf8)).prefix(16)), path: path, reason: folders[path] ?? "",
                fileCount: content.files.count, bytes: content.bytes)
        }
        return StorageScan(
            gameID: game.id, directory: root.path, bytes: listing.bytes, fingerprint: listing.fingerprint,
            candidates: candidates, warnings: ["自动命名扫描不覆盖所有引擎、注册表存档、AppData 与云端存档。请补充已知位置；AI 无法证明没有其他存档。"])
    }
    public static func archive(_ scan: StorageScan, to parent: URL) throws -> StorageReceipt {
        let gameRoot = URL(fileURLWithPath: scan.directory)
        guard !FileSafety.contained(parent, in: gameRoot), !FileManager.default.fileExists(atPath: parent.path) else {
            throw VNError.message("备份必须位于游戏目录以外的全新位置")
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var saved: [SaveArchive] = []
        for (index, candidate) in scan.candidates.enumerated() {
            let destination = parent.appendingPathComponent("Save-\(index+1)")
            let manifest = try SaveBackup.copyAndVerify(
                source: URL(fileURLWithPath: candidate.path), destination: destination, includeHidden: true)
            guard manifest.hashes.count == candidate.fileCount else {
                throw VNError.message("存档含隐藏/特殊文件或内容变化，未获得完整副本。停止卸载。")
            }
            saved.append(SaveArchive(source: candidate.path, destination: destination.path, manifest: manifest))
        }
        let receipt = StorageReceipt(
            gameID: scan.gameID, gameDirectory: scan.directory, created: Date(), archives: saved,
            inventoryFingerprint: scan.fingerprint)
        try Storage.save(receipt, to: parent.appendingPathComponent("save-receipt.json"))
        return receipt
    }
    public static func verifyBeforeUninstall(receipt: StorageReceipt, game: Game, library: [Game]) throws {
        let root = try validateRoot(game: game, library: library)
        guard receipt.gameID == game.id, receipt.gameDirectory == root.path,
            try inventory(root).fingerprint == receipt.inventoryFingerprint
        else { throw VNError.message("游戏文件在预览后变化，请重新扫描与备份") }
        for archive in receipt.archives {
            guard !FileSafety.contained(URL(fileURLWithPath: archive.destination), in: root) else {
                throw VNError.message("备份落在卸载范围内")
            }
            let src = try inventory(URL(fileURLWithPath: archive.source))
            let dst = try inventory(URL(fileURLWithPath: archive.destination))
            guard src.files.count == archive.manifest.hashes.count, dst.files.count == archive.manifest.hashes.count
            else { throw VNError.message("存档或备份内容已变化，停止卸载") }
            for (relative, hash) in archive.manifest.hashes {
                for parent in [archive.source, archive.destination] {
                    let base = URL(fileURLWithPath: parent)
                    let target = base.appendingPathComponent(relative)
                    guard FileSafety.contained(target, in: base),
                        FileSafety.fingerprint(try FileSafety.read(target, limit: 128 * 1024 * 1024)) == hash
                    else { throw VNError.message("存档或备份哈希不匹配，停止卸载") }
                }
            }
        }
    }
}
