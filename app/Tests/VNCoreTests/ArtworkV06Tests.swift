import Foundation
import Testing

@testable import VNCore

@Test func oldMetadataDoesNotPromoteUnreviewedScreenshotOrCover() throws {
    let old = try JSONDecoder().decode(
        GameMetadata.self,
        from: Data(#"{"backgroundPath":"/hud.jpg","backgroundSource":"Steam","artworkRevision":5}"#.utf8))
    #expect(old.chosenWallpaper == nil)
    #expect(old.discArtwork == nil)
    var manual = old
    manual.backgroundSource = "手动选择"
    #expect(manual.chosenWallpaper?.path == "/hud.jpg")
    #expect(manual.chosenWallpaper?.userLocked == true)
    #expect(manual.discArtwork == nil)
}
@Test func independentArtworkLocksSurviveRefreshAndRoundTrip() throws {
    var game = Game(title: "Title", executable: "/unused", workingDirectory: "/unused")
    game.metadata = GameMetadata()
    game.metadata?.discArtwork = ArtworkSelection(
        path: "/manual-disc.jpg", source: "手动选择", reason: "", userLocked: true, horizontal: 0.7)
    var incoming = MetadataResult()
    incoming.metadata.artworkRevision = 6
    incoming.metadata.discArtwork = ArtworkSelection(path: "/auto-disc.jpg", source: "official", reason: "")
    incoming.metadata.wallpaperArtwork = ArtworkSelection(path: "/auto-wall.jpg", source: "official", reason: "")
    let updated = MetadataService.merge(incoming, into: game, imported: game)
    #expect(updated.metadata?.discArtwork == game.metadata?.discArtwork)
    #expect(updated.metadata?.chosenWallpaper?.path == "/auto-wall.jpg")
    let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(updated))
    #expect(decoded == updated)
    var stale = incoming
    stale.metadata.artworkRevision = 5
    stale.metadata.wallpaperArtwork?.path = "/stale.jpg"
    #expect(
        MetadataService.merge(stale, into: updated, imported: game).metadata?.chosenWallpaper?.path == "/auto-wall.jpg")
}
@Test func cropValuesRemainBoundedAndCatalogIsExplicit() {
    let art = ArtworkSelection(path: "", source: "", reason: "", horizontal: -.infinity, vertical: 9, zoom: .nan)
    #expect(art.horizontal == 0.5)
    #expect(art.vertical == 1)
    #expect(art.safeZoom == 1)
    #expect(ArtworkCatalog.entries["unknown"] == nil)
    #expect(ArtworkCatalog.entries.count == 6)
    for item in ArtworkCatalog.entries.values {
        #expect(MetadataService.allowedImageURL(URL(string: item.wallpaperURL)!))
        #expect(MetadataService.allowedImageURL(URL(string: item.discURL)!))
    }
    #expect(!MetadataService.allowedImageURL(URL(string: "https://www.dramaticcreate.com/other.jpg")!))
    #expect(!MetadataService.allowedImageURL(URL(string: "https://steinsgate.jp/reboot/other.jpg")!))
}
