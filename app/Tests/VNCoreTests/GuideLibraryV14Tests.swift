import Foundation
import Testing

@testable import VNCore

struct GuideLibraryV14Tests {
    func plan() -> GuidePlan {
        var plan = GuidePlan()
        plan.title = "Fixture guide"
        plan.sourceURL = "https://example.com/guide"
        plan.version = "Fixture build 1"
        plan.target = "Route A"
        let start = GuideNode(title: "Start", chapter: "1", hint: "Read this page")
        let end = GuideNode(
            title: "End", chapter: "2", route: "A", hint: "Choose A", saveReminder: "Use a new slot",
            prerequisites: [start.id])
        plan.nodes = [start, end]
        plan.nodes[0].next = [end.id]
        return plan
    }

    @Test func prerequisitesSelectionAndSpoilerGates() throws {
        var plan = plan()
        try plan.validate()
        #expect(throws: (any Error).self) { try plan.select(plan.nodes[1].id) }
        try plan.select(plan.nodes[0].id)
        var progress = PlayProgress()
        progress.guidePlan = plan
        #expect(progress.guideBlock != nil)
        progress.manual = ProgressPosition(chapter: "1")
        progress.gameVersion = plan.version
        progress.target = plan.target
        #expect(progress.guideBlock == nil)
        progress.observation = SaveObservation(fingerprint: "new", slots: [], adapter: "fixture")
        #expect(progress.guideBlock != nil)
        progress.manualBasis = "new"
        #expect(progress.guideBlock == nil)
        progress.gameVersion = "different"
        #expect(progress.guideBlock != nil)
        progress.gameVersion = plan.version
        progress.target = "other"
        #expect(progress.guideBlock != nil)
    }

    @Test func completionRemovalAndDanglingEdges() throws {
        var plan = plan()
        plan.completedNodeIDs = [plan.nodes[0].id]
        try plan.select(plan.nodes[1].id)
        #expect(plan.currentNote?.hint.contains("Use a new slot") == true)
        let removed = plan.nodes[0].id
        plan.removeNode(removed)
        try plan.validate()
        #expect(plan.nodes[0].prerequisites.isEmpty)
        #expect(plan.completedNodeIDs.isEmpty)
        plan.removeNode(plan.nodes[0].id)
        #expect(plan.selectedNodeID == nil)
        #expect(plan.currentNote == nil)
    }

    @Test func invalidGraphAndSourceAreRejected() throws {
        var plan = plan()
        plan.nodes[0].prerequisites = [plan.nodes[1].id]
        #expect(throws: (any Error).self) { try plan.validate() }
        plan = self.plan()
        plan.nodes[0].next = [UUID()]
        #expect(throws: (any Error).self) { try plan.validate() }
        plan = self.plan()
        plan.sourceURL = "https://user:password@example.com/guide"
        #expect(throws: (any Error).self) { try plan.validate() }
        plan.sourceURL = "file:///private/guide"
        #expect(throws: (any Error).self) { try plan.validate() }
    }

    @Test func revokedPrerequisiteHidesCurrentHint() throws {
        var plan = plan()
        plan.completedNodeIDs = [plan.nodes[0].id]
        try plan.select(plan.nodes[1].id)
        var progress = PlayProgress()
        progress.guidePlan = plan
        progress.manual = ProgressPosition(chapter: "2", route: "A")
        progress.gameVersion = plan.version
        progress.target = plan.target
        #expect(progress.guideBlock == nil)
        progress.guidePlan?.completedNodeIDs = []
        #expect(progress.guideBlock != nil)
    }

    @Test func legacyBookmarkAndNewRecordsRoundtrip() throws {
        var game = Game(title: "Fixture", executable: "/fixture/game.exe", workingDirectory: "/fixture")
        game.bookmark = PlayBookmark(note: "Legacy")
        game.bookmarks = [NamedBookmark(name: "Second", value: PlayBookmark(chapter: "2"))]
        #expect(game.allBookmarks.count == 2)
        #expect(game.allBookmarks[0].id == game.id)
        var progress = PlayProgress()
        progress.guidePlan = plan()
        game.progress = progress
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(decoded == game)
        try PersonalLibrary.validate(games: [decoded], collections: [])
        var bad = game
        let duplicate = try #require(bad.bookmarks?.first)
        bad.bookmarks?.append(duplicate)
        #expect(throws: (any Error).self) { try PersonalLibrary.validate(games: [bad], collections: []) }
    }

    @Test func portableGuideAndBookmarksPreserveLegacyImport() throws {
        let root = URL(fileURLWithPath: "/private/tmp/VNGuideTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        var game = Game(title: "Fixture", executable: "/fixture/game.exe", workingDirectory: "/fixture")
        game.bookmarks = [NamedBookmark(name: "A", value: PlayBookmark(note: "private note"))]
        var progress = PlayProgress()
        progress.guidePlan = plan()
        game.progress = progress
        let destination = root.appendingPathComponent("export")
        _ = try LibraryTransfer.export(games: [game], to: destination)
        let preview = try LibraryTransfer.preview(at: destination)
        #expect(preview.games == [game])
        var old = game
        old.bookmarks = nil
        old.progress = nil
        let merged = LibraryMerge.apply([old], to: [game], mode: .updateDetails).games[0]
        #expect(merged.bookmarks == game.bookmarks)
        #expect(merged.progress == game.progress)
        var empty = game
        empty.bookmarks = []
        #expect(LibraryMerge.apply([empty], to: [game], mode: .updateDetails).games[0].bookmarks == [])
    }

    @Test func invalidPersistedSourceIsRejected() throws {
        let root = URL(fileURLWithPath: "/private/tmp/VNLibraryTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        var game = Game(title: "Fixture", executable: "/fixture", workingDirectory: "/fixture")
        var profiles = try PublicSourceClient.parse(
            Data(#"{"results":[{"id":"v1","title":"Test","rating":75,"votecount":10}]}"#.utf8), source: .vndb)
        profiles.append(profiles[0])
        game.metadata = GameMetadata()
        game.metadata?.publicProfiles = profiles
        let file = root.appendingPathComponent("library.json")
        try Storage.save(LibraryDocument(games: [game]), to: file)
        #expect(throws: (any Error).self) { try Storage.load(file) }
    }

    @Test func steamReleaseMatchWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["VN_STEAM_MATCH_SMOKE"] == "1" else { return }
        let matches = try await PublicSourceClient.shared.matchSteam(appID: "2052410")
        #expect(matches.contains { $0.sourceID == "v777" && $0.matchedSteamID == "2052410" })
    }
}

@Test func configurationSavePreservesConcurrentProgressAndLibraryEdits() throws {
    var original = Game(title: "Old", executable: "/old.exe", workingDirectory: "/old")
    original.bookmark = PlayBookmark(note: "legacy")
    var draft = original
    draft.workingDirectory = "/new"
    draft.arguments = ["--windowed"]
    var latest = original
    latest.progress = PlayProgress()
    latest.progress?.observation = SaveObservation(fingerprint: "new", slots: [], adapter: "test")
    latest.bookmarks = [NamedBookmark(name: "Fresh")]
    latest.lastLaunched = Date()
    latest.favorite = true
    latest.metadata = GameMetadata()
    latest.metadata?.summary = "newly fetched"
    let saved = try GameConfiguration.applying(
        draft, original: original, to: latest, titleEdited: false, coverEdited: false)
    #expect(saved.workingDirectory == "/new")
    #expect(saved.arguments == ["--windowed"])
    #expect(saved.progress == latest.progress)
    #expect(saved.bookmarks == latest.bookmarks)
    #expect(saved.lastLaunched == latest.lastLaunched)
    #expect(saved.favorite)
    #expect(saved.metadata == latest.metadata)
}
