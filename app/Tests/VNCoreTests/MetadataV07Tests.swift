import Foundation
import Testing

@testable import VNCore

private func candidateV07(_ id: String, name: String = "New") -> MetadataResult {
    var result = MetadataResult()
    result.title = name
    result.metadata.identity = MetadataIdentity(steamAppID: id, name: name)
    result.metadata.originalTitle = name
    result.metadata.summary = "Public summary"
    result.metadata.publisher = "Public studio"
    result.metadata.titleSource = "https://store.steampowered.com/app/" + id
    result.metadata.detailSource = result.metadata.titleSource
    return result
}
@Test func metadataV07IdentityNeverChangesLaunchConfigurationAndRejectsLateResults() throws {
    var game = Game(title: "Local game", executable: "/local.exe", workingDirectory: "/local")
    game.kind = .steam
    game.steamAppID = "111"
    game.arguments = ["-flag"]
    game.bottleID = "/bottle"
    game.metadata = GameMetadata()
    game.metadata?.summary = "Old"
    let matched = try MetadataEditing.rematch(
        candidateV07("222"), fields: [.title, .summary], includeArtwork: false, into: game)
    #expect(matched.metadataSteamID == "222")
    #expect(matched.steamAppID == "111")
    #expect(matched.executable == game.executable)
    #expect(matched.arguments == game.arguments)
    #expect(matched.bottleID == game.bottleID)
    #expect(MetadataService.merge(candidateV07("111"), into: matched, imported: game) == matched)
    var independent = game
    independent.kind = .executable
    independent.steamAppID = ""
    #expect(
        try MetadataEditing.rematch(candidateV07("222"), fields: [.title], includeArtwork: false, into: independent)
            .kind == .executable)
}
@Test func metadataV07ManualFieldsAndExplicitEmptySurviveAutomaticRefresh() throws {
    var game = Game(title: "Initial", executable: "/a", workingDirectory: "/")
    game.kind = .steam
    game.steamAppID = "111"
    let edited = try MetadataEditing.manual([.title: "My name", .summary: "", .publisher: "My studio"], in: game)
    let refreshed = MetadataService.merge(candidateV07("111"), into: edited, imported: edited)
    #expect(refreshed.displayTitle == "My name")
    #expect(refreshed.metadata?.summary == "")
    #expect(refreshed.metadata?.publisher == "My studio")
    #expect(refreshed.metadataOrigin(.summary).manual)
    let adopted = try MetadataEditing.rematch(
        candidateV07("111"), fields: [.summary], includeArtwork: false, into: refreshed)
    #expect(adopted.metadata?.summary == "Public summary")
    #expect(!adopted.metadataOrigin(.summary).manual)
    #expect(adopted.displayTitle == "My name")
}
@Test func metadataV07SourcePriorityAndLegacyManualTitle() throws {
    var game = Game(title: "Public", executable: "/a", workingDirectory: "/")
    game.kind = .steam
    game.steamAppID = "111"
    game = MetadataService.merge(candidateV07("111"), into: game, imported: game)
    var local = MetadataResult()
    local.title = "Local ini"
    local.metadata.titleSource = "本地 Game.ini"
    #expect(MetadataService.merge(local, into: game, imported: game).displayTitle == "New")
    game.title = "Legacy manual"
    game.metadata?.titleSource = "手动编辑"
    #expect(MetadataService.merge(candidateV07("111"), into: game, imported: game).displayTitle == "Legacy manual")
    for input in [
        "0", "https://store.steampowered.com.evil.example/app/111", "https://user@store.steampowered.com/app/111",
        "111&x=1", "http://store.steampowered.com/app/111",
    ] { #expect(throws: (any Error).self) { try MetadataEditing.steamID(from: input) } }
    #expect(try MetadataEditing.steamID(from: " https://store.steampowered.com/app/111/title/?l=schinese ") == "111")
}
@Test func metadataV07RematchDropsOldAutomaticArtworkButKeepsManual() throws {
    var game = Game(title: "Old", executable: "/a", workingDirectory: "/")
    game.kind = .steam
    game.steamAppID = "111"
    game.coverPath = "/old-cover"
    game.metadata = GameMetadata()
    game.metadata?.summary = "Old summary"
    game.metadata?.publisher = "Old publisher"
    game.metadata?.discArtwork = ArtworkSelection(path: "/manual", source: "manual", reason: "", userLocked: true)
    game.metadata?.wallpaperArtwork = ArtworkSelection(path: "/automatic", source: "auto", reason: "")
    let changed = try MetadataEditing.rematch(candidateV07("222"), fields: [.title], includeArtwork: false, into: game)
    #expect(changed.coverPath == nil)
    #expect(changed.metadata?.summary == nil)
    #expect(changed.metadata?.publisher == nil)
    #expect(changed.metadata?.chosenWallpaper == nil)
    #expect(changed.metadata?.discArtwork == game.metadata?.discArtwork)
}
@Test func metadataV07HistoryRestoresOnlyMetadataAndIsBounded() throws {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("history.json")
    var game = Game(title: "Old", executable: "/old", workingDirectory: "/old")
    let revision = MetadataRevision(game: game, reason: "fixture")
    game.title = "New"
    game.executable = "/new"
    game.favorite = true
    let restored = revision.restoring(into: game)
    #expect(restored.title == "Old")
    #expect(restored.executable == "/new")
    #expect(restored.favorite)
    for index in 0..<15 { try MetadataHistory.record(game, reason: "change \(index)", at: url) }
    #expect(try MetadataHistory.load(at: url).count == 12)
    try Data("corrupt".utf8).write(to: url)
    #expect(throws: (any Error).self) { try MetadataHistory.record(game, reason: "blocked", at: url) }
    #expect(try String(contentsOf: url, encoding: .utf8) == "corrupt")
}
@Test func metadataV07LibraryMergePreservesLaunchAndUndoProtectsLaterEdits() throws {
    var local = Game(title: "Local", executable: "/current", workingDirectory: "/current")
    local.arguments = ["keep"]
    local.bottleID = "current"
    local.saveDirectory = "/save"
    var incoming = local
    incoming.title = "Imported"
    incoming.executable = "/other"
    incoming.arguments = ["replace"]
    incoming.favorite = true
    let merged = LibraryMerge.apply([incoming], to: [local], mode: .updateDetails)
    #expect(merged.updated == 1)
    #expect(merged.games[0].title == "Imported")
    #expect(merged.games[0].favorite)
    #expect(merged.games[0].executable == local.executable)
    #expect(merged.games[0].arguments == local.arguments)
    #expect(merged.games[0].saveDirectory == local.saveDirectory)
    #expect(LibraryMerge.apply([incoming], to: [local], mode: .addOnly).games == [local])
    #expect(try LibraryMerge.undo(before: [local], after: merged.games, current: merged.games) == [local])
    var changed = merged.games
    changed[0].alias = "Newer edit"
    #expect(throws: (any Error).self) { try LibraryMerge.undo(before: [local], after: merged.games, current: changed) }
}
