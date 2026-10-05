import Foundation
import Testing

@testable import VNCore

struct AuditV14Tests {
    @Test func unreadableChildCannotProduceBackupReceipt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let locked = source.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        try Data("visible".utf8).write(to: source.appendingPathComponent("ok.dat"))
        try Data("save".utf8).write(to: locked.appendingPathComponent("slot.dat"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        #expect(throws: (any Error).self) {
            try SaveBackup.copyAndVerify(source: source, destination: root.appendingPathComponent("copy"))
        }
    }

    @Test func finalBackupVerificationRejectsEarlierFileMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("copy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = source.appendingPathComponent("slot.dat")
        try Data("before".utf8).write(to: file)
        let receipt = try SaveBackup.copyAndVerify(source: source, destination: target)
        try Data("after".utf8).write(to: file)
        #expect(throws: (any Error).self) {
            try SaveBackup.verifyContents(source: source, destination: target, hashes: receipt.hashes)
        }
    }

    @Test func convertedLegacyBookmarkImportsAndCanBeCleared() throws {
        var local = Game(title: "Fixture", executable: "/fixture.exe", workingDirectory: "/")
        local.bookmark = PlayBookmark(chapter: "1")
        var converted = local
        converted.bookmark = nil
        converted.bookmarks = [NamedBookmark(id: local.id, name: "Edited", value: PlayBookmark(chapter: "2"))]
        let merged = LibraryMerge.apply([converted], to: [local], mode: .updateDetails).games[0]
        try PersonalLibrary.validate(games: [merged], collections: [])
        #expect(merged.allBookmarks.count == 1)
        #expect(merged.allBookmarks.first?.value.chapter == "2")
        converted.bookmarks = []
        let cleared = LibraryMerge.apply([converted], to: [local], mode: .updateDetails).games[0]
        #expect(cleared.allBookmarks.isEmpty)
    }

    @Test func analysisInputsIgnorePersonalChangesButTrackLaunchIdentity() {
        let base = Game(title: "Fixture", executable: "/a.exe", workingDirectory: "/")
        var changed = base
        changed.title = "Edited"
        changed.bookmark = PlayBookmark(chapter: "1")
        #expect(GameConfiguration.sameAnalysisInputs(base, changed))
        changed.executable = "/b.exe"
        #expect(!GameConfiguration.sameAnalysisInputs(base, changed))
        changed = base
        changed.steamAppID = "2052410"
        #expect(!GameConfiguration.sameAnalysisInputs(base, changed))
    }
}
