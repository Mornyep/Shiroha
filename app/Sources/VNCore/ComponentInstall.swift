import Foundation

public struct ComponentGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let findings: [Finding]
    public var unresolved: [Finding] { findings.filter { $0.state != .detected } }
    public var summary: String {
        if unresolved.isEmpty { return "已找到同架构候选" }
        if unresolved.contains(where: { $0.state == .missing }) { return "有确认缺失项" }
        if unresolved.contains(where: { $0.state == .conflict }) { return "有架构或加载冲突" }
        return "有未找到或待验证项"
    }
}
public enum ComponentInventory {
    public static func groups(_ report: AnalysisReport) -> [ComponentGroup] {
        let families: [(String, String, (Finding) -> Bool)] = [
            (
                "vc14", "Visual C++ v14",
                {
                    $0.component.hasPrefix("vcruntime140") || $0.component.hasPrefix("msvcp140")
                        || $0.component.hasPrefix("concrt140")
                }
            ),
            (
                "directx", "旧 DirectX 可选组件",
                {
                    $0.component.hasPrefix("d3dx") || $0.component.hasPrefix("xinput1_")
                        || $0.component.hasPrefix("xaudio2_") || $0.component.hasPrefix("d3dcompiler_")
                }
            ),
            ("records", "容器安装记录", { $0.component == "安装记录" }),
            ("other", "系统依赖与其他线索", { _ in true }),
        ]
        var remaining = report.findings
        return families.compactMap { id, title, predicate in
            var seen = Set<String>()
            let matched = remaining.filter(predicate).filter {
                seen.insert($0.component + ($0.architecture ?? "") + $0.state.rawValue + $0.evidence).inserted
            }
            remaining.removeAll(where: predicate)
            return matched.isEmpty ? nil : ComponentGroup(id: id, title: title, findings: matched)
        }
    }
}
public struct VCInstallPlan: Codable, Sendable {
    public let source: Bottle
    public let destination: Bottle
    public let architecture: String
    public let download: URL
    public let reportFingerprint: String
    public static func eligibleArchitectures(_ report: AnalysisReport) -> [String] {
        let facts = ComponentInventory.groups(report).first { $0.id == "vc14" }?.unresolved ?? []
        return Array(
            Set(
                facts.filter {
                    $0.state == .missing
                        || ($0.state == .verify && $0.evidence.contains("未找到") && !$0.evidence.contains("另有"))
                }.compactMap(\.architecture))
        ).filter { ["x86", "x64"].contains($0) }.sorted()
    }
    public init(
        report: AnalysisReport, bottle: Bottle, architecture: String,
        destinationName: String = "VN-Repair-" + UUID().uuidString
    ) throws {
        guard ["x86", "x64"].contains(architecture),
            report.architecture.components(separatedBy: " / ").contains(architecture)
        else { throw VNError.message("组件架构与扫描结果不匹配") }
        guard Self.eligibleArchitectures(report).contains(architecture) else {
            throw VNError.message("没有待核验的 VC++ v14 依赖，不重复安装")
        }
        guard ["win10", "win11"].contains(bottle.configuration["WindowsVersion"] ?? "") else {
            throw VNError.message("此官方包要求 Windows 10/11 容器；不会自动修改 Windows 版本")
        }
        guard destinationName.hasPrefix("VN-Repair-"),
            destinationName.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
            destinationName != bottle.name
        else { throw VNError.message("副本名称无效") }
        source = bottle
        self.architecture = architecture
        destination = Bottle(
            name: destinationName,
            path: URL(fileURLWithPath: bottle.path).deletingLastPathComponent().appendingPathComponent(destinationName)
                .path, configuration: bottle.configuration)
        download = URL(string: "https://aka.ms/vc14/vc_redist.\(architecture).exe")!
        reportFingerprint = report.fingerprint
    }
    public func remap(_ original: Game) -> Game {
        var game = original
        func path(_ value: String) -> String {
            value.hasPrefix(source.path + "/") ? destination.path + value.dropFirst(source.path.count) : value
        }
        game.bottleID = destination.id
        game.executable = path(game.executable)
        game.workingDirectory = path(game.workingDirectory)
        // External save paths are intentionally not rewritten or described as backed up.
        return game
    }
}
public struct InstallReceipt: Codable, Sendable {
    public let sourceBottle: String
    public let destinationBottle: String
    public let architecture: String
    public let downloadURL: String
    public let sha256: String
    public let exitCode: Int32
    public let created: Date
}
public enum ComponentInstaller {
    public static func checkIdle(bottle: Bottle, runner: Runner, log: URL) async throws -> Bool {
        try await run(
            runner.executable,
            ["--no-lock", "--bottle", bottle.name, "--scope", "private", "--ux-app", "wineserver", "-k0"], log: log,
            seconds: 15) == 1
    }
    public static func trustedDownload(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else {
            return false
        }
        return host == "download.microsoft.com" || host == "download.visualstudio.microsoft.com" || host == "aka.ms"
            || host.hasSuffix(".download.microsoft.com")
    }
    // This only terminates the exact child process on timeout/cancellation, never Wine globally.
    static func run(_ executable: String, _ arguments: [String], log: URL, seconds: Double = 300) async throws -> Int32
    {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(seconds)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else {
                    throw VNError.message("步骤超时；仅停止本步骤进程。副本可能有残留进程，请在 CrossOver 检查，不会自动终止其他游戏。")
                }
                try await Task.sleep(for: .milliseconds(150))
            }
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }
        return process.terminationStatus
    }
    public static func install(
        plan: VCInstallPlan, game: Game, report: AnalysisReport, runner: Runner, directory: URL,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> InstallReceipt {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard plan.reportFingerprint == report.fingerprint, game.id == report.gameID, game.bottleID == plan.source.id,
            !fm.fileExists(atPath: plan.destination.path),
            FileSafety.contained(URL(fileURLWithPath: plan.source.path), in: CrossOver.bottlesRoot),
            URL(fileURLWithPath: plan.source.path).resolvingSymlinksInPath().path == plan.source.path
        else { throw VNError.message("容器位置已变化或副本已存在，未执行") }
        try Storage.save(plan, to: directory.appendingPathComponent("plan.json"))
        let current = try Analyzer.scan(game: game, bottle: plan.source, runner: runner)
        func facts(_ value: AnalysisReport) -> [String] {
            value.findings.map { $0.component + ($0.architecture ?? "") + $0.state.rawValue + $0.evidence }.sorted()
        }
        guard facts(current) == facts(report), current.fingerprint == report.fingerprint,
            current.bottleFingerprint == report.bottleFingerprint, current.runnerVersion == report.runnerVersion
        else { throw VNError.message("扫描证据已变化，请重新扫描后确认") }
        func requireStopped() async throws {
            let code = try await run(
                runner.executable,
                ["--no-lock", "--bottle", plan.source.name, "--scope", "private", "--ux-app", "wineserver", "-k0"],
                log: directory.appendingPathComponent("idle-check.log"), seconds: 15)
            guard code == 1 else {
                throw VNError.message(code == 0 ? "源容器仍在运行，请先正常退出游戏和 Steam；不会强制关闭。" : "无法确认源容器已停止，未复制或安装。")
            }
        }
        try await requireStopped()
        await progress("下载微软官方 VC++ \(plan.architecture)…")
        let file = directory.appendingPathComponent("vc_redist.\(plan.architecture).exe")
        let downloadLog = directory.appendingPathComponent("download.log")
        let code = try await run(
            "/usr/bin/curl",
            [
                "--fail", "--silent", "--show-error", "--location", "--max-redirs", "4", "--proto", "=https",
                "--proto-redir", "=https", "--max-time", "120", "--max-filesize", "67108864", "--output", file.path,
                "--write-out", "%{url_effective}", plan.download.absoluteString,
            ], log: downloadLog, seconds: 130)
        guard code == 0,
            let finalURL = URL(
                string: try String(contentsOf: downloadLog, encoding: .utf8).trimmingCharacters(
                    in: .whitespacesAndNewlines)), trustedDownload(finalURL)
        else { throw VNError.message("官方下载失败或最终来源不在微软允许列表；未运行安装器") }
        let data = try FileSafety.read(file, limit: 64 * 1024 * 1024)
        _ = try PEReader.parse(data)
        let digest = FileSafety.fingerprint(data)
        try await requireStopped()
        await progress("建立独立容器副本，原容器保留…")
        // APFS clone, no source-bottle shutdown command and no symlink traversal.
        guard
            try await run(
                "/bin/cp", ["-cR", plan.source.path, plan.destination.path],
                log: directory.appendingPathComponent("copy.log"), seconds: 600) == 0
        else { throw VNError.message("文件系统副本未完成；保留现场，未安装。需要支持克隆的 APFS 卷。") }
        try await requireStopped()
        let after = try Analyzer.scan(game: game, bottle: plan.source, runner: runner)
        guard after.fingerprint == report.fingerprint, after.bottleFingerprint == report.bottleFingerprint else {
            throw VNError.message("复制期间源证据变化，已停止；副本保留供检查，未安装")
        }
        let copiedRoot = URL(fileURLWithPath: plan.destination.path)
        for relative in [
            "cxbottle.conf", "system.reg", "user.reg", "drive_c", "drive_c/windows", "drive_c/windows/system32",
            "dosdevices/c:",
        ] {
            guard FileSafety.contained(copiedRoot.appendingPathComponent(relative), in: copiedRoot) else {
                throw VNError.message("副本的关键路径映射到容器外，已停止安装：" + relative)
            }
        }
        let tool = URL(fileURLWithPath: runner.executable).deletingLastPathComponent().appendingPathComponent(
            "cxbottle"
        ).path
        guard
            try await run(
                tool, ["--bottle", plan.destination.name, "--restored", "--new-uuid", "--no-update"],
                log: directory.appendingPathComponent("register.log"), seconds: 120) == 0
        else { throw VNError.message("副本注册失败，未运行安装器；原容器未修改") }
        await progress("在 \(plan.destination.name) 安装；可能显示微软安装窗口…")
        let exit = try await run(
            runner.executable,
            ["--bottle", plan.destination.name, "--no-update", file.path, "/install", "/passive", "/norestart"],
            log: directory.appendingPathComponent("installer.log"), seconds: 600)
        let receipt = InstallReceipt(
            sourceBottle: plan.source.path, destinationBottle: plan.destination.path, architecture: plan.architecture,
            downloadURL: finalURL.absoluteString, sha256: digest, exitCode: exit, created: Date())
        try Storage.save(receipt, to: directory.appendingPathComponent("receipt.json"))
        guard exit == 0 else { throw VNError.message("安装器退出码 \(exit)。未切换游戏容器；副本与日志已保留。需要重启的状态也须人工核验。") }
        return receipt
    }
}
