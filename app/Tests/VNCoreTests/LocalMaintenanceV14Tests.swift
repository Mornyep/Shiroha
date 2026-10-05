import Darwin
import Foundation
import Testing

@testable import VNCore

@Suite struct LocalMaintenanceV14Tests {
    func fixture() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("V14-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func put(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    @Test func modernLegacyInvalidAndOversizedVDF() throws {
        #expect(
            try SteamLibraries.paths(
                in:
                    #""libraryfolders" { "0" { "path" "C:\\Program Files (x86)\\Steam" "apps" { "10" "1" } } "1" { "path" "/Volumes/Games/Steam" } }"#
            ) == ["/Volumes/Games/Steam", "C:\\Program Files (x86)\\Steam"])
        #expect(try SteamLibraries.paths(in: #""LibraryFolders" { "1" "D:\\Steam" "2" "D:\\Steam" }"#) == ["D:\\Steam"])
        for text in [
            "bad", "\"libraryfolders\" {", "\"libraryfolders\" { \"1\" }",
            String(repeating: " ", count: 1024 * 1024 + 1),
        ] { #expect(throws: (any Error).self) { try SteamLibraries.paths(in: text) } }
    }
    @Test func explicitMappingDiscoveryDedupOfflineAndSymlinkBoundaries() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottleRoot = root.appendingPathComponent("Bottle")
        let external = root.appendingPathComponent("External")
        let steam = bottleRoot.appendingPathComponent("drive_c/Program Files (x86)/Steam")
        try put("", steam.appendingPathComponent("steam.exe"))
        try FileManager.default.createDirectory(
            at: bottleRoot.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: bottleRoot.appendingPathComponent("dosdevices/d:"), withDestinationURL: external)
        try FileManager.default.createSymbolicLink(
            at: bottleRoot.appendingPathComponent("dosdevices/z:"), withDestinationURL: URL(fileURLWithPath: "/"))
        try put(
            "\"libraryfolders\" { \"1\" { \"path\" \"D:\\\\Steam\" } \"2\" \"\(external.path)/Steam\" \"3\" \"E:\\\\Offline\" }",
            steam.appendingPathComponent("steamapps/libraryfolders.vdf"))
        let apps = external.appendingPathComponent("Steam/steamapps")
        try FileManager.default.createDirectory(
            at: apps.appendingPathComponent("common/Game"), withIntermediateDirectories: true)
        try put(
            #""AppState" { "appid" "123" "name" "Fixture" "installdir" "Game" }"#,
            apps.appendingPathComponent("appmanifest_123.acf"))
        try put(
            #""AppState" { "appid" "124" "name" "Escape" "installdir" "../Game" }"#,
            apps.appendingPathComponent("appmanifest_124.acf"))
        let outside = root.appendingPathComponent("outside.acf")
        try put(#""AppState" { "appid" "125" "name" "Link" "installdir" "Game" }"#, outside)
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("appmanifest_125.acf"), withDestinationURL: outside)
        try put(String(repeating: "x", count: 256 * 1024 + 1), apps.appendingPathComponent("appmanifest_126.acf"))
        let bottle = Bottle(name: "Fixture", path: bottleRoot.path, configuration: [:])
        let games = try CrossOver.steamGames(in: bottle)
        #expect(games.count == 1)
        #expect(games.first?.steamAppID == "123")
        #expect(
            games.first?.workingDirectory == apps.appendingPathComponent("common/Game").resolvingSymlinksInPath().path)
        #expect(games.first?.executable == steam.appendingPathComponent("steam.exe").path)
        #expect(SteamLibraries.resolve("D:\\..\\secret", bottle: bottleRoot) == nil)
        #expect(SteamLibraries.resolve("Q:\\missing", bottle: bottleRoot) == nil)
        #expect(SteamLibraries.resolve("Z:\\Volumes\\Games", bottle: bottleRoot)?.path == "/Volumes/Games")
        try FileManager.default.createSymbolicLink(
            at: external.appendingPathComponent("Alias"), withDestinationURL: root)
        #expect(SteamLibraries.resolve("D:\\Alias\\private", bottle: bottleRoot) == nil)
        try FileManager.default.removeItem(at: external)
        #expect(try CrossOver.steamGames(in: bottle).isEmpty)
    }
    @Test func retentionRecoveryAndActiveLocks() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("Logs")
        let recovery = root.appendingPathComponent("Recovery")
        let activeURL = logs.appendingPathComponent("\(UUID()).log")
        let idleURL = logs.appendingPathComponent("\(UUID()).log")
        let active = try LauncherLogs.create(activeURL, header: "active")
        #expect(fcntl(active.fileDescriptor, F_GETFD) & FD_CLOEXEC != 0)
        defer { try? active.close() }
        try put(String(repeating: "i", count: 2048), idleURL)
        try put("unrelated", logs.appendingPathComponent("user.log"))
        let linked = logs.appendingPathComponent("\(UUID()).log")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: idleURL)
        #expect(LauncherLogs.list(logs).count == 2)
        #expect(LauncherLogs.list(logs).first(where: { $0.url == activeURL })?.active == true)
        let moved = try LauncherLogs.clean(
            logs, policy: LauncherLogPolicy(totalBytes: 1024), allInactive: true, recovery: recovery)
        #expect(moved == [idleURL])
        #expect(FileManager.default.fileExists(atPath: activeURL.path))
        #expect(FileManager.default.fileExists(atPath: logs.appendingPathComponent("user.log").path))
        #expect(
            try String(contentsOf: recovery.appendingPathComponent(idleURL.lastPathComponent), encoding: .utf8)
                == String(repeating: "i", count: 2048))
        try FileManager.default.moveItem(at: recovery.appendingPathComponent(idleURL.lastPathComponent), to: idleURL)
        #expect(FileManager.default.fileExists(atPath: idleURL.path))
        try active.write(contentsOf: Data(repeating: 65, count: 4096))
        #expect(try LauncherLogs.boundActive(active, maximum: 1024))
        try active.write(contentsOf: Data("tail".utf8))
        let content = try Data(contentsOf: activeURL)
        #expect(content.count < 1024)
        #expect(String(decoding: content, as: UTF8.self).hasSuffix("tail"))
        #expect(!content.contains(0))
        #expect(
            try LauncherLogs.clean(
                logs, policy: LauncherLogPolicy(), protected: [idleURL.path], allInactive: true, recovery: recovery
            ).isEmpty)
        try active.close()
        // Other concurrent Process tests may briefly inherit descriptors between fork and exec.
        // Require eventual release without explicitly unlocking handles inherited by game children.
        let deadline = Date().addingTimeInterval(1)
        while LauncherLogs.list(logs).first(where: { $0.url == activeURL })?.active == true && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(LauncherLogs.list(logs).first(where: { $0.url == activeURL })?.active == false)
    }
    @Test func inheritedWriterSurvivesLauncherHandleClosure() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("\(UUID()).log")
        let handle = try LauncherLogs.create(url, header: "fixture\n")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "/bin/sleep 0.3; /usr/bin/printf inherited-output"]
        child.standardOutput = handle
        child.standardError = handle
        child.standardInput = FileHandle.nullDevice
        try child.run()
        try handle.close()
        #expect(LauncherLogs.list(root).first?.active == true)
        #expect(
            try LauncherLogs.clean(
                root, policy: LauncherLogPolicy(), allInactive: true, recovery: root.appendingPathComponent("Recovery")
            ).isEmpty)
        for _ in 0..<40 where child.isRunning { try await Task.sleep(for: .milliseconds(25)) }
        if child.isRunning { child.terminate() }
        #expect(!child.isRunning)
        #expect(child.terminationStatus == 0)
        #expect(try String(contentsOf: url, encoding: .utf8).hasSuffix("inherited-output"))
        #expect(LauncherLogs.list(root).first?.active == false)
    }
    @Test func ageRetentionAndAppendDescriptorFlags() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("\(UUID()).log")
        let handle = try LauncherLogs.create(url, header: "header")
        #expect(fcntl(handle.fileDescriptor, F_GETFL) & O_APPEND != 0)
        try handle.close()
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
        #expect(
            try LauncherLogs.clean(
                root, policy: LauncherLogPolicy(days: 1), recovery: root.appendingPathComponent("Recovery")
            ).count == 1)
    }
}
