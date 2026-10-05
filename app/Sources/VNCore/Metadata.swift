import Foundation

public struct GameMetadata: Codable, Equatable, Sendable {
    public var productType: String?
    public var identity: MetadataIdentity?
    public var fieldOrigins: [String: MetadataOrigin]?
    public var artworkRevision: Int?
    public var wallpaperArtwork: ArtworkSelection?
    public var discArtwork: ArtworkSelection?
    public var reviews: SteamReviews?
    public var publicProfiles: [PublicProfile]?
    public var summary: String?
    public var developer: String?
    public var publisher: String?
    public var releaseDate: String?
    public var genres: [String]?
    public var coverSource: String?
    public var detailSource: String?
    public var titleSource: String?
    public var originalTitle: String?
    public var localizedTitle: String?
    public var localizedTitleSource: String?
    public var backgroundPath: String?
    public var backgroundSource: String?
    public var backgroundURL: String?
    public var screenshotURLs: [String]?
    public var updatedAt: Date?
    public init() {}
}
public struct MetadataResult: Sendable {
    public var title: String?
    public var coverPath: String?
    public var metadata = GameMetadata()
    public init() {}
}
public enum MetadataService {
    public static func merge(_ result: MetadataResult, into current: Game, imported: Game) -> Game {
        MetadataEditing.automatic(result, current: current, imported: imported)
    }
    public static func local(game: Game) throws -> MetadataResult {
        var result = MetadataResult()
        let root = URL(fileURLWithPath: game.workingDirectory)
        var candidates: [(URL, String, Int)] = []
        // Only named artwork in the selected folder (two levels), never arbitrary screenshots or saves.
        let files = try FileSafety.walk(root, maximum: 1500).files
        let extensions = Set(["jpg", "jpeg", "png", "webp", "tiff"])
        for url in files where extensions.contains(url.pathExtension.lowercased()) {
            let depth = url.pathComponents.count - root.pathComponents.count
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            guard depth <= 2 else { continue }
            if ["cover", "folder", "poster", "front", "封面", "ジャケット", "library_600x900", "header"].contains(name) {
                candidates.append((url, "游戏目录：" + url.lastPathComponent, name == "cover" ? 0 : 2))
            }
        }
        if game.kind == .steam, !game.steamAppID.isEmpty, game.steamAppID.allSatisfy({ $0.isASCII && $0.isNumber }) {
            let cache = URL(fileURLWithPath: game.executable).deletingLastPathComponent().appendingPathComponent(
                "appcache/librarycache")
            let id = game.steamAppID
            if let background = localSteamBackground(cache: cache, appID: id) {
                result.metadata.backgroundPath = background.path
                result.metadata.backgroundSource =
                    "本机 Steam librarycache · App ID " + id + " · " + background.lastPathComponent
            }
            for filename in [
                id + "_library_600x900.jpg", id + "_library_600x900_2x.jpg", id + "_header.jpg",
                id + "/library_600x900.jpg", id + "/library_600x900_2x.jpg", id + "/header.jpg",
            ] {
                let url = cache.appendingPathComponent(filename)
                if FileSafety.contained(url, in: cache), FileManager.default.fileExists(atPath: url.path) {
                    candidates.append(
                        (url, "本机 Steam librarycache · App ID " + id, filename.contains("600x900") ? -2 : 1))
                }
            }
            let nested = cache.appendingPathComponent(id)
            if FileSafety.contained(nested, in: cache), FileManager.default.fileExists(atPath: nested.path) {
                for url in (try? FileSafety.walk(nested, maximum: 150).files) ?? []
                where extensions.contains(url.pathExtension.lowercased())
                    && url.lastPathComponent.contains("library_600x900")
                { candidates.append((url, "本机 Steam librarycache · App ID " + id, -2)) }
            }
        }
        if let first = candidates.sorted(by: { a, b in
            let x = ArtworkQuality.size(a.0.path)
            let y = ArtworkQuality.size(b.0.path)
            if x?.portrait != y?.portrait { return x?.portrait == true }
            if x?.pixels != y?.pixels { return (x?.pixels ?? 0) > (y?.pixels ?? 0) }
            return a.2 == b.2 ? a.0.path < b.0.path : a.2 < b.2
        }).first(where: { (try? FileSafety.read($0.0, limit: 20 * 1024 * 1024)) != nil }) {
            result.coverPath = first.0.path
            result.metadata.coverSource = first.1
        }
        // Explicit title keys only. No scripts, binary resource archives or command evaluation.
        for name in ["Game.ini", "game.ini", "config.ini"] {
            let url = root.appendingPathComponent(name)
            guard FileSafety.contained(url, in: root), let data = try? FileSafety.read(url, limit: 128 * 1024),
                let text = String(data: data, encoding: .utf8)
            else { continue }
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if parts.count == 2, ["title", "gametitle", "gamename"].contains(parts[0].lowercased()),
                    !parts[1].isEmpty, parts[1].count < 150
                {
                    result.title = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    result.metadata.titleSource = "本地 " + name + " 的 " + parts[0]
                    break
                }
            }
            if result.title != nil { break }
        }
        result.metadata.updatedAt = Date()
        return result
    }
    public static func steam(appID: String, cacheDirectory: URL) async throws -> MetadataResult {
        guard validSteamID(appID) else { throw VNError.message("Steam App ID 无效") }
        let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=schinese")!
        let data = try await boundedFetch(url, limit: 2 * 1024 * 1024)
        let parsed = try parseSteam(data, appID: appID)
        var result = parsed.result
        if appID == "4012810",
            let official = URL(string: "https://steinsgate.jp/reboot/zh-hans/common/img/top_image.jpg?20260820"),
            let path = try? await cacheArtwork(
                official, appID: appID, role: "official-poster", directory: cacheDirectory)
        {
            result.coverPath = path
            result.metadata.coverSource = official.absoluteString
        }
        if result.coverPath == nil, let header = parsed.coverURL {
            for cover in ArtworkQuality.steamPosters(header: header) {
                if let path = try? await cacheArtwork(cover, appID: appID, role: "poster", directory: cacheDirectory),
                    let size = ArtworkQuality.size(path), size.portrait
                {
                    if result.coverPath == nil || ArtworkQuality.improves(path, over: result.coverPath) {
                        result.coverPath = path
                        result.metadata.coverSource = cover.absoluteString
                    }
                    if size.width >= 600 && size.height >= 900 { break }
                }
            }
            if result.coverPath == nil,
                let path = try? await cacheArtwork(header, appID: appID, role: "cover", directory: cacheDirectory)
            {
                result.coverPath = path
                result.metadata.coverSource = header.absoluteString
            }
        }
        result.metadata.wallpaperArtwork = try await ArtworkCatalog.fetch(
            appID: appID, role: .wallpaper, directory: cacheDirectory)
        result.metadata.discArtwork = try await ArtworkCatalog.fetch(
            appID: appID, role: .disc, directory: cacheDirectory)
        result.metadata.artworkRevision = ArtworkCatalog.revision
        return result
    }
    public static func parseSteam(_ data: Data, appID: String) throws -> (result: MetadataResult, coverURL: URL?) {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let app = obj[appID] as? [String: Any], app["success"] as? Bool == true,
            let details = app["data"] as? [String: Any]
        else { throw VNError.message("Steam 未返回该 App ID 的公开资料；可能受地区或商店状态限制。") }
        var result = MetadataResult()
        result.title = (details["name"] as? String).map { String($0.prefix(150)) }
        result.metadata.productType = (details["type"] as? String).map { String($0.prefix(40)) }
        result.metadata.originalTitle = result.title
        result.metadata.identity = MetadataIdentity(steamAppID: appID, name: result.title ?? "Steam " + appID)
        let source = "https://store.steampowered.com/app/" + appID + "/?l=schinese"
        if let known = LocalizedMetadata.steamTitle(appID: appID) {
            result.metadata.localizedTitle = known.title
            result.metadata.localizedTitleSource = known.source
        } else if let title = result.title, LocalizedMetadata.containsHan(title) {
            result.metadata.localizedTitle = title
            result.metadata.localizedTitleSource = source
        }
        result.metadata.backgroundURL =
            ["background_raw", "background"].compactMap { details[$0] as? String }.compactMap(URL.init(string:)).first(
                where: allowedImageURL)?.absoluteString
        result.metadata.screenshotURLs = (details["screenshots"] as? [[String: Any]])?.prefix(12).compactMap {
            $0["path_full"] as? String
        }.compactMap(URL.init(string:)).filter(allowedImageURL).map(\.absoluteString)
        result.metadata.summary = (details["short_description"] as? String).map { String(plainText($0).prefix(3000)) }
        result.metadata.developer = (details["developers"] as? [String])?.prefix(8).joined(separator: "、")
        result.metadata.publisher = (details["publishers"] as? [String])?.prefix(8).joined(separator: "、")
        result.metadata.releaseDate = (details["release_date"] as? [String: Any])?["date"] as? String
        result.metadata.genres = (details["genres"] as? [[String: Any]])?.compactMap { $0["description"] as? String }
            .prefix(12).map { $0 }
        result.metadata.detailSource = "https://store.steampowered.com/app/" + appID
        result.metadata.titleSource = result.metadata.detailSource
        result.metadata.updatedAt = Date()
        let cover = (details["header_image"] as? String).flatMap(URL.init(string:)).flatMap {
            allowedImageURL($0) ? $0 : nil
        }
        return (result, cover)
    }
    public static func plainText(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, replacement) in [
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&amp;", "&"),
        ] { text = text.replacingOccurrences(of: entity, with: replacement) }
        return text
    }
    public static func allowedImageURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil,
            url.port == nil || url.port == 443
        else { return false }
        if ArtworkCatalog.entries.values.contains(where: {
            $0.wallpaperURL == url.absoluteString || $0.discURL == url.absoluteString
        }) {
            return true
        }
        if host == "steinsgate.jp", url.path == "/reboot/zh-hans/common/img/top_image.jpg" { return true }
        return ["steamstatic.com", "steamcdn-a.akamaihd.net"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    public static func localSteamBackground(cache: URL, appID: String) -> URL? {
        guard validSteamID(appID) else { return nil }
        let extensions = Set(["jpg", "jpeg", "png"])
        let direct = [
            appID + "_library_hero.jpg", appID + "_library_hero_2x.jpg", appID + "/library_hero.jpg",
            appID + "/library_hero_2x.jpg",
        ].map { cache.appendingPathComponent($0) }
        let nested = cache.appendingPathComponent(appID)
        let discovered =
            FileSafety.contained(nested, in: cache)
            ? ((try? FileSafety.walk(nested, maximum: 150).files) ?? []).filter {
                $0.lastPathComponent.contains("library_hero") && !$0.lastPathComponent.contains("_blur")
                    && extensions.contains($0.pathExtension.lowercased())
            }.sorted { $0.path < $1.path } : []
        return (direct + discovered).first {
            FileSafety.contained($0, in: cache) && (try? FileSafety.read($0, limit: 8 * 1024 * 1024)) != nil
        }
    }
    static func cacheArtwork(_ url: URL, appID: String, role: String, directory: URL) async throws -> String {
        guard allowedImageURL(url) else { throw VNError.message("图片来源不受信任") }
        let image = try await boundedFetch(url, limit: 8 * 1024 * 1024)
        guard image.starts(with: [0xff, 0xd8, 0xff]) || image.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw VNError.message("商店图片格式无法确认")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(
            "steam-\(appID)-\(role)-\(FileSafety.fingerprint(image).prefix(12)).img")
        try image.write(to: destination, options: .atomic)
        return destination.path
    }
    static func boundedFetch(_ url: URL, limit: Int) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: MetadataRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            response.expectedContentLength <= limit
        else { throw VNError.message("公开资料请求失败或超过上限") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw VNError.message("资料超过大小上限") }
            data.append(byte)
        }
        return data
    }
}
private final class MetadataRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? { nil }
}
