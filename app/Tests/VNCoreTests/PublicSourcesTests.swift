import Foundation
import Testing

@testable import VNCore

struct PublicSourcesTests {
    let bangumi = Data(
        #"{"data":[{"id":5418,"type":4,"name":"魔法使いの夜","name_cn":"魔法使之夜","date":"2012-04-12","summary":"简介","rating":{"score":8.7,"total":100,"rank":10}},{"id":42,"type":2,"name":"动画"}]}"#
            .utf8)
    let vndb = Data(
        #"{"results":[{"id":"v777","title":"Mahoutsukai no Yoru","alttitle":"魔法使いの夜","released":"2012-04-12","rating":86.3,"votecount":5566}]}"#
            .utf8)
    @Test func bangumiIdentityAndType() throws {
        let profiles = try PublicSourceClient.parse(bangumi, source: .bangumi)
        #expect(profiles.count == 1)
        #expect(profiles[0].title == "魔法使之夜")
        #expect(profiles[0].url?.absoluteString == "https://bgm.tv/subject/5418")
        #expect(profiles[0].score == 8.7)
        #expect(profiles[0].rank == 10)
    }
    @Test func vndbScaleAndNoRating() throws {
        let profiles = try PublicSourceClient.parse(vndb, source: .vndb)
        #expect(abs((profiles[0].score ?? 0) - 8.63) < 0.0001)
        let empty = try PublicSourceClient.parse(
            Data(#"{"results":[{"id":"v1","title":"Empty","rating":null,"votecount":0}]}"#.utf8), source: .vndb)
        #expect(empty[0].score == nil)
        #expect(empty[0].scoreLabel == "暂无评分")
    }
    @Test func invalidSourceData() throws {
        #expect(throws: (any Error).self) {
            try PublicSourceClient.parse(Data(#"{"error":"failure"}"#.utf8), source: .vndb)
        }
        #expect(!PublicSource.vndb.validID("v777/evil"))
        #expect(!PublicSource.bangumi.validID("１２３"))
        #expect(!PublicSource.bangumi.validID("0"))
        let invalid = try PublicSourceClient.parse(
            Data(
                #"{"results":[{"id":"v1","title":"Test","rating":110,"votecount":5},{"id":"https://evil","title":"Bad"}]}"#
                    .utf8), source: .vndb)
        #expect(invalid.count == 1)
        #expect(invalid[0].score == nil)
    }
    @Test func singleSubjectAndLengthBounds() throws {
        let object: [String: Any] = [
            "id": 1, "type": 4, "name": "Test", "summary": String(repeating: "a", count: 12000),
        ]
        let profiles = try PublicSourceClient.parse(
            JSONSerialization.data(withJSONObject: object), source: .bangumi, single: true)
        #expect(profiles[0].summary.count == 8000)
        #expect(profiles[0].votes == 0)
    }
    @Test func persistenceRefreshAndRematch() throws {
        var game = Game(title: "手动名", executable: "/fixture", workingDirectory: "/fixture")
        game.kind = .steam
        game.steamAppID = "2052410"
        game.metadata = GameMetadata()
        game.metadata?.publicProfiles = try PublicSourceClient.parse(vndb, source: .vndb)
        game = try MetadataEditing.manual([.title: "我自己的标题"], in: game)
        let restored = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(restored == game)
        var candidate = MetadataResult()
        candidate.title = "New"
        candidate.metadata.identity = MetadataIdentity(steamAppID: "2052410", name: "same")
        let refreshed = MetadataEditing.automatic(candidate, current: game, imported: game)
        #expect(refreshed.metadata?.publicProfiles == game.metadata?.publicProfiles)
        #expect(refreshed.displayTitle == "我自己的标题")
        candidate.metadata.identity = MetadataIdentity(steamAppID: "123", name: "different")
        let rematched = try MetadataEditing.rematch(candidate, fields: [], includeArtwork: false, into: game)
        #expect(rematched.metadata?.publicProfiles == nil)
    }
    @Test func publicLiveSmokeWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["VN_PUBLIC_SOURCE_SMOKE"] == "1" else { return }
        let bgm = try await PublicSourceClient.shared.search(.bangumi, query: "魔法使之夜")
        let vn = try await PublicSourceClient.shared.search(.vndb, query: "Mahoutsukai no Yoru")
        #expect(bgm.contains { $0.sourceID == "5418" && $0.url != nil })
        #expect(vn.contains { $0.sourceID == "v777" && $0.score != nil })
        try await Task.sleep(for: .seconds(3))
        let bgmFresh = try await PublicSourceClient.shared.refresh(try #require(bgm.first { $0.sourceID == "5418" }))
        let vnFresh = try await PublicSourceClient.shared.refresh(try #require(vn.first { $0.sourceID == "v777" }))
        #expect(bgmFresh.sourceID == "5418")
        #expect(vnFresh.sourceID == "v777")
    }
}
