import Foundation

public struct MetadataIdentity: Codable, Equatable, Sendable {
    public var steamAppID: String
    public var name: String
    public var confirmedAt: Date?
    public init(steamAppID: String, name: String, confirmedAt: Date? = nil) {
        self.steamAppID = steamAppID
        self.name = name
        self.confirmedAt = confirmedAt
    }
}
public enum MetadataField: String, CaseIterable, Codable, Sendable, Identifiable {
    case title, originalTitle, summary, developer, publisher, releaseDate, genres
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .title: "显示标题"
        case .originalTitle: "原名"
        case .summary: "简介"
        case .developer: "开发商"
        case .publisher: "发行商"
        case .releaseDate: "发行日期"
        case .genres: "分类"
        }
    }
}
public struct MetadataOrigin: Codable, Equatable, Sendable {
    public var source: String
    public var date: Date?
    public var manual: Bool
    public init(source: String, date: Date? = nil, manual: Bool = false) {
        self.source = source
        self.date = date
        self.manual = manual
    }
    public var priority: Int { manual ? 100 : (source.hasPrefix("https://") ? 60 : (source.hasPrefix("本地") ? 30 : 10)) }
}
extension Game {
    /// Explicit association is independent of Steam's launch App ID.
    public var metadataSteamID: String? {
        if let identity = metadata?.identity {
            return MetadataService.validSteamID(identity.steamAppID) ? identity.steamAppID : nil
        }
        return kind == .steam && MetadataService.validSteamID(steamAppID) ? steamAppID : nil
    }
    public func metadataValue(_ field: MetadataField) -> String {
        switch field {
        case .title: displayTitle
        case .originalTitle: metadata?.originalTitle ?? ""
        case .summary: metadata?.summary ?? ""
        case .developer: metadata?.developer ?? ""
        case .publisher: metadata?.publisher ?? ""
        case .releaseDate: metadata?.releaseDate ?? ""
        case .genres: metadata?.genres?.joined(separator: "、") ?? ""
        }
    }
    public func metadataOrigin(_ field: MetadataField) -> MetadataOrigin {
        if field == .title, metadata?.titleSource == "手动编辑" {
            return MetadataOrigin(
                source: "手动编辑", date: metadata?.fieldOrigins?[field.rawValue]?.date ?? metadata?.updatedAt, manual: true
            )
        }
        if let origin = metadata?.fieldOrigins?[field.rawValue] { return origin }
        if field == .title {
            if metadata?.titleSource == "手动编辑" {
                return MetadataOrigin(source: "手动编辑", date: metadata?.updatedAt, manual: true)
            }
            return MetadataOrigin(
                source: metadata?.localizedTitleSource ?? metadata?.titleSource ?? "导入时的名称", date: metadata?.updatedAt)
        }
        return MetadataOrigin(source: metadata?.detailSource ?? "此前导入的资料", date: metadata?.updatedAt)
    }
}
public enum MetadataEditing {
    public static func steamID(from input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if MetadataService.validSteamID(value), (UInt64(value) ?? 0) > 0 { return value }
        if let url = URL(string: value), url.scheme == "https", url.host?.lowercased() == "store.steampowered.com",
            url.user == nil, url.password == nil, url.port == nil || url.port == 443
        {
            let components = url.path.split(separator: "/")
            if components.count >= 2, components[0] == "app", MetadataService.validSteamID(String(components[1])),
                (UInt64(components[1]) ?? 0) > 0
            {
                return String(components[1])
            }
        }
        throw VNError.message("请输入 Steam App ID 或 https://store.steampowered.com/app/… 链接。")
    }
    public static func manual(_ values: [MetadataField: String], in current: Game, at date: Date = Date()) throws
        -> Game
    {
        var result = current
        for (field, value) in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard field != .title || !cleaned.isEmpty else { throw VNError.message("显示标题不能为空。") }
            guard cleaned.count <= (field == .summary ? 10000 : 500) else {
                throw VNError.message("\(field.label)过长，请缩短后保存。")
            }
            assign(cleaned, field: field, origin: MetadataOrigin(source: "手动编辑", date: date, manual: true), to: &result)
        }
        return result
    }
    public static func rematch(
        _ candidate: MetadataResult, fields: Set<MetadataField>, includeArtwork: Bool, into current: Game,
        at date: Date = Date()
    ) throws -> Game {
        guard var identity = candidate.metadata.identity, MetadataService.validSteamID(identity.steamAppID),
            !identity.name.isEmpty
        else { throw VNError.message("候选没有可核验的作品身份。") }
        let different = current.metadataSteamID != identity.steamAppID
        guard !different || fields.contains(.title) || current.metadataOrigin(.title).manual else {
            throw VNError.message("更换作品时请选择显示标题，或先设定手动标题。")
        }
        var game = current
        var meta = game.metadata ?? GameMetadata()
        if different {
            // Carry only explicit corrections across a change in work/edition.
            var clean = GameMetadata()
            clean.originalTitle = meta.originalTitle
            clean.fieldOrigins = meta.fieldOrigins?.filter { $0.value.manual }
            clean.titleSource = current.metadataOrigin(.title).manual ? "手动编辑" : nil
            clean.localizedTitle = current.metadataOrigin(.title).manual ? current.displayTitle : nil
            clean.originalTitle = current.metadataOrigin(.originalTitle).manual ? meta.originalTitle : nil
            clean.summary = current.metadataOrigin(.summary).manual ? meta.summary : nil
            clean.developer = current.metadataOrigin(.developer).manual ? meta.developer : nil
            clean.publisher = current.metadataOrigin(.publisher).manual ? meta.publisher : nil
            clean.releaseDate = current.metadataOrigin(.releaseDate).manual ? meta.releaseDate : nil
            clean.genres = current.metadataOrigin(.genres).manual ? meta.genres : nil
            if meta.coverSource == "手动选择" { clean.coverSource = meta.coverSource } else { game.coverPath = nil }
            if meta.chosenWallpaper?.userLocked == true {
                clean.wallpaperArtwork = meta.chosenWallpaper
                clean.backgroundPath = meta.chosenWallpaper?.path
                clean.backgroundSource = "手动选择"
            }
            if meta.discArtwork?.userLocked == true { clean.discArtwork = meta.discArtwork }
            meta = clean
        }
        identity.confirmedAt = date
        meta.identity = identity
        meta.detailSource = candidate.metadata.detailSource
        meta.productType = candidate.metadata.productType
        meta.backgroundURL = candidate.metadata.backgroundURL
        meta.screenshotURLs = candidate.metadata.screenshotURLs
        game.metadata = meta
        for field in fields {
            if let value = value(field, in: candidate) {
                assign(value, field: field, origin: origin(field, in: candidate), to: &game)
            }
        }
        if includeArtwork {
            if let path = candidate.coverPath, game.metadata?.coverSource != "手动选择" {
                game.coverPath = path
                game.metadata?.coverSource = candidate.metadata.coverSource
            }
            if game.metadata?.chosenWallpaper?.userLocked != true, let art = candidate.metadata.wallpaperArtwork {
                game.metadata?.wallpaperArtwork = art
                game.metadata?.backgroundPath = art.path
                game.metadata?.backgroundSource = art.source
            }
            if game.metadata?.discArtwork?.userLocked != true {
                game.metadata?.discArtwork = candidate.metadata.discArtwork
            }
            game.metadata?.artworkRevision = candidate.metadata.artworkRevision
        }
        game.metadata?.updatedAt = date
        return game
    }
    public static func automatic(_ candidate: MetadataResult, current: Game, imported: Game) -> Game {
        if let identity = candidate.metadata.identity, current.metadataSteamID != identity.steamAppID { return current }
        var game = current
        var meta = game.metadata ?? GameMetadata()
        if let identity = candidate.metadata.identity {
            if meta.identity == nil { meta.identity = identity } else { meta.identity?.name = identity.name }
        }
        if meta.originalTitle == nil { meta.originalTitle = candidate.metadata.originalTitle ?? imported.title }
        game.metadata = meta
        for field in MetadataField.allCases {
            guard let incoming = value(field, in: candidate) else { continue }
            let incomingOrigin = origin(field, in: candidate)
            let previousOrigin = game.metadataOrigin(field)
            guard !previousOrigin.manual,
                game.metadataValue(field).isEmpty || incomingOrigin.priority >= previousOrigin.priority
            else { continue }
            // A local ini must not replace the display name after a user or a known public source edited it.
            if field == .title, current.title != imported.title { continue }
            assign(incoming, field: field, origin: incomingOrigin, to: &game)
        }
        meta = game.metadata ?? GameMetadata()
        if let art = candidate.metadata.wallpaperArtwork,
            (candidate.metadata.artworkRevision ?? 0) >= (meta.artworkRevision ?? 0),
            meta.chosenWallpaper?.userLocked != true
        {
            meta.wallpaperArtwork = art
            meta.backgroundPath = art.path
            meta.backgroundSource = art.source
        }
        if let art = candidate.metadata.discArtwork,
            (candidate.metadata.artworkRevision ?? 0) >= (meta.artworkRevision ?? 0),
            meta.discArtwork?.userLocked != true
        {
            meta.discArtwork = art
        }
        if let value = candidate.metadata.backgroundURL { meta.backgroundURL = value }
        if let value = candidate.metadata.screenshotURLs { meta.screenshotURLs = value }
        if let cover = candidate.coverPath, meta.coverSource != "手动选择",
            current.coverPath == nil || ArtworkQuality.improves(cover, over: current.coverPath)
        {
            game.coverPath = cover
            meta.coverSource = candidate.metadata.coverSource
        }
        if let value = candidate.metadata.artworkRevision {
            meta.artworkRevision = max(value, meta.artworkRevision ?? 0)
        }
        if let reviews = candidate.metadata.reviews { meta.reviews = reviews }
        if let source = candidate.metadata.detailSource { meta.detailSource = source }
        if let type = candidate.metadata.productType { meta.productType = type }
        if let date = candidate.metadata.updatedAt { meta.updatedAt = date }
        game.metadata = meta
        return game
    }
    public static func value(_ field: MetadataField, in result: MetadataResult) -> String? {
        switch field {
        case .title: result.metadata.localizedTitle ?? result.title
        case .originalTitle: result.metadata.originalTitle
        case .summary: result.metadata.summary
        case .developer: result.metadata.developer
        case .publisher: result.metadata.publisher
        case .releaseDate: result.metadata.releaseDate
        case .genres: result.metadata.genres?.joined(separator: "、")
        }
    }
    public static func origin(_ field: MetadataField, in result: MetadataResult) -> MetadataOrigin {
        if let recorded = result.metadata.fieldOrigins?[field.rawValue] { return recorded }
        let source: String
        if field == .title {
            source = result.metadata.localizedTitleSource ?? result.metadata.titleSource ?? "本地资料"
        } else {
            source = result.metadata.detailSource ?? "本地资料"
        }
        return MetadataOrigin(source: source, date: result.metadata.updatedAt)
    }
    private static func assign(_ value: String, field: MetadataField, origin: MetadataOrigin, to game: inout Game) {
        if game.metadata == nil { game.metadata = GameMetadata() }
        if game.metadata?.fieldOrigins == nil { game.metadata?.fieldOrigins = [:] }
        game.metadata?.fieldOrigins?[field.rawValue] = origin
        switch field {
        case .title:
            game.title = value
            game.metadata?.localizedTitle = value
            game.metadata?.localizedTitleSource = origin.source
            game.metadata?.titleSource = origin.manual ? "手动编辑" : origin.source
        case .originalTitle: game.metadata?.originalTitle = value
        case .summary: game.metadata?.summary = value
        case .developer: game.metadata?.developer = value
        case .publisher: game.metadata?.publisher = value
        case .releaseDate: game.metadata?.releaseDate = value
        case .genres:
            game.metadata?.genres = value.components(separatedBy: CharacterSet(charactersIn: "、,，\n")).map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }
    }
}

public struct MetadataRevision: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var reason: String
    public var title: String
    public var coverPath: String?
    public var metadata: GameMetadata?
    public init(game: Game, reason: String) {
        self.title = game.title
        self.coverPath = game.coverPath
        self.metadata = game.metadata
        self.reason = reason
    }
    public func restoring(into current: Game) -> Game {
        var result = current
        result.title = title
        result.coverPath = coverPath
        result.metadata = metadata
        return result
    }
}
public enum MetadataHistory {
    public static func load(at url: URL) throws -> [MetadataRevision] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try FileSafety.read(url, limit: 4 * 1024 * 1024)
        let revisions = try JSONDecoder().decode([MetadataRevision].self, from: data)
        guard revisions.count <= 12 else { throw VNError.message("资料历史条数异常，保留原文件。") }
        return revisions
    }
    public static func record(_ game: Game, reason: String, at url: URL) throws {
        var revisions = try load(at: url)
        revisions.insert(MetadataRevision(game: game, reason: reason), at: 0)
        try Storage.save(Array(revisions.prefix(12)), to: url)
    }
}
