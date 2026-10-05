import AppKit
import SwiftUI
import VNCore

@MainActor @Observable final class LibraryStore {
    var games: [Game] = []
    var collections: [GameCollection] = []
    var progressLinks: [UUID: ProgressLink] = [:]
    var progressMessages: [UUID: String] = [:]
    var progressLinkError: String?
    var progressTasks: [UUID: Task<Void, Never>] = [:]
    var progressWatches: [UUID: SaveWatch] = [:]
    var selectedID: UUID?
    var runner: Runner?
    var bottles: [Bottle] = []
    var sessions: [LaunchSession] = []
    var reports: [UUID: AnalysisReport] = [:]
    var message: String?
    var candidates: [Game] = []
    var showCandidates = false
    var busy = false
    var metadataLoading: Set<UUID> = []
    var metadataStatus: [UUID: String] = [:]
    private var metadataTasks: [UUID: Task<Void, Never>] = [:]
    var scanningID: UUID?
    var scanTask: Task<Void, Never>?
    var writable = true
    let isDemo = ProcessInfo.processInfo.environment["VNLAUNCHER_DEMO"] == "1"
    let root: URL
    private var processes: [UUID: Process] = [:]
    private var logHandles: [UUID: FileHandle] = [:]
    private var logMaintenanceTask: Task<Void, Never>?
    var logPolicy: LauncherLogPolicy {
        LauncherLogPolicy(
            days: UserDefaults.standard.integer(forKey: "logRetentionDays").nonzero(or: 14),
            totalBytes: Int64(UserDefaults.standard.integer(forKey: "logTotalMB").nonzero(or: 64)) * 1024 * 1024,
            activeBytes: Int64(UserDefaults.standard.integer(forKey: "logActiveMB").nonzero(or: 4)) * 1024 * 1024)
    }
    var logsRoot: URL { root.appendingPathComponent("Logs") }
    var activeLogPaths: Set<String> { Set(logHandles.keys.map { logsRoot.appendingPathComponent("\($0).log").path }) }
    func maintainLogs() {
        for handle in logHandles.values {
            do { _ = try LauncherLogs.boundActive(handle, maximum: logPolicy.activeBytes) } catch {
                message = "活跃日志容量检查失败：\(error.localizedDescription)"
            }
        }
        do { try LauncherLogs.clean(logsRoot, policy: logPolicy, protected: activeLogPaths) } catch {
            message = "日志保留未完成：\(error.localizedDescription)"
        }
    }
    func cleanInactiveLogs() throws {
        try LauncherLogs.clean(logsRoot, policy: logPolicy, protected: activeLogPaths, allInactive: true)
    }
    init() {
        let override = ProcessInfo.processInfo.environment["VNLAUNCHER_DATA_DIR"]
        root =
            override.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VNLauncher")
        do {
            let document = try Storage.load(root.appendingPathComponent("library.json"))
            games = document.games
            collections = document.collections ?? []
        } catch {
            writable = false
            message = "读取资料失败；保留原文件并禁止写入。\(error.localizedDescription)"
        }
        let sessionURL = root.appendingPathComponent("sessions.json")
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            do {
                sessions = try JSONDecoder().decode([LaunchSession].self, from: Data(contentsOf: sessionURL)).map {
                    var s = $0
                    if s.exitCode == nil { s.status = "上次会话；当前运行状态未知" }
                    return s
                }
            } catch {
                writable = false
                message = "会话记录读取失败，已保留原文件并禁止覆盖：\(error.localizedDescription)"
            }
        }
        selectedID = isDemo && games.count > 2 ? games[2].id : games.first?.id
        refresh()
        restoreProgressLinks()
        if !isDemo {
            maintainLogs()
            logMaintenanceTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard let self, !Task.isCancelled else { return }
                    self.maintainLogs()
                }
            }
        }
        if !isDemo {
            for game in games where !game.isUtility && game.metadata?.artworkRevision != ArtworkCatalog.revision {
                enrich(game)
            }
        }
    }
    func refresh() {
        scanTask?.cancel()
        reports.removeAll()
        runner = CrossOver.discoverRunner(at: UserDefaults.standard.string(forKey: "runnerPath"))
        bottles = CrossOver.discoverBottles()
    }
    func persist() {
        guard writable else { return }
        do {
            try Storage.save(
                LibraryDocument(games: games, collections: collections), to: root.appendingPathComponent("library.json")
            )
            try Storage.save(sessions, to: root.appendingPathComponent("sessions.json"))
        } catch { message = "保存失败：\(error.localizedDescription)" }
    }
    func update(_ game: Game) {
        guard writable, let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        if games[i].executable != game.executable || games[i].workingDirectory != game.workingDirectory
            || games[i].bottleID != game.bottleID
        {
            reports[game.id] = nil
        }
        games[i] = game
        persist()
    }
    func add(_ game: Game) {
        guard writable else { return }
        if let existing = games.first(where: {
            $0.executable == game.executable && $0.steamAppID == game.steamAppID && $0.bottleID == game.bottleID
        }) {
            selectedID = existing.id
            return
        }
        games.append(game)
        selectedID = game.id
        persist()
        enrich(game)
        scan(game)
    }
    func remove(_ id: UUID) {
        guard writable else { return }
        metadataTasks[id]?.cancel()
        stopProgress(id)
        games.removeAll { $0.id == id }
        selectedID = games.first?.id
        persist()
    }
    func enrich(_ imported: Game, publicDetails: Bool = false) {
        guard !metadataLoading.contains(imported.id) else { return }
        metadataLoading.insert(imported.id)
        metadataTasks[imported.id]?.cancel()
        metadataStatus[imported.id] = "正在查找本地封面和资料…"
        let allowOnline = publicDetails || UserDefaults.standard.bool(forKey: "steamMetadataEnabled")
        let cache = root.appendingPathComponent("Artwork")
        metadataTasks[imported.id] = Task {
            defer { metadataLoading.remove(imported.id) }
            do {
                let worker = Task.detached(priority: .utility) { try MetadataService.local(game: imported) }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                if let current = games.first(where: { $0.id == imported.id }) {
                    try commitMetadata(
                        MetadataService.merge(result, into: current, imported: imported), reason: "本地资料补全")
                }
                metadataStatus[imported.id] = result.coverPath == nil ? "本地未找到明确封面，可手动选择。" : "已补充本地封面，来源见详情。"
                if allowOnline, let metadataID = imported.metadataSteamID {
                    metadataStatus[imported.id] = "正在读取 Steam 公开商店资料…"
                    let remote = try await MetadataService.steam(appID: metadataID, cacheDirectory: cache)
                    try Task.checkCancellation()
                    if let current = games.first(where: { $0.id == imported.id }) {
                        try commitMetadata(
                            MetadataService.merge(remote, into: current, imported: imported), reason: "公开资料刷新")
                    }
                    metadataStatus[imported.id] = "简介已更新，正在读取评论…"
                    var reviews = MetadataResult()
                    reviews.metadata.identity = remote.metadata.identity
                    reviews.metadata.reviews = try await MetadataService.steamReviews(appID: metadataID)
                    try Task.checkCancellation()
                    if let current = games.first(where: { $0.id == imported.id }) {
                        update(MetadataService.merge(reviews, into: current, imported: imported))
                    }
                    metadataStatus[imported.id] = "公开资料已更新；保留手动编辑。"
                }
            } catch is CancellationError {} catch {
                metadataStatus[imported.id] = "自动补全未完成：\(error.localizedDescription)；导入与启动不受影响。"
            }
        }
    }
    func cancelMetadata(_ id: UUID) { metadataTasks[id]?.cancel() }
    func historyURL(_ id: UUID) -> URL { root.appendingPathComponent("MetadataHistory/\(id).json") }
    func commitMetadata(_ edited: Game, reason: String) throws {
        guard writable, let index = games.firstIndex(where: { $0.id == edited.id }) else {
            throw VNError.message("资料库不可写或作品已移除。")
        }
        let current = games[index]
        let updated = MetadataRevision(game: edited, reason: reason).restoring(into: current)
        guard updated != current else { return }
        func substantive(_ game: Game) -> MetadataRevision {
            var revision = MetadataRevision(game: game, reason: "")
            revision.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            revision.date = .distantPast
            revision.metadata?.updatedAt = nil
            revision.metadata?.reviews = nil
            if let origins = revision.metadata?.fieldOrigins {
                revision.metadata?.fieldOrigins = origins.mapValues {
                    var value = $0
                    value.date = nil
                    return value
                }
            }
            return revision
        }
        if substantive(current) != substantive(updated) {
            try MetadataHistory.record(current, reason: reason, at: historyURL(current.id))
        }
        var proposed = games
        proposed[index] = updated
        try Storage.save(
            LibraryDocument(games: proposed, collections: collections), to: root.appendingPathComponent("library.json"))
        games = proposed
    }
    func reorder(_ id: UUID, delta: Int) {
        guard writable, let index = games.firstIndex(where: { $0.id == id }) else { return }
        let visible = games.indices.filter { !games[$0].isUtility }
        guard let current = visible.firstIndex(of: index), visible.indices.contains(current + delta) else { return }
        games.swapAt(index, visible[current + delta])
        persist()
    }
    func moveVisible(_ offsets: IndexSet, to destination: Int) {
        guard writable else { return }
        var visible = games.filter { !$0.isUtility }
        visible.move(fromOffsets: offsets, toOffset: destination)
        games = visible + games.filter(\.isUtility)
        persist()
    }
    func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "选择游戏 EXE 或目录。仅建立引用，不移动游戏。"
        if panel.runModal() == .OK, let url = panel.url { importURL(url) }
    }
    func importURL(_ url: URL) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                let files = try await Task.detached {
                    if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                        return try FileSafety.walk(url).files.filter { $0.pathExtension.lowercased() == "exe" }
                    }
                    guard url.pathExtension.lowercased() == "exe" else { throw VNError.message("请选择 EXE；暂不支持压缩包") }
                    return [url]
                }.value
                candidates = files.map {
                    Game(
                        title: $0.deletingPathExtension().lastPathComponent, executable: $0.path,
                        workingDirectory: $0.deletingLastPathComponent().path)
                }
                if candidates.isEmpty {
                    message = "扫描范围内没有 EXE。请选择实际启动程序。"
                } else if candidates.count == 1 {
                    add(candidates[0])
                } else {
                    showCandidates = true
                }
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    func discoverSteam() {
        let snapshot = bottles
        busy = true
        Task {
            do {
                candidates = try await Task.detached { try snapshot.flatMap { try CrossOver.steamGames(in: $0) } }.value
                if candidates.isEmpty {
                    message = "Steam 已声明的库内没有可导入游戏；外部盘需在线，路径需有有效驱动器映射。"
                } else {
                    showCandidates = true
                }
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    func chooseRunner() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.message = "选择已有 CrossOver.app"
        if panel.runModal() == .OK, let url = panel.url {
            guard let value = CrossOver.discoverRunner(at: url.path) else {
                message = "此应用没有可用 CrossOver 包装器"
                return
            }
            UserDefaults.standard.set(url.path, forKey: "runnerPath")
            runner = value
        }
    }
    func launch(_ game: Game) {
        guard !isDemo else { return }
        do {
            guard writable else { throw VNError.message("资料存储只读，未提交启动。请先处理读取错误。") }
            guard let runner = CrossOver.discoverRunner(at: runner?.appPath),
                let bottle = CrossOver.discoverBottles().first(where: { $0.id == game.bottleID })
            else { throw VNError.message("请在游戏详情选择现有容器，并确认 CrossOver 可用。") }
            guard !sessions.contains(where: { $0.gameID == game.id && processes[$0.id]?.isRunning == true }) else {
                throw VNError.message("该游戏的启动包装器仍在运行，未重复提交。")
            }
            guard logHandles.count < 128 else { throw VNError.message("本次启动器会话已保护 128 份日志；请稍后重新打开启动器再提交新启动。") }
            let command = try CrossOver.command(game: game, bottle: bottle, runner: runner)
            let id = UUID()
            let log = root.appendingPathComponent("Logs/\(id).log")
            let header =
                "VNLauncher session \(id)\nCrossOver \(runner.version) / \(bottle.name)\n仅记录启动包装器；进程退出不代表游戏退出或兼容。\n日志容量仅在启动器存活时每 15 秒检查；关闭后输出继续写入文件。\n"
            let handle = try LauncherLogs.create(log, header: header)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: command.directory)
            process.standardOutput = handle
            process.standardError = handle
            process.standardInput = FileHandle.nullDevice
            var session = LaunchSession(
                gameID: game.id, runnerVersion: runner.version, bottleName: bottle.name, status: "进程已提交 · 游戏运行待确认",
                logPath: log.path)
            session.id = id
            process.terminationHandler = { [weak self] p in
                let code = p.terminationStatus
                Task { @MainActor in
                    guard let self, let index = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                    self.sessions[index].exitCode = code
                    self.sessions[index].status = code == 0 ? "启动包装器已退出 · 游戏状态未知" : "启动包装器失败（\(code)）· 查看日志"
                    self.processes[id] = nil
                    // Wine can hand stdout to descendants after the wrapper exits. Retain the append handle
                    // until the launcher exits so those logs stay protected and bounded while it is open.
                    self.persist()
                }
            }
            sessions.insert(session, at: 0)
            do {
                try process.run()
                processes[id] = process
                logHandles[id] = handle
            } catch {
                try? handle.close()
                sessions[0].status = "启动失败：" + error.localizedDescription
                persist()
                throw error
            }
            var changed = game
            changed.lastLaunched = Date()
            update(changed)
            persist()
        } catch { message = error.localizedDescription }
    }
    func scan(_ game: Game) {
        scanTask?.cancel()
        scanningID = game.id
        let bottle = bottles.first { $0.id == game.bottleID }
        let runner = runner
        scanTask = Task {
            let worker = Task.detached(priority: .utility) {
                try Analyzer.scan(game: game, bottle: bottle, runner: runner)
            }
            do {
                let report = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard let latest = games.first(where: { $0.id == game.id }),
                    GameConfiguration.sameAnalysisInputs(latest, game),
                    bottles.first(where: { $0.id == latest.bottleID }) == bottle,
                    self.runner?.appPath == runner?.appPath, self.runner?.version == runner?.version
                else {
                    if scanningID == game.id { scanningID = nil }
                    return
                }
                reports[game.id] = report
                try Storage.save(report, to: root.appendingPathComponent("Reports/\(game.id).json"))
            } catch is CancellationError {} catch { message = error.localizedDescription }
            if scanningID == game.id { scanningID = nil }
        }
    }
    func choosePath(directory: Bool, message: String) -> String? {
        let p = NSOpenPanel()
        p.canChooseFiles = !directory
        p.canChooseDirectories = directory
        p.message = message
        return p.runModal() == .OK ? p.url?.path : nil
    }
}

extension Int { fileprivate func nonzero(or fallback: Int) -> Int { self > 0 ? self : fallback } }
