import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import VNCore

private func transferFixture() throws -> URL {
    let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(
        "transfer-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func transferImage(_ root: URL) throws -> URL {
    let url = root.appendingPathComponent("fixture.png")
    let context = CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw VNError.message("fixture creation failed") }
    return url
}
private func transferManifest(_ root: URL, mutate: (inout [String: Any]) -> Void) throws {
    let url = root.appendingPathComponent("manifest.json")
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    mutate(&object)
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
}

@Test func transferV07RoundTripPreservesConfigurationAndArtworkLocks() throws {
    let root = try transferFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = try transferImage(root)
    var game = Game(title: "Example", executable: "/original/game.exe", workingDirectory: "/original")
    game.coverPath = image.path
    game.favorite = true
    game.state = .completed
    game.arguments = ["--flag"]
    game.bottleID = "/bottles/old"
    game.saveDirectory = "/saves"
    game.metadata = GameMetadata()
    game.metadata?.backgroundPath = image.path
    game.metadata?.wallpaperArtwork = ArtworkSelection(
        path: image.path, source: "manual", reason: "Keep", userLocked: true, horizontal: 0.2, vertical: 0.7, zoom: 1.8)
    game.metadata?.discArtwork = ArtworkSelection(
        path: image.path, source: "manual", reason: "Disc", userLocked: true, horizontal: 0.8)
    let bundle = root.appendingPathComponent("library.vncollection")
    let receipt = try LibraryTransfer.export(games: [game], to: bundle)
    #expect(receipt.exportedCount == 1)
    #expect(receipt.assetCount == 1)
    #expect(receipt.bytes > 0)
    let preview = try LibraryTransfer.preview(at: bundle)
    #expect(preview.games[0].coverPath?.hasPrefix("assets/") == true)
    let cache = root.appendingPathComponent("cache")
    let imported = try LibraryTransfer.importArtwork(from: preview, to: cache)
    var expected = game
    expected.bookmarks = []  // V4 export normalizes absent named bookmarks.
    expected.coverPath = imported[0].coverPath
    expected.metadata?.backgroundPath = imported[0].metadata?.backgroundPath
    expected.metadata?.wallpaperArtwork?.path = imported[0].metadata!.wallpaperArtwork!.path
    expected.metadata?.discArtwork?.path = imported[0].metadata!.discArtwork!.path
    #expect(imported == [expected])
    #expect(ArtworkQuality.size(imported[0].coverPath)?.width == 2)
    #expect(imported[0].coverPath == imported[0].metadata?.discArtwork?.path)
    let second = try LibraryTransfer.importArtwork(from: preview, to: cache)
    #expect(second[0].coverPath != imported[0].coverPath)
    #expect(try Data(contentsOf: URL(fileURLWithPath: imported[0].coverPath!)) == Data(contentsOf: image))
}

@Test func transferV07EmptyLibraryAndNoOverwrite() throws {
    let root = try transferFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = root.appendingPathComponent("empty")
    _ = try LibraryTransfer.export(games: [], to: bundle)
    #expect(try LibraryTransfer.preview(at: bundle).games.isEmpty)
    #expect(throws: (any Error).self) { try LibraryTransfer.export(games: [], to: bundle) }
    let marker = bundle.appendingPathComponent("marker")
    try Data("keep".utf8).write(to: marker)
    #expect(throws: (any Error).self) { try LibraryTransfer.export(games: [], to: bundle) }
    #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
    let linked = root.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: root)
    #expect(throws: (any Error).self) {
        try LibraryTransfer.export(games: [], to: linked.appendingPathComponent("new"))
    }
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: linked.appendingPathComponent("empty")) }
}

@Test func transferV07RejectsTraversalAbsolutePathsSymlinksAndHashTamper() throws {
    let root = try transferFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = try transferImage(root)
    var game = Game(title: "Game", executable: "/unused", workingDirectory: "/unused")
    game.coverPath = image.path
    for (index, malicious) in ["../fixture.png", image.path, "assets/../fixture.png"].enumerated() {
        let bundle = root.appendingPathComponent("bad-\(index)")
        _ = try LibraryTransfer.export(games: [game], to: bundle)
        try transferManifest(bundle) { object in
            var games = object["games"] as! [[String: Any]]
            games[0]["coverPath"] = malicious
            object["games"] = games
        }
        #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
    }
    let bundle = root.appendingPathComponent("tamper")
    _ = try LibraryTransfer.export(games: [game], to: bundle)
    let preview = try LibraryTransfer.preview(at: bundle)
    let asset = bundle.appendingPathComponent(preview.games[0].coverPath!)
    try Data("not image".utf8).write(to: asset)
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
    #expect(throws: (any Error).self) {
        try LibraryTransfer.importArtwork(from: preview, to: root.appendingPathComponent("cache"))
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cache").path))
    try FileManager.default.removeItem(at: asset)
    try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: image)
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
    game.coverPath = asset.path
    #expect(throws: (any Error).self) {
        try LibraryTransfer.export(games: [game], to: root.appendingPathComponent("linked-export"))
    }
}

@Test func transferV07RejectsChangedPreviewVersionsDuplicatesAndBounds() throws {
    let root = try transferFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let game = Game(title: "Game", executable: "/unused", workingDirectory: "/unused")
    let bundle = root.appendingPathComponent("changed")
    _ = try LibraryTransfer.export(games: [game], to: bundle)
    let preview = try LibraryTransfer.preview(at: bundle)
    try transferManifest(bundle) { object in
        var games = object["games"] as! [[String: Any]]
        games[0]["title"] = "changed"
        object["games"] = games
    }
    #expect(throws: (any Error).self) {
        try LibraryTransfer.importArtwork(from: preview, to: root.appendingPathComponent("cache"))
    }
    #expect(try LibraryTransfer.preview(at: bundle).games[0].title == "changed")
    try transferManifest(bundle) { $0["version"] = 99 }
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
    #expect(throws: (any Error).self) {
        try LibraryTransfer.export(games: [game, game], to: root.appendingPathComponent("duplicate"))
    }
    #expect(throws: (any Error).self) {
        try LibraryTransfer.export(
            games: Array(repeating: game, count: 1001), to: root.appendingPathComponent("too-many"))
    }
    try transferManifest(bundle) { object in
        object["version"] = 1
        object["games"] = Array(repeating: (object["games"] as! [Any])[0], count: 1001)
    }
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
    try Data(repeating: 32, count: 8 * 1024 * 1024 + 1).write(to: bundle.appendingPathComponent("manifest.json"))
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
}

@Test func transferV07RejectsNonImagesExtraFilesAndDeclaredAssetBounds() throws {
    let root = try transferFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let bad = root.appendingPathComponent("game.exe")
    try Data("MZ executable".utf8).write(to: bad)
    var game = Game(title: "Game", executable: bad.path, workingDirectory: root.path)
    game.coverPath = bad.path
    #expect(throws: (any Error).self) {
        try LibraryTransfer.export(games: [game], to: root.appendingPathComponent("bad"))
    }
    game.coverPath = try transferImage(root).path
    let bundle = root.appendingPathComponent("good")
    _ = try LibraryTransfer.export(games: [game], to: bundle)
    let extra = bundle.appendingPathComponent("secret.key")
    try Data("extra".utf8).write(to: extra)
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
    try FileManager.default.removeItem(at: extra)
    try transferManifest(bundle) { object in
        var assets = object["assets"] as! [[String: Any]]
        assets[0]["bytes"] = 8 * 1024 * 1024 + 1
        object["assets"] = assets
    }
    #expect(throws: (any Error).self) { try LibraryTransfer.preview(at: bundle) }
}
