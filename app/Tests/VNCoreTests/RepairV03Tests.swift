import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import VNCore

private func repairReport(_ facts: [Finding], architecture: String = "x64") -> AnalysisReport {
    AnalysisReport(
        gameID: UUID(), date: Date(), fingerprint: "game", bottleFingerprint: "bottle", runnerVersion: "fixture",
        systemVersion: "fixture", architecture: architecture, findings: facts, notes: [])
}
@Test func v03RepairRequiresSpecificArchitectureAndMissingCandidate() throws {
    let missing = Finding(
        component: "vcruntime140.dll", architecture: "x86", state: .verify, evidence: "适用候选目录未找到同架构实现", action: "核对")
    let conflict = Finding(
        component: "msvcp140.dll", architecture: "x64", state: .verify, evidence: "游戏私有目录：x86；另有同架构容器候选",
        action: "核对加载顺序")
    let report = repairReport([missing, conflict], architecture: "x64 / x86")
    let bottle = Bottle(name: "Steam", path: "/fixture/Steam", configuration: ["WindowsVersion": "win10"])
    #expect(VCInstallPlan.eligibleArchitectures(report) == ["x86"])
    let plan = try VCInstallPlan(
        report: report, bottle: bottle, architecture: "x86", destinationName: "VN-Repair-fixture")
    #expect(plan.download.absoluteString == "https://aka.ms/vc14/vc_redist.x86.exe")
    #expect(throws: (any Error).self) { try VCInstallPlan(report: report, bottle: bottle, architecture: "x64") }
    #expect(throws: (any Error).self) {
        try VCInstallPlan(report: report, bottle: bottle, architecture: "x86", destinationName: "../Steam")
    }
    #expect(throws: (any Error).self) {
        try VCInstallPlan(
            report: report,
            bottle: Bottle(name: "Old", path: "/fixture/Old", configuration: ["WindowsVersion": "win7"]),
            architecture: "x86")
    }
    var game = Game(
        title: "原库保留", executable: "/fixture/Steam/drive_c/game.exe", workingDirectory: "/fixture/Steam/drive_c")
    game.saveDirectory = "/outside/save"
    let copied = plan.remap(game)
    #expect(copied.executable == "/fixture/VN-Repair-fixture/drive_c/game.exe")
    #expect(game.executable == "/fixture/Steam/drive_c/game.exe")
    #expect(copied.saveDirectory == "/outside/save")
    game.executable = "/fixture/SteamOther/game.exe"
    #expect(plan.remap(game).executable == game.executable)
}
@Test func v03InventoryDeduplicatesRecordsAndDoesNotConvertUnknownToMissing() {
    let record = Finding(component: "安装记录", state: .verify, evidence: "Visual C++", action: "不证明可用")
    let unknown = Finding(component: "vcruntime140.dll", state: .verify, evidence: "未找到", action: "待核验")
    let groups = ComponentInventory.groups(repairReport([record, record, unknown]))
    #expect(groups.first { $0.id == "records" }?.findings.count == 1)
    #expect(groups.first { $0.id == "vc14" }?.summary == "有未找到或待验证项")
    #expect(VCInstallPlan.eligibleArchitectures(repairReport([unknown])).isEmpty)
    #expect(ComponentInstaller.trustedDownload(URL(string: "https://download.visualstudio.microsoft.com/a.exe")!))
    #expect(!ComponentInstaller.trustedDownload(URL(string: "https://download.microsoft.com.evil.test/a.exe")!))
    #expect(!ComponentInstaller.trustedDownload(URL(string: "http://download.microsoft.com/a.exe")!))
}
@Test func v03CopyFixturePreservesOriginalAndExternalSymlink() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VNCloneTest-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Source")
    let destination = root.appendingPathComponent("New")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let original = Data("original bytes".utf8)
    try original.write(to: source.appendingPathComponent("system.reg"))
    try FileManager.default.createSymbolicLink(
        at: source.appendingPathComponent("external"),
        withDestinationURL: URL(fileURLWithPath: "/nonexistent-fixture-target"))
    let code = try await ComponentInstaller.run(
        "/bin/cp", ["-cR", source.path, destination.path], log: root.appendingPathComponent("copy.log"), seconds: 10)
    #expect(code == 0)
    try Data("changed copy".utf8).write(to: destination.appendingPathComponent("system.reg"))
    #expect(try Data(contentsOf: source.appendingPathComponent("system.reg")) == original)
    #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("external").path)
            == "/nonexistent-fixture-target")
    #expect(throws: (any Error).self) { try Data(contentsOf: destination.appendingPathComponent("external")) }
    do {
        _ = try await ComponentInstaller.run(
            "/bin/sleep", ["5"], log: root.appendingPathComponent("timeout.log"), seconds: 0.1)
        Issue.record("Expected timeout")
    } catch { #expect(error.localizedDescription.contains("超时")) }
}
@Test func v03ArtworkUpgradeUsesPixelsAndPreservesManualChoice() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VNArtTest-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func png(_ w: Int, _ h: Int, _ name: String) throws -> String {
        let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = root.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url.path
    }
    let low = try png(300, 450, "old.png")
    let high = try png(600, 900, "new.png")
    let banner = try png(2000, 600, "banner.png")
    #expect(ArtworkQuality.improves(high, over: low))
    #expect(!ArtworkQuality.improves(banner, over: high))
    var game = Game(title: "测试", executable: "/fixture", workingDirectory: "/fixture")
    game.coverPath = low
    game.metadata = GameMetadata()
    game.metadata?.coverSource = "本机 Steam"
    var result = MetadataResult()
    result.coverPath = high
    result.metadata.coverSource = "https://cdn.steamstatic.com/poster.jpg"
    #expect(MetadataService.merge(result, into: game, imported: game).coverPath == high)
    game.metadata?.coverSource = "手动选择"
    #expect(MetadataService.merge(result, into: game, imported: game).coverPath == low)
    #expect(
        ArtworkQuality.steamPosters(
            header: URL(
                string:
                    "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1/hash/header_schinese.jpg?t=3")!
        ).first?.path == "/store_item_assets/steam/apps/1/hash/library_600x900_2x_schinese.jpg")
}
