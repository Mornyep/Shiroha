import Foundation
import Testing

@testable import VNCore

private func progressRoot() throws -> URL {
    let root = URL(fileURLWithPath: "/private/tmp/progress-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func sud(_ script: String = "4_1.chs") -> Data {
    var data = Data(repeating: 0, count: 512)
    data[2] = 1
    for (i, byte) in script.utf8.enumerated() { data[284 + i] = byte }
    return data
}
@Test func v12HeaderReadsOnlyBoundedKnownFormat() {
    #expect(MahoyoSaveHeader.parse(sud())?.script == "4_1.chs")
    #expect(MahoyoSaveHeader.parse(sud("TEATIME3.chs"))?.script == "TEATIME3.chs")
    #expect(MahoyoSaveHeader.parse(Data()) == nil)
    #expect(MahoyoSaveHeader.parse(sud("../../evil.chs")) == nil)
    #expect(MahoyoSaveHeader.parse(sud("4_1.unknown")) == nil)
    var bad = sud()
    bad[0] = 1
    #expect(MahoyoSaveHeader.parse(bad) == nil)
}
@Test func v12SnapshotTracksSlotsChangesDeletionWithoutWritingOriginals() throws {
    let root = try progressRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("WitchOnTheHolyNight000.sud")
    let b = root.appendingPathComponent("WitchOnTheHolyNight120.sud")
    try sud().write(to: a)
    try sud("1_2.chs").write(to: b)
    try Data("ignored".utf8).write(to: root.appendingPathComponent("steam_autocloud.vdf"))
    let before = try Data(contentsOf: a)
    let first = try SaveSnapshotReader.scan(directory: root, mahoyo: true)
    #expect(first.observation.slots.count == 2)
    #expect(first.observation.slots[0].script == "4_1.chs")
    #expect(try Data(contentsOf: a) == before)
    try sud("3_1.chs").write(to: a, options: .atomic)
    let second = try SaveSnapshotReader.scan(directory: root, mahoyo: true)
    #expect(second.observation.fingerprint != first.observation.fingerprint)
    try FileManager.default.removeItem(at: b)
    #expect(try SaveSnapshotReader.scan(directory: root, mahoyo: true).observation.slots.count == 1)
}
@Test func v12SnapshotRejectsLinkedRootSkipsLinkedChildAndBoundsEnumeration() throws {
    let root = try progressRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let watched = root.appendingPathComponent("watched")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
    try sud().write(to: source.appendingPathComponent("private.sud"))
    try FileManager.default.createSymbolicLink(at: watched.appendingPathComponent("escape"), withDestinationURL: source)
    #expect(try SaveSnapshotReader.scan(directory: watched, mahoyo: false).observation.slots.isEmpty)
    #expect(throws: (any Error).self) {
        try SaveSnapshotReader.scan(directory: watched.appendingPathComponent("escape"), mahoyo: false)
    }
    for i in 0..<129 { try Data().write(to: watched.appendingPathComponent("file\(i)")) }
    #expect(throws: (any Error).self) { try SaveSnapshotReader.scan(directory: watched, mahoyo: false) }
}
@Test func v12StableSnapshotRejectsChangingInput() async throws {
    let root = try progressRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("slot")
    try Data("before".utf8).write(to: file)
    let writer = Task {
        try await Task.sleep(for: .milliseconds(250))
        try Data("after".utf8).write(to: file)
    }
    await #expect(throws: (any Error).self) { try await SaveSnapshotReader.stable(directory: root, mahoyo: false) }
    try await writer.value
    #expect(try await SaveSnapshotReader.stable(directory: root, mahoyo: false).observation.slots.count == 1)
}
@Test func v12GuideGatesSpoilersOnPositionTargetVersionAndNewEvidence() throws {
    var progress = PlayProgress()
    var guide = GuideNote()
    guide.title = "Original"
    guide.url = "https://example.com/guide"
    guide.version = "Steam"
    guide.chapter = "第四章"
    guide.target = "主线"
    guide.hint = "继续阅读"
    progress.guide = guide
    #expect(progress.guideBlock != nil)
    progress.manual = ProgressPosition(chapter: "第四章")
    progress.gameVersion = "Steam"
    progress.target = "主线"
    #expect(progress.guideBlock == nil)
    progress.target = "其他"
    #expect(progress.guideBlock != nil)
    progress.target = "主线"
    progress.observation = SaveObservation(fingerprint: "changed", slots: [], adapter: "test")
    #expect(progress.hasNewEvidence)
    #expect(progress.guideBlock != nil)
    progress.manualBasis = "changed"
    #expect(progress.guideBlock == nil)
    progress.guide?.url = "file:///private"
    #expect(throws: (any Error).self) { try PlayProgress.validate(progress) }
}
@Test func v12PersonalProgressRoundtripMergeAndUndoProtectEdits() throws {
    let root = try progressRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var game = Game(title: "Title", executable: "/a", workingDirectory: "/")
    game.bookmark = PlayBookmark(note: "Keep me")
    var progress = PlayProgress()
    progress.manual = ProgressPosition(chapter: "4")
    progress.target = "主线"
    game.progress = progress
    let file = root.appendingPathComponent("library.json")
    try Storage.save(LibraryDocument(games: [game]), to: file)
    #expect(try Storage.load(file).games == [game])
    #expect(try Storage.load(file).version == LibraryDocument.currentVersion)
    let portable = root.appendingPathComponent("portable")
    _ = try LibraryTransfer.export(games: [game], to: portable)
    #expect(try LibraryTransfer.preview(at: portable).games[0].progress == progress)
    var legacy = game
    legacy.progress = nil
    #expect(LibraryMerge.apply([legacy], to: [game], mode: .updateDetails).games[0].progress == progress)
    var edited = game
    edited.progress?.target = "new"
    #expect(throws: (any Error).self) { try LibraryMerge.undo(before: [legacy], after: [game], current: [edited]) }
    #expect(edited.bookmark == game.bookmark)
}
@Test func v12FutureLibraryVersionRefusesRead() throws {
    let root = try progressRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var doc = LibraryDocument()
    doc.version = LibraryDocument.currentVersion + 1
    let file = root.appendingPathComponent("library.json")
    try Storage.save(doc, to: file)
    #expect(throws: (any Error).self) { try Storage.load(file) }
}

@Test func v12UnreadableOversizedAndUnsupportedInputsStayBounded() throws {
    let root = try progressRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: (any Error).self) {
        try SaveSnapshotReader.scan(directory: root.appendingPathComponent("missing"), mahoyo: true)
    }
    let file = root.appendingPathComponent("WitchOnTheHolyNight000.sud")
    try Data("broken".utf8).write(to: file)
    let unknown = try SaveSnapshotReader.scan(directory: root, mahoyo: true)
    #expect(unknown.observation.slots.count == 1)
    #expect(unknown.observation.slots[0].script == nil)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 8 * 1024 * 1024 + 1)
    try handle.close()
    #expect(throws: (any Error).self) { try SaveSnapshotReader.scan(directory: root, mahoyo: true) }
}
