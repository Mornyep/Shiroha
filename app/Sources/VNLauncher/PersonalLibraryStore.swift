import Foundation
import VNCore

extension LibraryStore {
    /// Persist first, so a failed disk write cannot appear as a successful personal edit.
    func commitPersonalLibrary(games proposed: [Game], collections catalog: [GameCollection]) throws {
        guard writable else { throw VNError.message("游戏库当前不可写。") }
        try PersonalLibrary.validate(games: proposed, collections: catalog)
        try Storage.save(
            LibraryDocument(games: proposed, collections: catalog), to: root.appendingPathComponent("library.json"))
        games = proposed
        collections = catalog
    }
    func saveNamedBookmark(_ bookmark: NamedBookmark, gameID: UUID) throws {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { throw VNError.message("作品已移除。") }
        var proposed = games
        if bookmark.id == gameID, proposed[index].bookmark != nil {
            proposed[index].bookmark = nil
            proposed[index].bookmarks = (proposed[index].bookmarks ?? []) + [bookmark]
        } else {
            var saved = proposed[index].bookmarks ?? []
            if let existing = saved.firstIndex(where: { $0.id == bookmark.id }) {
                saved[existing] = bookmark
            } else {
                saved.append(bookmark)
            }
            proposed[index].bookmarks = saved
        }
        try commitPersonalLibrary(games: proposed, collections: collections)
    }
    func removeBookmark(_ id: UUID, gameID: UUID) throws {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { throw VNError.message("作品已移除。") }
        var proposed = games
        try Storage.save(
            LibraryDocument(games: games, collections: collections),
            to: root.appendingPathComponent("LibraryBackups/bookmark-\(UUID().uuidString).json"))
        if id == gameID { proposed[index].bookmark = nil }
        proposed[index].bookmarks = (proposed[index].bookmarks ?? []).filter { $0.id != id }
        try commitPersonalLibrary(games: proposed, collections: collections)
    }
    func saveMembership(_ ids: Set<UUID>, gameID: UUID) throws {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { throw VNError.message("作品已移除。") }
        var proposed = games
        proposed[index].collectionIDs = collections.filter { ids.contains($0.id) }.map(\.id)
        try commitPersonalLibrary(games: proposed, collections: collections)
    }
    @discardableResult func createCollection(_ name: String) throws -> UUID {
        let collection = GameCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        try commitPersonalLibrary(games: games, collections: collections + [collection])
        return collection.id
    }
    func renameCollection(_ id: UUID, to name: String) throws {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { throw VNError.message("收藏集已移除。") }
        var catalog = collections
        catalog[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try commitPersonalLibrary(games: games, collections: catalog)
    }
    func removeCollection(_ id: UUID) throws {
        // Keep a complete local snapshot before removing the grouping or its links.
        guard writable else { throw VNError.message("游戏库当前不可写。") }
        try Storage.save(
            LibraryDocument(games: games, collections: collections),
            to: root.appendingPathComponent("LibraryBackups/collection-\(UUID().uuidString).json"))
        try commitPersonalLibrary(
            games: PersonalLibrary.removingCollection(id, games: games), collections: collections.filter { $0.id != id }
        )
    }
}
