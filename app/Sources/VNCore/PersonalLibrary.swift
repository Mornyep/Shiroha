import Foundation

public struct PlayBookmark: Codable, Equatable, Sendable {
    public var chapter: String
    public var route: String
    public var note: String
    public var nextStep: String
    public var hidesSpoilers: Bool
    public var updatedAt: Date
    public init(
        chapter: String = "", route: String = "", note: String = "", nextStep: String = "", hidesSpoilers: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.chapter = chapter
        self.route = route
        self.note = note
        self.nextStep = nextStep
        self.hidesSpoilers = hidesSpoilers
        self.updatedAt = updatedAt
    }
    public var isEmpty: Bool {
        [chapter, route, note, nextStep].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
public struct NamedBookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var value: PlayBookmark
    public init(id: UUID = UUID(), name: String, value: PlayBookmark = PlayBookmark()) {
        self.id = id
        self.name = name
        self.value = value
    }
}

extension Game {
    public var allBookmarks: [NamedBookmark] {
        // Keep the original single bookmark addressable without rewriting older libraries on load.
        let original = bookmark.map { [NamedBookmark(id: id, name: "原有书签", value: $0)] } ?? []
        return original + (bookmarks ?? [])
    }
}

public struct GameCollection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public enum PersonalLibrary {
    public static func nameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func validate(games: [Game], collections: [GameCollection]) throws {
        guard collections.count <= 100, Set(collections.map(\.id)).count == collections.count,
            Set(collections.map { nameKey($0.name) }).count == collections.count,
            collections.allSatisfy({
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40
            })
        else { throw VNError.message("收藏集名称不能为空或重复，最多 40 字、100 个收藏集。") }
        let ids = Set(collections.map(\.id))
        for game in games {
            if let profiles = game.metadata?.publicProfiles {
                guard profiles.count <= 2, Set(profiles.map(\.source)).count == profiles.count,
                    profiles.allSatisfy({ profile in
                        profile.source.validID(profile.sourceID) && profile.title.count <= 300
                            && profile.originalTitle.count <= 300 && profile.summary.count <= 8000
                            && profile.released.count <= 40 && profile.votes >= 0
                            && (profile.score.map { $0.isFinite && $0 > 0 && $0 <= 10 } ?? true)
                    })
                else { throw VNError.message("公开来源资料格式无效。") }
            }
            if let progress = game.progress { try PlayProgress.validate(progress) }
            let membership = game.collectionIDs ?? []
            guard membership.count <= 100, Set(membership).count == membership.count, Set(membership).isSubset(of: ids)
            else { throw VNError.message("作品包含无效的收藏集关联。") }
            let bookmarks = game.allBookmarks
            guard bookmarks.count <= 50, Set(bookmarks.map(\.id)).count == bookmarks.count,
                bookmarks.allSatisfy({
                    !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80
                })
            else {
                throw VNError.message("每部作品最多 50 个书签，名称最多 80 字，且 ID 不可重复。")
            }
            for item in bookmarks {
                let bookmark = item.value
                guard bookmark.chapter.count <= 120, bookmark.route.count <= 120, bookmark.note.count <= 2000,
                    bookmark.nextStep.count <= 1000
                else { throw VNError.message("书签内容过长：章节和路线各 120 字，笔记 2000 字，下次计划 1000 字。") }
            }
        }
    }
    /// Names identify equivalent collections across independently created libraries.
    /// A UUID collision with a different name receives a fresh ID; local membership is untouched.
    public static func mergeCollections(_ incoming: [GameCollection], into existing: [GameCollection], games: [Game])
        throws -> (collections: [GameCollection], games: [Game])
    {
        try validate(games: games, collections: incoming)
        var result = existing
        var mapping: [UUID: UUID] = [:]
        for item in incoming {
            if let match = result.first(where: { nameKey($0.name) == nameKey(item.name) }) {
                mapping[item.id] = match.id
            } else {
                let id = result.contains(where: { $0.id == item.id }) ? UUID() : item.id
                result.append(GameCollection(id: id, name: item.name))
                mapping[item.id] = id
            }
        }
        let remapped = games.map { game in
            var copy = game
            if let ids = game.collectionIDs { copy.collectionIDs = ids.compactMap { mapping[$0] } }
            return copy
        }
        try validate(games: remapped, collections: result)
        return (result, remapped)
    }
    public static func removingCollection(_ id: UUID, games: [Game]) -> [Game] {
        games.map { game in
            var copy = game
            copy.collectionIDs = game.collectionIDs?.filter { $0 != id }
            return copy
        }
    }
}
