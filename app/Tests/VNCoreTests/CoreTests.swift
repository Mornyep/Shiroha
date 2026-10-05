import Foundation
import Testing

@testable import VNCore

private func pe(architecture: UInt16 = 0x8664, imports: [String] = [], delayed: [String] = []) -> Data {
    var d = Data(repeating: 0, count: 8192)
    func put(_ p: Int, _ v: UInt64, _ n: Int) { for i in 0..<n { d[p + i] = UInt8(truncatingIfNeeded: v >> (8 * i)) } }
    let plus = architecture != 0x14c
    let opt = 0x98
    let optionalSize = plus ? 240 : 224
    let dirs = opt + (plus ? 112 : 96)
    put(0, 0x5a4d, 2)
    put(0x3c, 0x80, 4)
    put(0x80, 0x4550, 4)
    put(0x84, UInt64(architecture), 2)
    put(0x86, 1, 2)
    put(0x94, UInt64(optionalSize), 2)
    put(opt, plus ? 0x20b : 0x10b, 2)
    put(opt + 60, 0x200, 4)
    put(opt + (plus ? 108 : 92), 16, 4)
    let section = opt + optionalSize
    put(section + 12, 0x1000, 4)
    put(section + 16, 0x1e00, 4)
    put(section + 20, 0x200, 4)
    func rva(_ p: Int) -> UInt64 { UInt64(p - 0x200 + 0x1000) }
    var nameOffset = 0x1000
    for (table, names, index, stride, field) in [(0x200, imports, 1, 20, 12), (0x600, delayed, 13, 32, 4)]
    where !names.isEmpty {
        put(dirs + index * 8, rva(table), 4)
        put(dirs + index * 8 + 4, UInt64((names.count + 1) * stride), 4)
        for (i, name) in names.enumerated() {
            if index == 13 { put(table + i * stride, 1, 4) }
            put(table + i * stride + field, rva(nameOffset), 4)
            for (j, byte) in name.utf8.enumerated() { d[nameOffset + j] = byte }
            nameOffset += name.utf8.count + 1
        }
    }
    return d
}
private func temporary() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent("VNTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
    return p
}
private func write(_ data: Data, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

@Test func parsesPEBothArchitecturesAndDelayImports() throws {
    for (machine, name) in [(UInt16(0x14c), "x86"), (UInt16(0x8664), "x64")] {
        let info = try PEReader.parse(
            pe(architecture: machine, imports: ["KERNEL32.dll", "msvcp140.dll"], delayed: ["MFPlat.dll"]))
        #expect(info.architecture == name)
        #expect(info.imports == ["kernel32.dll", "msvcp140.dll"])
        #expect(info.delayed == ["mfplat.dll"])
    }
}
@Test func malformedPEIsRejectedWithoutCrashes() {
    #expect(throws: (any Error).self) { try PEReader.parse(Data()) }
    let valid = pe(imports: ["kernel32.dll"])
    for length in [1, 63, 64, 128, 150, 230, 511] {
        #expect(throws: (any Error).self) { try PEReader.parse(valid.prefix(length)) }
    }
    var bad = valid
    bad[0x3c] = 0xff
    bad[0x3d] = 0xff
    bad[0x3e] = 0xff
    bad[0x3f] = 0xff
    #expect(throws: (any Error).self) { try PEReader.parse(bad) }
    #expect(throws: (any Error).self) { try PEReader.parse(pe(imports: ["../../private.dll"])) }
}
@Test func mutatedPEOffsetsNeverTrap() {
    let original = pe(imports: ["kernel32.dll"], delayed: ["mfplat.dll"])
    for offset in stride(from: 0, to: 640, by: 4) {
        var data = original
        for j in 0..<4 { data[offset + j] = 255 }
        _ = try? PEReader.parse(data)
    }
}
@Test func boundedWalkDoesNotFollowSymlinks() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let selected = root.appendingPathComponent("游戏")
    let outside = root.appendingPathComponent("outside")
    try write(Data("private".utf8), outside.appendingPathComponent("secret.txt"))
    try write(Data(), selected.appendingPathComponent("game.exe"))
    try FileManager.default.createSymbolicLink(at: selected.appendingPathComponent("z:"), withDestinationURL: outside)
    let result = try FileSafety.walk(selected)
    #expect(result.files.map(\.lastPathComponent) == ["game.exe"])
    #expect(!FileSafety.contained(selected.appendingPathComponent("z:/secret.txt"), in: selected))
    #expect(try FileSafety.walk(selected, maximum: 0).limited)
    #expect(throws: (any Error).self) { try FileSafety.read(outside.appendingPathComponent("secret.txt"), limit: 1) }
}
@Test func libraryRoundTripAndCorruptionPreservation() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("library.json")
    var game = Game(title: "日本語 中文 空格", executable: "/fixture/a.exe", workingDirectory: "/fixture")
    game.favorite = true
    game.arguments = ["--name", "space and ' quotes", "$(touch dangerous)"]
    try Storage.save(LibraryDocument(games: [game]), to: url)
    #expect(try Storage.load(url).games == [game])
    let corrupt = Data("corrupt original".utf8)
    try corrupt.write(to: url)
    #expect(throws: (any Error).self) { try Storage.load(url) }
    #expect(try Data(contentsOf: url) == corrupt)
}
@Test func exactLaunchArgumentsNoShellAndExplicitBottle() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("CrossOver.app")
    let bottleURL = root.appendingPathComponent("瓶 子")
    let exe = root.appendingPathComponent("日本語 中文/game.exe")
    let wrapper = app.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
    try write(Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\npwd\n".utf8), wrapper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    try write(pe(), exe)
    try write(Data(), bottleURL.appendingPathComponent("cxbottle.conf"))
    let bottle = Bottle(name: "瓶 子", path: bottleURL.path, configuration: [:])
    let runner = Runner(appPath: app.path, version: "fixture")
    var game = Game(title: "测试", executable: exe.path, workingDirectory: exe.deletingLastPathComponent().path)
    #expect(throws: (any Error).self) { try CrossOver.command(game: game, bottle: bottle, runner: runner) }
    game.bottleID = bottle.id
    game.arguments = ["--title", "$(touch NO) ' 字"]
    let command = try CrossOver.command(game: game, bottle: bottle, runner: runner)
    #expect(
        command.arguments == [
            "--bottle", "瓶 子", "--no-update", "--workdir", game.workingDirectory, game.executable, "--title",
            "$(touch NO) ' 字",
        ])
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: command.executable)
    process.arguments = command.arguments
    process.currentDirectoryURL = URL(fileURLWithPath: command.directory)
    process.standardOutput = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(String(decoding: output, as: UTF8.self).contains("$(touch NO) ' 字"))
    #expect(!FileManager.default.fileExists(atPath: game.workingDirectory + "/NO"))
    game.kind = .steam
    game.steamAppID = "12345"
    #expect(try CrossOver.command(game: game, bottle: bottle, runner: runner).arguments.contains("-applaunch"))
    game.steamAppID = "1;exit"
    #expect(throws: (any Error).self) { try CrossOver.command(game: game, bottle: bottle, runner: runner) }
}
@Test func dependencyResolutionDistinguishesArchitecturesAndUnknown() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(pe(architecture: 0x14c), root.appendingPathComponent("msvcp140.dll"))
    let wrong = Analyzer.resolve(dll: "msvcp140.dll", architecture: "x64", directory: root, bottle: nil, runner: nil)
    #expect(wrong.state == .verify)
    #expect(wrong.evidence.contains("x86"))
    let match = Analyzer.resolve(dll: "msvcp140.dll", architecture: "x86", directory: root, bottle: nil, runner: nil)
    #expect(match.state == .detected)
    let absent = Analyzer.resolve(
        dll: "api-ms-win-core-test.dll", architecture: "x64", directory: root, bottle: nil, runner: nil)
    #expect(absent.state == .verify)
    #expect(absent.action.contains("不要下载"))
}
@Test func builtInWineHashAndReadOnlyScan() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let gameRoot = root.appendingPathComponent("game")
    let bottleRoot = root.appendingPathComponent("bottle")
    let app = root.appendingPathComponent("CrossOver.app")
    try write(pe(imports: ["kernel32.dll"], delayed: ["unknown.dll"]), gameRoot.appendingPathComponent("game.exe"))
    let dll = pe()
    try write(dll, bottleRoot.appendingPathComponent("drive_c/windows/system32/kernel32.dll"))
    try write(dll, app.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/kernel32.dll"))
    try write(Data("\"WindowsVersion\" = \"win10\"".utf8), bottleRoot.appendingPathComponent("cxbottle.conf"))
    let before = try FileSafety.walk(bottleRoot).files.map { try FileSafety.fingerprint(Data(contentsOf: $0)) }.sorted()
    let game = Game(
        title: "game", executable: gameRoot.appendingPathComponent("game.exe").path, workingDirectory: gameRoot.path)
    let report = try Analyzer.scan(
        game: game, bottle: Bottle(name: "fixture", path: bottleRoot.path, configuration: [:]),
        runner: Runner(appPath: app.path, version: "fixture"))
    #expect(report.findings.contains { $0.component == "kernel32.dll" && $0.evidence.contains("哈希一致") })
    #expect(!report.findings.contains { $0.state == .missing })
    #expect(
        before
            == (try FileSafety.walk(bottleRoot).files.map { try FileSafety.fingerprint(Data(contentsOf: $0)) }.sorted())
    )
}
@Test func cancelledScanStops() async throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    for i in 0..<50 { try write(Data(), root.appendingPathComponent("\(i).txt")) }
    let task = Task {
        try Task.checkCancellation()
        return try FileSafety.walk(root)
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Cancellation ignored")
    } catch is CancellationError {} catch { Issue.record("Unexpected error") }
}
@Test func steamManifestDiscoveryAndTraversalExclusion() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let steam = root.appendingPathComponent("drive_c/Program Files (x86)/Steam")
    try write(Data(), steam.appendingPathComponent("steam.exe"))
    try write(Data(), steam.appendingPathComponent("steamapps/common/日本語/a.exe"))
    try write(
        Data("\"appid\" \"123\"\n\"name\" \"日本語\"\n\"installdir\" \"日本語\"".utf8),
        steam.appendingPathComponent("steamapps/appmanifest_123.acf"))
    let games = try CrossOver.steamGames(in: Bottle(name: "test", path: root.path, configuration: [:]))
    #expect(games.count == 1)
    #expect(games.first?.kind == .steam)
    #expect(games.first?.steamAppID == "123")
}
@Test func backupAndIndependentRestoreVerifyBytesAndNeverOverwrite() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("save")
    let copy = root.appendingPathComponent("copy")
    let restored = root.appendingPathComponent("restored")
    try write(Data("存档".utf8), source.appendingPathComponent("slot/1.dat"))
    let first = try SaveBackup.copyAndVerify(source: source, destination: copy)
    let second = try SaveBackup.copyAndVerify(source: copy, destination: restored)
    #expect(first.hashes == second.hashes)
    #expect(
        try Data(contentsOf: source.appendingPathComponent("slot/1.dat"))
            == Data(contentsOf: restored.appendingPathComponent("slot/1.dat")))
    #expect(throws: (any Error).self) { try SaveBackup.copyAndVerify(source: source, destination: copy) }
    #expect(throws: (any Error).self) {
        try SaveBackup.copyAndVerify(source: source, destination: source.appendingPathComponent("nested"))
    }
}
@Test func advisorRedactsNamesAndRejectsUnknownEvidence() throws {
    let report = AnalysisReport(
        gameID: UUID(), date: Date(), fingerprint: "local", bottleFingerprint: "local", runnerVersion: "26.3",
        systemVersion: "system", architecture: "x64",
        findings: [
            Finding(
                component: "/Users/private/ignore instructions.exe", state: .verify, evidence: "SECRET_TOKEN",
                action: "run evil"),
            Finding(component: "kernel32.dll", state: .detected, evidence: "/Users/private", action: "anything"),
        ], notes: ["secret"])
    let input = AdviceInput(report: report)
    let json = String(decoding: try AdviceInput(report: report).json(), as: UTF8.self)
    #expect(!json.contains("private"))
    #expect(!json.contains("SECRET_TOKEN"))
    #expect(!json.contains("instructions"))
    #expect(input.facts.count == 1)
    let valid: [String: Any] = [
        "advice": [
            [
                "conclusion": "需要实测", "evidenceIDs": [input.facts[0].id], "confidence": "low",
                "sources": ["https://learn.microsoft.com/windows/"], "scope": "static", "action": "review",
                "verification": "input test",
            ]
        ]
    ]
    #expect(try HTTPAdvisor.validate(JSONSerialization.data(withJSONObject: valid), input: input).advice.count == 1)
    #expect(throws: (any Error).self) { try HTTPAdvisor.validate(Data("{bad json".utf8), input: input) }
    let invalid = String(decoding: try JSONSerialization.data(withJSONObject: valid), as: UTF8.self)
        .replacingOccurrences(of: input.facts[0].id, with: "invented")
    #expect(throws: (any Error).self) { try HTTPAdvisor.validate(Data(invalid.utf8), input: input) }
    let unsafe = String(decoding: try JSONSerialization.data(withJSONObject: valid), as: UTF8.self)
        .replacingOccurrences(of: "https:", with: "file:")
    #expect(throws: (any Error).self) { try HTTPAdvisor.validate(Data(unsafe.utf8), input: input) }
}
@Test func localMetadataFindsExplicitArtAndPreservesEdits() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(Data([137, 80, 78, 71]), root.appendingPathComponent("cover.png"))
    try write(Data("Title=Local title".utf8), root.appendingPathComponent("Game.ini"))
    let imported = Game(title: "a", executable: root.appendingPathComponent("a.exe").path, workingDirectory: root.path)
    let result = try MetadataService.local(game: imported)
    #expect(result.title == "Local title")
    #expect(result.coverPath?.hasSuffix("cover.png") == true)
    var edited = imported
    edited.title = "My title"
    edited.coverPath = "/my/cover.jpg"
    let merged = MetadataService.merge(result, into: edited, imported: imported)
    #expect(merged.title == "My title")
    #expect(merged.coverPath == "/my/cover.jpg")
    let automatic = MetadataService.merge(result, into: imported, imported: imported)
    #expect(automatic.title == "Local title")
    #expect(automatic.metadata?.coverSource?.contains("cover.png") == true)
}
@Test func steamMetadataRejectsUntrustedArtworkHostsAndStripsHTML() throws {
    let json = Data(
        #"{"123":{"success":true,"data":{"name":"Fixture","short_description":"<b>Story</b>","developers":["Studio"],"header_image":"https://evil.example/private.png"}}}"#
            .utf8)
    let result = try MetadataService.parseSteam(json, appID: "123")
    #expect(result.result.metadata.summary == "Story")
    #expect(result.coverURL == nil)
    #expect(MetadataService.allowedImageURL(URL(string: "https://shared.akamai.steamstatic.com/cover.jpg")!))
    #expect(!MetadataService.allowedImageURL(URL(string: "https://steamstatic.com.evil.example/cover.jpg")!))
    #expect(!MetadataService.allowedImageURL(URL(string: "file:///private/file")!))
}
private struct FailingTransport: AdviceTransport {
    let code: URLError.Code
    func send(_ request: URLRequest) async throws -> Data { throw URLError(code) }
}
private struct InvalidTransport: AdviceTransport {
    func send(_ request: URLRequest) async throws -> Data { Data("{invalid server response".utf8) }
}
@Test func advisorOfflineTimeoutAndBadJSONRemainErrors() async throws {
    let report = AnalysisReport(
        gameID: UUID(), date: Date(), fingerprint: "", bottleFingerprint: "", runnerVersion: "26.3", systemVersion: "",
        architecture: "x64", findings: [], notes: [])
    let input = AdviceInput(report: report)
    for code in [URLError.Code.notConnectedToInternet, .timedOut] {
        do {
            _ = try await HTTPAdvisor(
                endpoint: URL(string: "https://fixture.invalid/chat/completions")!, model: "test", key: "fixture",
                transport: FailingTransport(code: code)
            ).explain(input)
            Issue.record("Expected service failure")
        } catch let error as URLError { #expect(error.code == code) }
    }
    do {
        _ = try await HTTPAdvisor(
            endpoint: URL(string: "https://fixture.invalid/chat/completions")!, model: "test", key: "fixture",
            transport: InvalidTransport()
        ).explain(input)
        Issue.record("Bad JSON accepted")
    } catch {}
}
@Test func repairPlanIsEvidenceBoundAndCannotExecute() {
    let missingCandidate = Finding(
        component: "msvcp140.dll", state: .verify, evidence: "no static match", action: "review")
    let report = AnalysisReport(
        gameID: UUID(), date: Date(), fingerprint: "", bottleFingerprint: "", runnerVersion: "26.3", systemVersion: "",
        architecture: "x86", findings: [missingCandidate], notes: [])
    let bottle = Bottle(name: "dedicated fixture", path: "/fixture", configuration: [:])
    let plans = RepairPlanner.proposals(report: report, bottle: bottle)
    #expect(plans.count == 1)
    #expect(plans[0].evidenceIDs == [missingCandidate.id])
    #expect(plans[0].action == .reviewVCRuntime)
    #expect(plans[0].recoveryBoundary.contains("未执行"))
    #expect(RepairPlanner.proposals(report: report, bottle: nil).isEmpty)
}
@Test func wrongPrivateDLLDoesNotBecomeSatisfiedBySystemCandidate() throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let game = root.appendingPathComponent("game")
    let bottle = root.appendingPathComponent("bottle")
    try write(pe(architecture: 0x14c), game.appendingPathComponent("msvcp140.dll"))
    try write(pe(), bottle.appendingPathComponent("drive_c/windows/system32/msvcp140.dll"))
    let result = Analyzer.resolve(
        dll: "msvcp140.dll", architecture: "x64", directory: game,
        bottle: Bottle(name: "test", path: bottle.path, configuration: [:]), runner: nil)
    #expect(result.state == .verify)
    #expect(result.action.contains("私有 DLL"))
}

@Test func reviewsValidateCountsDeduplicateAndKeepSource() throws {
    let data = Data(
        #"{"success":1,"query_summary":{"total_reviews":12,"total_positive":10},"reviews":[{"recommendationid":"1","author":{"steamid":"123","playtime_forever":75},"review":"Actual player text","voted_up":true},{"recommendationid":"1","author":{"steamid":"123"},"review":"duplicate","voted_up":false},{"recommendationid":"2","author":{"steamid":"../bad"},"review":"invalid","voted_up":true}]}"#
            .utf8)
    let reviews = try MetadataService.parseReviews(data, appID: "456")
    #expect(reviews.items.count == 1)
    #expect(reviews.items[0].source == "https://steamcommunity.com/profiles/123/recommended/456/")
    #expect(reviews.items[0].playtimeMinutes == 75)
    #expect(throws: (any Error).self) { try MetadataService.parseReviews(data, appID: "456&evil=1") }
    let bad = Data(#"{"success":1,"query_summary":{"total_reviews":1,"total_positive":2},"reviews":[]}"#.utf8)
    #expect(throws: (any Error).self) { try MetadataService.parseReviews(bad, appID: "456") }
}
@Test func metadataDecodesOldVersionAndPreservesManualArtwork() throws {
    let old = try JSONDecoder().decode(GameMetadata.self, from: Data(#"{"summary":"Existing description"}"#.utf8))
    #expect(old.reviews == nil)
    var game = Game(title: "Manual", executable: "/fixture.exe", workingDirectory: "/")
    game.coverPath = "/manual.png"
    game.metadata = old
    game.metadata?.coverSource = "手动选择"
    var result = MetadataResult()
    result.coverPath = "/automatic.png"
    result.metadata.reviews = SteamReviews(totalReviews: 0, totalPositive: 0, items: [], fetchedAt: Date())
    let merged = MetadataService.merge(result, into: game, imported: game)
    #expect(merged.coverPath == "/manual.png")
    #expect(merged.metadata?.summary == "Existing description")
    #expect(merged.metadata?.reviews?.totalReviews == 0)
}
@Test func codexUsesIsolatedReadOnlyConfigurationAndFlagsTools() {
    let root = URL(fileURLWithPath: "/tmp/test")
    let args = CodexAdvisor.arguments(
        directory: root, schema: root.appendingPathComponent("schema"), output: root.appendingPathComponent("out"),
        model: "")
    #expect(args.contains("--ignore-user-config"))
    #expect(args.contains("read-only"))
    #expect(!args.contains("danger-full-access"))
    #expect(args.contains("web_search=\"disabled\""))
    #expect(args.contains("project_doc_max_bytes=0"))
    #expect(!args.contains("--model"))
    #expect(args.last == "-")
    #expect(CodexAdvisor.containsToolExecution(Data(#"{"item":{"type":"command_execution"}}"#.utf8)))
    #expect(!CodexAdvisor.containsToolExecution(Data(#"{"item":{"type":"agent_message","text":"ok"}}"#.utf8)))
    #expect(!CodexAdvisor.containsToolExecution(Data(#"{"item":{"type":"error","message":"Feature warning"}}"#.utf8)))
}
@Test func codexProcessCancellationAndFailureAreBounded() async throws {
    let root = try temporary()
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("fake-cli")
    try Data("#!/bin/sh\nexec /bin/sleep 20\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    let task = Task { try await CodexProcess.run(executable: script, arguments: [], input: nil, timeout: 5) }
    try await Task.sleep(for: .milliseconds(120))
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Cancelled CLI returned success")
    } catch is CancellationError {} catch { Issue.record("Unexpected \(error)") }
    try Data("#!/bin/sh\nprintf 'Logged in using an API key' >&2\nexit 0\n".utf8).write(to: script)
    do {
        _ = try await CodexAdvisor(executable: script).loginStatus()
        Issue.record("API authentication accepted as ChatGPT")
    } catch {}
}
