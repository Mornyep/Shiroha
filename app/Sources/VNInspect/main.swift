import Foundation
import VNCore

if CommandLine.arguments.contains("--codex-smoke") {
    guard let path = CodexAdvisor.discover() else { throw VNError.message("Codex CLI not found") }
    let input = try JSONDecoder().decode(
        AdviceInput.self,
        from: Data(
            #"{"architecture":"x64","crossOverVersion":"synthetic-test","facts":[{"id":"fixture-vc","category":"vcruntime140.dll","state":"需要验证"}]}"#
                .utf8))
    do {
        let result = try await CodexAdvisor(executable: path).explain(input)
        print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
    } catch {
        print("CODEX_SMOKE_FAILED: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}
let runner = CrossOver.discoverRunner()
let bottles = CrossOver.discoverBottles()
let summary: [String: Any] = [
    "runnerVersion": runner?.version ?? "not_found", "system": ProcessInfo.processInfo.operatingSystemVersionString,
    "bottles": bottles.map {
        [
            "name": $0.name, "windowsVersion": $0.configuration["WindowsVersion"] ?? "unknown",
            "template": $0.configuration["Template"] ?? "unknown",
        ]
    }, "mode": "read_only_no_wine_process",
]
print(
    String(
        decoding: try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]),
        as: UTF8.self))
// The optional library path must be deliberately supplied. This inspects only its selected first entry.
if CommandLine.arguments.count == 2 {
    let library = try Storage.load(URL(fileURLWithPath: CommandLine.arguments[1]))
    if let game = library.games.first {
        let report = try Analyzer.scan(game: game, bottle: bottles.first { $0.id == game.bottleID }, runner: runner)
        print("SCAN_SUMMARY")
        let counts = Dictionary(grouping: report.findings, by: { $0.state.rawValue }).mapValues(\.count)
        print(
            String(
                decoding: try JSONSerialization.data(
                    withJSONObject: [
                        "findings": counts, "architecture": report.architecture, "fingerprint": report.fingerprint,
                        "bottleFingerprint": report.bottleFingerprint, "notes": report.notes,
                    ], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
