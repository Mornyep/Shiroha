import Foundation
import Testing

@testable import VNCore

@Test func v03OldMetadataAndOriginalTitleAreCompatible() throws {
    let metadata = try JSONDecoder().decode(GameMetadata.self, from: Data(#"{"summary":"Existing"}"#.utf8))
    #expect(metadata.localizedTitle == nil)
    #expect(metadata.backgroundPath == nil)
    var game = Game(title: "WITCH ON THE HOLY NIGHT", executable: "/unused", workingDirectory: "/unused")
    game.kind = .steam
    game.steamAppID = "2052410"
    game.metadata = metadata
    let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
    #expect(decoded.displayTitle == "魔法使之夜")
    #expect(decoded.searchableTitle.contains("WITCH ON THE HOLY NIGHT"))
    game.title = "我的命名"
    game.metadata?.titleSource = "手动编辑"
    #expect(game.displayTitle == "我的命名")
    var unknown = game
    unknown.metadata = nil
    unknown.steamAppID = "123"
    #expect(unknown.displayTitle == "我的命名")
}
@Test func v03SteamChineseSourceArtworkAndManualMerge() throws {
    let fixture = Data(
        #"{"2052410":{"success":true,"data":{"name":"WITCH ON THE HOLY NIGHT","background_raw":"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2052410/bg.jpg","screenshots":[{"path_full":"https://evil.example/a.jpg"},{"path_full":"https://cdn.akamai.steamstatic.com/a.jpg"}]}}}"#
            .utf8)
    let result = try MetadataService.parseSteam(fixture, appID: "2052410").result
    #expect(result.metadata.localizedTitle == "魔法使之夜")
    #expect(result.metadata.localizedTitleSource == LocalizedMetadata.steamTitle(appID: "2052410")?.source)
    #expect(result.metadata.originalTitle == "WITCH ON THE HOLY NIGHT")
    #expect(result.metadata.backgroundURL?.contains("steamstatic.com") == true)
    #expect(result.metadata.screenshotURLs?.count == 1)
    var manual = Game(title: "My title", executable: "/unused", workingDirectory: "/unused")
    manual.metadata = GameMetadata()
    manual.metadata?.titleSource = "手动编辑"
    manual.metadata?.backgroundPath = "/manual.png"
    manual.metadata?.backgroundSource = "手动选择"
    var remote = result
    remote.metadata.backgroundPath = "/download.jpg"
    remote.metadata.backgroundSource = result.metadata.backgroundURL
    let merged = MetadataService.merge(remote, into: manual, imported: manual)
    #expect(merged.title == manual.title)
    #expect(merged.displayTitle == manual.title)
    #expect(merged.metadata?.backgroundPath == "/manual.png")
    #expect(merged.metadata?.backgroundSource == "手动选择")
}
@Test func v03ArtworkHostsAndLocalHeroPrecedence() throws {
    for value in [
        "http://cdn.akamai.steamstatic.com/a.jpg", "https://steamstatic.com.evil.example/a.jpg",
        "https://user@steamstatic.com/a.jpg", "https://steamstatic.com:444/a.jpg",
        "https://store.steampowered.com/a.jpg",
    ] {
        #expect(!MetadataService.allowedImageURL(URL(string: value)!))
    }
    #expect(MetadataService.allowedImageURL(URL(string: "https://shared.fastly.steamstatic.com/a.jpg")!))
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cache) }
    let hero = cache.appendingPathComponent("2052410_library_hero.jpg")
    try Data([0xff, 0xd8, 0xff]).write(to: hero)
    #expect(MetadataService.localSteamBackground(cache: cache, appID: "2052410") == hero)
    #expect(MetadataService.localSteamBackground(cache: cache, appID: "../2052410") == nil)
    var game = Game(title: "Original", executable: "/unused", workingDirectory: "/unused")
    game.metadata = GameMetadata()
    game.metadata?.backgroundPath = hero.path
    game.metadata?.backgroundSource = "本机 Steam librarycache"
    var remote = MetadataResult()
    remote.metadata.backgroundPath = "/network.jpg"
    remote.metadata.backgroundSource = "https://shared.fastly.steamstatic.com/a.jpg"
    #expect(MetadataService.merge(remote, into: game, imported: game).metadata?.backgroundPath == hero.path)
}

@Test func v06ReviewedBackgroundUpgradePreservesManualAndRejectsOlderRefresh() {
    var game = Game(title: "Artwork", executable: "/unused", workingDirectory: "/unused")
    game.metadata = GameMetadata()
    game.metadata?.backgroundPath = "/old-hero.jpg"
    game.metadata?.artworkRevision = 3
    var result = MetadataResult()
    result.metadata.backgroundPath = "/landscape-scene.jpg"
    result.metadata.backgroundSource = "Steam official screenshot"
    result.metadata.artworkRevision = 6
    result.metadata.wallpaperArtwork = ArtworkSelection(
        path: "/landscape-scene.jpg", source: "Reviewed official", reason: "Clean scene")
    let updated = MetadataService.merge(result, into: game, imported: game)
    #expect(updated.metadata?.backgroundPath == "/landscape-scene.jpg")
    var old = MetadataResult()
    old.metadata.backgroundPath = "/old-hero.jpg"
    #expect(
        MetadataService.merge(old, into: updated, imported: updated).metadata?.backgroundPath == "/landscape-scene.jpg")
    game.metadata?.backgroundSource = "手动选择"
    #expect(MetadataService.merge(result, into: game, imported: game).metadata?.backgroundPath == "/old-hero.jpg")
}
