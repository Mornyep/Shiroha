import Foundation

public enum LibraryMergeMode: String, CaseIterable, Sendable {
    case addOnly = "只添加新作品"
    case updateDetails = "同时更新已有作品的资料"
}
public struct LibraryMergeResult: Sendable {
    public var games: [Game]
    public var added: Int
    public var updated: Int
    public var skipped: Int
}
public enum LibraryMerge {
    public static func existingIndex(for incoming: Game, in games: [Game]) -> Int? {
        if let index = games.firstIndex(where: { $0.id == incoming.id }) { return index }
        return games.firstIndex {
            !$0.executable.isEmpty && $0.executable == incoming.executable
                && $0.workingDirectory == incoming.workingDirectory && $0.kind == incoming.kind
                && $0.steamAppID == incoming.steamAppID && $0.bottleID == incoming.bottleID
        }
    }
    public static func apply(_ incoming: [Game], to existing: [Game], mode: LibraryMergeMode) -> LibraryMergeResult {
        var games = existing
        var added = 0
        var updated = 0
        var skipped = 0
        for item in incoming {
            if let index = existingIndex(for: item, in: games) {
                if mode == .addOnly {
                    skipped += 1
                    continue
                }
                var current = games[index]
                current.title = item.title
                current.coverPath = item.coverPath
                current.metadata = item.metadata
                if let progress = item.progress { current.progress = progress }
                // V4 sends the complete bookmark state, including an empty list. Older packages omit it.
                if let bookmarks = item.bookmarks {
                    current.bookmarks = bookmarks
                    current.bookmark = item.bookmark
                } else if let bookmark = item.bookmark {
                    current.bookmark = bookmark
                }
                if let ids = item.collectionIDs { current.collectionIDs = ids }
                current.alias = item.alias
                current.series = item.series
                current.favorite = item.favorite
                current.state = item.state
                games[index] = current
                updated += 1
            } else {
                games.append(item)
                added += 1
            }
        }
        return LibraryMergeResult(games: games, added: added, updated: updated, skipped: skipped)
    }
    public static func undo(before: [Game], after: [Game], current: [Game]) throws -> [Game] {
        guard current == after else { throw VNError.message("导入后游戏库又有修改，已停止撤销以保留新内容。导入前副本仍保存在本机。") }
        return before
    }
}
