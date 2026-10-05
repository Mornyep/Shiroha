import Foundation
import Testing

@testable import VNCore

private func personalRoot() throws -> URL {
    let root = URL(fileURLWithPath: "/private/tmp/personal-library-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func v11LegacyLibraryLoadsWithoutPersonalFieldsAndWritesCurrentVersion() throws {
    let root = try personalRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let game = Game(title: "Old", executable: "/original.exe", workingDirectory: "/old")
    let data = try JSONEncoder().encode(LibraryDocument(games: [game]))
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    json["version"] = 1
    json.removeValue(forKey: "collections")
    let url = root.appendingPathComponent("library.json")
    try JSONSerialization.data(withJSONObject: json).write(to: url)
    let old = try Storage.load(url)
    #expect(old.games == [game])
    #expect(old.collections == nil)
    #expect(old.games[0].bookmark == nil)
    try Storage.save(LibraryDocument(games: old.games, collections: []), to: url)
    #expect(try Storage.load(url).version == LibraryDocument.currentVersion)
}

@Test func v11BookmarkCollectionsAndEmptyCollectionSurvivePortableRoundTrip() throws {
    let root = try personalRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = GameCollection(name: "Next")
    let b = GameCollection(name: "日语阅读")
    let empty = GameCollection(name: "空收藏集")
    var game = Game(title: "Story", executable: "/a/game.exe", workingDirectory: "/a")
    game.collectionIDs = [a.id, b.id]
    game.bookmark = PlayBookmark(chapter: "第二章", route: "共通线", note: "停在雨夜", nextStep: "看下一节", hidesSpoilers: true)
    let package = root.appendingPathComponent("portable")
    _ = try LibraryTransfer.export(games: [game], collections: [a, b, empty], to: package)
    let preview = try LibraryTransfer.preview(at: package)
    game.bookmarks = []  // V4 explicitly carries an empty named-bookmark state.
    #expect(preview.collections == [a, b, empty])
    #expect(preview.games == [game])
    let imported = try LibraryTransfer.importArtwork(from: preview, to: root.appendingPathComponent("cache"))
    #expect(imported[0].bookmark == game.bookmark)
    #expect(imported[0].collectionIDs == [a.id, b.id])
}

@Test func v11CollectionMergeMapsNamesAndResolvesUUIDCollision() throws {
    let local = GameCollection(name: "Next")
    let collision = GameCollection(name: "Existing")
    let sameName = GameCollection(name: " next ")
    let incomingCollision = GameCollection(id: collision.id, name: "Different")
    var game = Game(title: "New", executable: "", workingDirectory: "")
    game.collectionIDs = [sameName.id, incomingCollision.id]
    let merged = try PersonalLibrary.mergeCollections(
        [sameName, incomingCollision], into: [local, collision], games: [game])
    #expect(merged.collections.count == 3)
    #expect(merged.games[0].collectionIDs?.first == local.id)
    #expect(merged.games[0].collectionIDs?.last != collision.id)
    #expect(merged.collections[1] == collision)
    try PersonalLibrary.validate(games: merged.games, collections: merged.collections)
}

@Test func v11RemovingCollectionKeepsGamesBookmarksAndOtherMemberships() {
    let a = GameCollection(name: "A")
    let b = GameCollection(name: "B")
    var game = Game(title: "Keep", executable: "/keep.exe", workingDirectory: "/keep")
    game.collectionIDs = [a.id, b.id]
    game.bookmark = PlayBookmark(note: "keep")
    let result = PersonalLibrary.removingCollection(a.id, games: [game])
    #expect(result.count == 1)
    #expect(result[0].collectionIDs == [b.id])
    #expect(result[0].bookmark == game.bookmark)
    #expect(result[0].executable == game.executable)
    #expect(result[0].id == game.id)
}

@Test func v11PersonalDataRejectsDuplicateNamesDanglingLinksAndOversizedNotes() throws {
    let a = GameCollection(name: "ＡＢＣ")
    let b = GameCollection(name: "abc")
    #expect(throws: (any Error).self) { try PersonalLibrary.validate(games: [], collections: [a, b]) }
    var game = Game(title: "Game", executable: "", workingDirectory: "")
    game.collectionIDs = [UUID()]
    #expect(throws: (any Error).self) { try PersonalLibrary.validate(games: [game], collections: [a]) }
    game.collectionIDs = [a.id]
    game.bookmark = PlayBookmark(note: String(repeating: "字", count: 2001))
    #expect(throws: (any Error).self) { try PersonalLibrary.validate(games: [game], collections: [a]) }
    let root = try personalRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: (any Error).self) {
        try LibraryTransfer.export(games: [game], collections: [a], to: root.appendingPathComponent("bad"))
    }
}

@Test func v11OldImportDoesNotEraseLocalBookmarkOrCollections() {
    var local = Game(title: "Local", executable: "/local", workingDirectory: "/")
    local.bookmark = PlayBookmark(note: "Personal")
    local.collectionIDs = [UUID()]
    var incoming = local
    incoming.bookmark = nil
    incoming.collectionIDs = nil
    incoming.title = "Updated"
    let result = LibraryMerge.apply([incoming], to: [local], mode: .updateDetails)
    #expect(result.games[0].bookmark == local.bookmark)
    #expect(result.games[0].collectionIDs == local.collectionIDs)
    incoming.bookmark = PlayBookmark(note: "Imported")
    incoming.collectionIDs = []
    let explicit = LibraryMerge.apply([incoming], to: [local], mode: .updateDetails)
    #expect(explicit.games[0].bookmark == incoming.bookmark)
    #expect(explicit.games[0].collectionIDs == [])
}

@Test func v11BookmarkEditAfterImportPreventsUndoClobbering() throws {
    let before = Game(title: "Local", executable: "/local", workingDirectory: "/")
    var after = before
    after.bookmark = PlayBookmark(note: "Imported")
    var current = after
    current.bookmark?.note = "New personal edit"
    #expect(throws: (any Error).self) { try LibraryMerge.undo(before: [before], after: [after], current: [current]) }
    #expect(try LibraryMerge.undo(before: [before], after: [after], current: [after]) == [before])
}

@Test func v11TransferRejectsUnregisteredCollectionBeforeImport() throws {
    let root = try personalRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let game = Game(title: "Test", executable: "", workingDirectory: "")
    let package = root.appendingPathComponent("package")
    _ = try LibraryTransfer.export(games: [game], to: package)
    let url = package.appendingPathComponent("manifest.json")
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var games = object["games"] as! [[String: Any]]
    games[0]["collectionIDs"] = [UUID().uuidString]
    object["games"] = games
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: package) }
}
