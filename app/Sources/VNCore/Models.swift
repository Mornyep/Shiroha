import Foundation

public enum LibraryState: String, Codable, CaseIterable, Sendable {
    case unplayed = "未开始"
    case playing = "在玩"
    case completed = "已通关"
}
public enum EntryKind: String, Codable, CaseIterable, Sendable {
    case executable = "独立 EXE"
    case steam = "Steam App ID"
}
public struct Game: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var series: String?
    public var bookmark: PlayBookmark?
    public var bookmarks: [NamedBookmark]?
    public var progress: PlayProgress?
    public var collectionIDs: [UUID]?
    public var isUtility: Bool { kind == .steam && ["228980"].contains(steamAppID) }
    public var alias = ""
    public var executable: String
    public var workingDirectory: String
    public var coverPath: String?
    public var favorite = false
    public var state = LibraryState.unplayed
    public var bottleID: String?
    public var kind = EntryKind.executable
    public var steamAppID = ""
    public var arguments: [String] = []
    public var lastLaunched: Date?
    public var saveDirectory: String?
    public var source = "手动选择；引用原文件"
    public var metadata: GameMetadata?
    public var runtimeChecks: [String: Bool]?
    public var runtimeChecksUpdatedAt: Date?
    public var displayTitle: String {
        if metadata?.titleSource == "手动编辑" { return title }
        return metadata?.localizedTitle
            ?? (kind == .steam ? LocalizedMetadata.steamTitle(appID: metadataSteamID ?? steamAppID)?.title : nil)
            ?? title
    }
    public var searchableTitle: String {
        [title, displayTitle, metadata?.originalTitle, alias].compactMap { $0 }.filter { !$0.isEmpty }.joined(
            separator: " ")
    }
    public init(title: String, executable: String, workingDirectory: String) {
        self.title = title
        self.executable = executable
        self.workingDirectory = workingDirectory
    }
}
public struct LibraryDocument: Codable, Sendable {
    public static let currentVersion = 4
    public var version = Self.currentVersion
    public var games: [Game] = []
    public var collections: [GameCollection]?
    public init(games: [Game] = [], collections: [GameCollection] = []) {
        self.games = games
        self.collections = collections
    }
}
public struct Bottle: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let configuration: [String: String]
    public init(name: String, path: String, configuration: [String: String]) {
        self.name = name
        self.path = path
        self.configuration = configuration
    }
}
public struct Runner: Codable, Sendable {
    public let appPath: String
    public let version: String
    public var executable: String { appPath + "/Contents/SharedSupport/CrossOver/bin/wine" }
    public init(appPath: String, version: String) {
        self.appPath = appPath
        self.version = version
    }
}
public struct LaunchCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let directory: String
}
public struct LaunchSession: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var gameID: UUID
    public var started = Date()
    public var runnerVersion: String
    public var bottleName: String
    public var status: String
    public var exitCode: Int32?
    public var logPath: String
    public init(gameID: UUID, runnerVersion: String, bottleName: String, status: String, logPath: String) {
        self.gameID = gameID
        self.runnerVersion = runnerVersion
        self.bottleName = bottleName
        self.status = status
        self.logPath = logPath
    }
}
public enum VNError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}
public enum Storage {
    public static func load(_ url: URL) throws -> LibraryDocument {
        if !FileManager.default.fileExists(atPath: url.path) { return LibraryDocument() }
        let doc = try JSONDecoder().decode(LibraryDocument.self, from: FileSafety.read(url, limit: 32 * 1024 * 1024))
        guard (1...LibraryDocument.currentVersion).contains(doc.version) else {
            throw VNError.message("资料版本较新，已停止写入。请使用匹配版本打开。")
        }
        guard doc.games.count <= 1000, Set(doc.games.map(\.id)).count == doc.games.count else {
            throw VNError.message("游戏库条目过多或包含重复 ID。")
        }
        try PersonalLibrary.validate(games: doc.games, collections: doc.collections ?? [])
        return doc
    }
    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
