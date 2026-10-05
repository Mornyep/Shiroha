import Darwin
import Foundation
import ImageIO

public struct LibraryTransferReceipt: Sendable {
    public let exportedCount: Int
    public let assetCount: Int
    public let bytes: Int
}
public struct LibraryTransferPreview: Sendable {
    public let games: [Game]
    public let collections: [GameCollection]
    public let assetCount: Int
    public let sourceURL: URL
    public let fingerprint: String
    public let warnings: [String]
}

/// Portable data only. Launch paths remain inert strings; only validated images are copied.
public enum LibraryTransfer {
    private static let manifestLimit = 8 * 1024 * 1024
    private static let assetLimit = 8 * 1024 * 1024
    private static let totalLimit = 128 * 1024 * 1024
    private struct Asset: Codable {
        let path: String
        let sha256: String
        let bytes: Int
    }
    private struct Manifest: Codable {
        let version: Int
        let createdAt: Date
        var games: [Game]
        let assets: [Asset]
        var collections: [GameCollection]?
    }
    private struct Validated {
        let manifest: Manifest
        let data: [String: Data]
        let fingerprint: String
    }
    private static func fail(_ message: String) -> VNError { .message("资料包：" + message) }

    public static func export(games: [Game], collections: [GameCollection] = [], to destination: URL) throws
        -> LibraryTransferReceipt
    {
        guard games.count <= 1000, Set(games.map(\.id)).count == games.count else { throw fail("游戏数量超限或 ID 重复") }
        try PersonalLibrary.validate(games: games, collections: collections)
        let fm = FileManager.default
        guard !exists(destination) else { throw fail("目标已存在，不能覆盖") }
        let parent = destination.deletingLastPathComponent()
        try rejectLinkedComponents(parent)
        try requireDirectory(parent)
        let stage = parent.appendingPathComponent(".vn-transfer-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        try fm.createDirectory(at: stage.appendingPathComponent("assets"), withIntermediateDirectories: false)
        var assets: [Asset] = []
        var content: [String: String] = [:]
        var total = 0
        var portable = games
        for index in portable.indices {
            portable[index].bookmarks = portable[index].bookmarks ?? []
            try mapArtwork(&portable[index]) { path in
                let url = URL(fileURLWithPath: path)
                try rejectLinkedComponents(url)
                let data = try read(url, limit: assetLimit)
                let hash = FileSafety.fingerprint(data)
                if let relative = content[hash] { return relative }
                guard assets.count < 3000, total <= totalLimit - data.count else { throw fail("图片数量或总容量超限") }
                let relative = "assets/" + hash + ".image"
                let target = stage.appendingPathComponent(relative)
                try data.write(to: target, options: .withoutOverwriting)
                try validateImage(data, at: target)
                assets.append(Asset(path: relative, sha256: hash, bytes: data.count))
                content[hash] = relative
                total += data.count
                return relative
            }
        }
        let manifest = Manifest(
            version: LibraryDocument.currentVersion, createdAt: Date(), games: portable, assets: assets,
            collections: collections)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(manifest)
        guard encoded.count <= manifestLimit else { throw fail("清单容量超限") }
        try encoded.write(to: stage.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
        // moveItem fails if another process has created the destination in the meantime.
        try fm.moveItem(at: stage, to: destination)
        return LibraryTransferReceipt(
            exportedCount: games.count, assetCount: assets.count, bytes: total + encoded.count)
    }

    public static func preview(at directory: URL) throws -> LibraryTransferPreview {
        let validated = try validate(directory)
        return LibraryTransferPreview(
            games: validated.manifest.games, collections: validated.manifest.collections ?? [],
            assetCount: validated.manifest.assets.count, sourceURL: directory, fingerprint: validated.fingerprint,
            warnings: ["启动路径与容器引用需要在本机确认；导入不会执行启动配置。"])
    }

    public static func importArtwork(from preview: LibraryTransferPreview, to cacheDirectory: URL) throws -> [Game] {
        // Re-read the whole package before any cache mutation; retain precisely these validated bytes.
        let validated = try validate(preview.sourceURL)
        guard validated.fingerprint == preview.fingerprint else { throw fail("预览后资料包已改变，请重新预览") }
        let fm = FileManager.default
        try rejectLinkedComponents(cacheDirectory)
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try requireDirectory(cacheDirectory)
        let identifier = UUID().uuidString
        let stage = cacheDirectory.appendingPathComponent(".import-" + identifier, isDirectory: true)
        let target = cacheDirectory.appendingPathComponent("collection-" + identifier, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        var paths: [String: String] = [:]
        for asset in validated.manifest.assets {
            let name = asset.sha256 + ".image"
            guard let data = validated.data[asset.path] else { throw fail("图片缺失") }
            try data.write(to: stage.appendingPathComponent(name), options: .withoutOverwriting)
            paths[asset.path] = target.appendingPathComponent(name).path
        }
        var games = validated.manifest.games
        for index in games.indices {
            try mapArtwork(&games[index]) { path in
                guard let mapped = paths[path] else { throw fail("未登记的图片引用") }
                return mapped
            }
        }
        try fm.moveItem(at: stage, to: target)
        return games
    }

    private static func validate(_ root: URL) throws -> Validated {
        try rejectLinkedComponents(root)
        try requireDirectory(root)
        let manifestData = try read(root.appendingPathComponent("manifest.json"), limit: manifestLimit)
        // Bound arrays before Codable creates a Game graph. JSON is itself bounded to 8 MB.
        guard let json = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
            let version = json["version"] as? Int, (1...LibraryDocument.currentVersion).contains(version),
            let gameArray = json["games"] as? [Any], gameArray.count <= 1000,
            let assetArray = json["assets"] as? [Any], assetArray.count <= 3000
        else { throw fail("版本不支持或清单数量超限") }
        var manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        if manifest.version >= 4 {
            for index in manifest.games.indices {
                manifest.games[index].bookmarks = manifest.games[index].bookmarks ?? []
            }
        }
        try PersonalLibrary.validate(games: manifest.games, collections: manifest.collections ?? [])
        guard Set(manifest.games.map(\.id)).count == manifest.games.count else { throw fail("游戏 ID 重复") }
        var assetsByPath: [String: Asset] = [:]
        var declaredTotal = 0
        for asset in manifest.assets {
            guard validAssetPath(asset.path), asset.bytes > 0, asset.bytes <= assetLimit,
                asset.sha256.count == 64, asset.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                assetsByPath[asset.path] == nil, declaredTotal <= totalLimit - asset.bytes
            else { throw fail("图片路径、摘要或容量非法") }
            assetsByPath[asset.path] = asset
            declaredTotal += asset.bytes
        }
        var referenced = Set<String>()
        var games = manifest.games
        for index in games.indices {
            try mapArtwork(&games[index]) { path in
                guard validAssetPath(path), assetsByPath[path] != nil else { throw fail("图片引用越界或未登记") }
                referenced.insert(path)
                return path
            }
        }
        guard referenced == Set(assetsByPath.keys) else { throw fail("含有未引用的文件") }
        var expected = Set(assetsByPath.keys)
        expected.insert("manifest.json")
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey],
                options: [])
        else { throw fail("目录无法读取") }
        var visited = 0
        for case let url as URL in walker {
            visited += 1
            guard visited <= 3002 else { throw fail("目录条目超限") }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, FileSafety.contained(url, in: root) else { throw fail("禁止符号链接") }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            if values.isDirectory == true {
                guard relative == "assets" else { throw fail("含有额外目录") }
            } else {
                guard values.isRegularFile == true, expected.remove(relative) != nil else { throw fail("含有额外或非法文件") }
            }
        }
        guard expected.isEmpty else { throw fail("文件缺失") }
        var data: [String: Data] = [:]
        for asset in manifest.assets {
            let url = root.appendingPathComponent(asset.path)
            try rejectLinkedComponents(url)
            let bytes = try read(url, limit: assetLimit)
            guard bytes.count == asset.bytes, FileSafety.fingerprint(bytes) == asset.sha256 else {
                throw fail("图片摘要不匹配")
            }
            try validateImage(bytes, at: url)
            data[asset.path] = bytes
        }
        return Validated(manifest: manifest, data: data, fingerprint: FileSafety.fingerprint(manifestData))
    }

    private static func validAssetPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0] == "assets" && !parts[1].isEmpty && parts[1] != "." && parts[1] != ".."
            && !path.contains("\\") && !path.contains("\0")
    }
    private static func mapArtwork(_ game: inout Game, _ transform: (String) throws -> String) rethrows {
        if let path = game.coverPath { game.coverPath = try transform(path) }
        if let path = game.metadata?.backgroundPath { game.metadata?.backgroundPath = try transform(path) }
        if let path = game.metadata?.wallpaperArtwork?.path {
            game.metadata?.wallpaperArtwork?.path = try transform(path)
        }
        if let path = game.metadata?.discArtwork?.path { game.metadata?.discArtwork?.path = try transform(path) }
    }
    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw fail("需要普通目录") }
    }
    private static func rejectLinkedComponents(_ url: URL) throws {
        var component = url
        while component.path != "/" {
            if exists(component) {
                let attrs = try FileManager.default.attributesOfItem(atPath: component.path)
                guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else { throw fail("禁止符号链接") }
            }
            component.deleteLastPathComponent()
        }
    }
    private static func read(_ url: URL, limit: Int) throws -> Data {
        // Open each ancestor via its descriptor, closing the check/open symlink race.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let filename = parts.last else { throw fail("缺少文件名") }
        var directory = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw fail("无法安全读取目录") }
        defer { Darwin.close(directory) }
        for part in parts.dropLast() {
            let next = openat(directory, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw fail("目录包含链接或无法读取") }
            Darwin.close(directory)
            directory = next
        }
        let descriptor = openat(directory, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw fail("无法安全读取文件") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_size >= 0,
            status.st_size <= limit
        else { throw fail("文件类型或容量不符合要求") }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit, data.count == status.st_size else { throw fail("文件在读取时改变") }
        return data
    }
    private static func validateImage(_ data: Data, at url: URL) throws {
        guard let size = ArtworkQuality.size(url.path), size.pixels <= 40_000_000,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0, width <= 16000, height <= 16000, width * height <= 40_000_000,
            CGImageSourceGetCount(source) == 1,
            CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
        else { throw fail("不是有效的静态图片或像素超限") }
    }
}
