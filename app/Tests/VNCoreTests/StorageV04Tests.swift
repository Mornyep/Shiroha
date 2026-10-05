import Foundation
import Testing

@testable import VNCore

private func storageFixture() throws -> (URL, Game) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VNStorageTests-" + UUID().uuidString)
    let gameRoot = root.appendingPathComponent("Game")
    let saves = gameRoot.appendingPathComponent("savedata")
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    try Data("fixture exe".utf8).write(to: gameRoot.appendingPathComponent("game.exe"))
    try Data("important save".utf8).write(to: saves.appendingPathComponent("slot1.dat"))
    try Data("hidden persistent save".utf8).write(to: saves.appendingPathComponent(".persistent"))
    return (
        root,
        Game(
            title: "Fixture", executable: gameRoot.appendingPathComponent("game.exe").path,
            workingDirectory: gameRoot.path)
    )
}
@Test func v04SaveBackupIncludesHiddenFilesAndDetectsTampering() throws {
    let (root, game) = try storageFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let scan = try StorageManagement.scan(game: game, library: [game])
    #expect(scan.candidates.count == 1)
    #expect(scan.candidates[0].fileCount == 2)
    let receipt = try StorageManagement.archive(scan, to: root.appendingPathComponent("Archive"))
    #expect(receipt.archives[0].manifest.hashes[".persistent"] != nil)
    try StorageManagement.verifyBeforeUninstall(receipt: receipt, game: game, library: [game])
    let target = URL(fileURLWithPath: receipt.archives[0].destination).appendingPathComponent("slot1.dat")
    try Data("corrupt".utf8).write(to: target)
    #expect(throws: (any Error).self) {
        try StorageManagement.verifyBeforeUninstall(receipt: receipt, game: game, library: [game])
    }
    #expect(FileManager.default.fileExists(atPath: game.executable))
}
@Test func v04CleanupRejectsSharedRootSymlinksAndChangedFiles() throws {
    let (root, game) = try storageFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let other = Game(title: "other", executable: game.executable, workingDirectory: game.workingDirectory)
    #expect(throws: (any Error).self) { try StorageManagement.scan(game: game, library: [game, other]) }
    let scan = try StorageManagement.scan(game: game, library: [game])
    #expect(throws: (any Error).self) {
        try StorageManagement.archive(
            scan, to: URL(fileURLWithPath: game.workingDirectory).appendingPathComponent("unsafeBackup"))
    }
    let receipt = try StorageManagement.archive(scan, to: root.appendingPathComponent("Archive"))
    try Data("changed game".utf8).write(to: URL(fileURLWithPath: game.executable))
    #expect(throws: (any Error).self) {
        try StorageManagement.verifyBeforeUninstall(receipt: receipt, game: game, library: [game])
    }
    try FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: game.workingDirectory).appendingPathComponent("link"), withDestinationURL: root)
    #expect(throws: (any Error).self) { try StorageManagement.scan(game: game, library: [game]) }
}
@Test func v04SteamManifestIdentityMustMatchBeforeCleanup() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VNSteamStorage-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let install = root.appendingPathComponent("steamapps/common/Game")
    try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
    var game = Game(
        title: "test", executable: root.appendingPathComponent("steam.exe").path, workingDirectory: install.path)
    game.kind = .steam
    game.steamAppID = "123"
    let manifest = root.appendingPathComponent("steamapps/appmanifest_123.acf")
    try Data(#""appid" "999" "installdir" "Game""#.utf8).write(to: manifest)
    #expect(throws: (any Error).self) { try StorageManagement.validateRoot(game: game, library: [game]) }
    try Data(#""appid" "123" "installdir" "Game""#.utf8).write(to: manifest)
    #expect(try StorageManagement.validateRoot(game: game, library: [game]).path == install.path)
}
@Test func v04SaveAIRejectsUnknownIDsAndRedactsFullPaths() throws {
    let (root, game) = try storageFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let scan = try StorageManagement.scan(game: game, library: [game])
    let payload = String(decoding: try SaveAdvisor.payload(scan), as: UTF8.self)
    #expect(!payload.contains(root.path))
    #expect(!payload.contains("important save"))
    #expect(payload.contains("savedata"))
    #expect(throws: (any Error).self) {
        try SaveAdvisor.validate(Data(#"{"keepIDs":["invented"],"explanation":"wrong"}"#.utf8), scan: scan)
    }
    let data = try JSONSerialization.data(withJSONObject: ["keepIDs": [scan.candidates[0].id], "explanation": "保留命名线索"])
    #expect(try SaveAdvisor.validate(data, scan: scan).keepIDs == [scan.candidates[0].id])
}
@Test func v04SeriesSortingStableAndUtilitiesHidden() throws {
    var a = Game(title: "A", executable: "/a", workingDirectory: "/a")
    var b = Game(title: "B", executable: "/b", workingDirectory: "/b")
    var c = Game(title: "C", executable: "/c", workingDirectory: "/c")
    a.series = "Series"
    c.series = "Series"
    b.kind = .steam
    b.steamAppID = "228980"
    #expect(LibraryOrdering.ordered([c, b, a], mode: "manual").map(\.id) == [c.id, a.id])
    b.steamAppID = "999"
    #expect(LibraryOrdering.ordered([c, b, a], mode: "series").map(\.id) == [c.id, a.id, b.id])
    #expect(LibraryOrdering.ordered([c, b, a], mode: "title").map(\.title) == ["A", "B", "C"])
    var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as! [String: Any]
    old.removeValue(forKey: "series")
    #expect(try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: old)).series == nil)
}
