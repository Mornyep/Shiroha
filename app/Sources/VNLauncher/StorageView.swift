import AppKit
import SwiftUI
import VNCore

struct StorageView: View {
    @Bindable var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var scan: StorageScan?
    @State private var receipt: StorageReceipt?
    @State private var extra: [String] = []
    @State private var busy = false
    @State private var status = ""
    @State private var savesConfirmed = false
    @State private var closedGame = false
    @State private var showAI = false
    @State private var advice: SaveAdvice?
    @State private var showUninstall = false
    @State private var confirmTitle = ""
    @State private var aiTask: Task<Void, Never>?
    private var game: Game? { store.games.first { $0.id == selected } }
    private var free: Int64? {
        try? URL(fileURLWithPath: game?.workingDirectory ?? store.root.path).resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ]).volumeAvailableCapacityForImportantUsage
    }
    private func size(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelHeading(
                    title: "空间管理", subtitle: "先确认存档，再整理游戏本体", symbol: "externaldrive", coverPath: game?.coverPath)
                Spacer()
                Button("完成") { dismiss() }.disabled(busy)
            }
            if let free {
                Text("游戏所在磁盘可用 " + size(free) + (free < 20 * 1024 * 1024 * 1024 ? " · 空间偏低，可选择已通关作品整理" : ""))
                    .foregroundStyle(free < 20 * 1024 * 1024 * 1024 ? .orange : .secondary)
            }
            Picker("选择作品", selection: $selected) {
                Text("请选择").tag(nil as UUID?)
                ForEach(store.games.filter { !$0.isUtility }) {
                    Text($0.displayTitle + " · " + $0.state.rawValue).tag(Optional($0.id))
                }
            }.disabled(busy)
            HStack {
                Button("扫描本体与存档候选") { startScan() }.disabled(game == nil || busy)
                Button("补充存档目录…") {
                    if let path = store.choosePath(directory: true, message: "选择你确认属于本作品的存档目录") {
                        extra.append(path)
                        startScan()
                    }
                }.disabled(game == nil || busy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let scan {
                        Text("本体文件约 " + size(scan.bytes)).font(.headline)
                        Text(scan.directory).font(.caption).textSelection(.enabled)
                        Text("预计释放量受文件系统快照、共享数据和卸载器影响，以卸载后磁盘读回为准。").font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text("保留存档候选 · \(scan.candidates.count) 处").font(.headline)
                        ForEach(scan.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: "checkmark.shield")
                                    Text(URL(fileURLWithPath: candidate.path).lastPathComponent).font(.headline)
                                    Spacer()
                                    Text(size(candidate.bytes)).foregroundStyle(.secondary)
                                }
                                Text(candidate.path).font(.caption).textSelection(.enabled)
                                Text("\(candidate.fileCount) 个文件 · " + candidate.reason).font(.caption).foregroundStyle(
                                    .secondary)
                                if advice?.keepIDs.contains(candidate.id) == true {
                                    Text("AI 建议保留").font(.caption).foregroundStyle(.teal)
                                }
                            }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        }
                        ForEach(scan.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                        Button("用 Codex 筛选存档候选…") { showAI = true }.disabled(scan.candidates.isEmpty || busy)
                        if let advice {
                            Text(advice.explanation).font(.callout)
                            Text("为避免误删，全部本地候选仍会备份，AI 不取消任何候选。").font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle(
                            scan.candidates.isEmpty ? "我已确认此作品没有需要保留的本地存档" : "我已核对这些位置，并补充了需要保留的其他存档",
                            isOn: $savesConfirmed
                        ).disabled(busy)
                        Toggle("游戏和对应容器内的 Steam 已正常退出，整理期间不再启动", isOn: $closedGame).disabled(busy)
                        Button(scan.candidates.isEmpty ? "保存清理预览记录…" : "备份全部候选并逐文件校验…") { archive() }.disabled(
                            !savesConfirmed || !closedGame || busy)
                        if let receipt {
                            Text("已完成 \(receipt.archives.count) 处存档副本校验；原始位置与哈希已记录。").foregroundStyle(.teal)
                            Button(game?.kind == .steam ? "继续到 Steam 卸载确认…" : "将本体移到废纸篓…") {
                                confirmTitle = ""
                                showUninstall = true
                            }.disabled(busy || store.isDemo)
                            Text(
                                game?.kind == .steam
                                    ? "只打开所选游戏的 Steam 卸载流程；最终确认在 Steam 中完成，不把打开窗口算作卸载成功。"
                                    : "先移到废纸篓，可恢复。此步骤不会立即释放磁盘容量；清空废纸篓必须由你另行决定。"
                            ).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("先选择作品。只扫描指定游戏目录与对应 Steam 存档位置，不遍历整个 Mac，也不会自动卸载。").foregroundStyle(.secondary)
                    }
                    if !status.isEmpty { Text(status).font(.callout).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if busy { ProgressView("处理中…") }
        }.padding(28).frame(width: 760, height: 610).editorSurface(coverPath: game?.coverPath)
            .onAppear { selected = store.selectedID ?? store.games.first(where: { !$0.isUtility })?.id }
            .onChange(of: selected) { _, _ in
                scan = nil
                receipt = nil
                extra = []
                advice = nil
                savesConfirmed = false
                closedGame = false
                status = ""
            }
            .interactiveDismissDisabled(busy)
            .sheet(isPresented: $showAI) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("确认存档候选摘要").font(.title2)
                    Text("使用 Codex / ChatGPT 订阅。只发送下面的目录末级名称、候选 ID、数量与识别依据，不发送完整路径或存档内容。")
                    ScrollView {
                        Text(
                            scan.flatMap { try? SaveAdvisor.payload($0) }.map { String(decoding: $0, as: UTF8.self) }
                                ?? "无候选"
                        ).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    HStack {
                        Button("取消") { showAI = false }
                        Spacer()
                        Button("同意本次发送并筛选") {
                            showAI = false
                            requestAI()
                        }
                    }
                }.padding(24).frame(width: 620, height: 460)
            }
            .sheet(isPresented: $showUninstall) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("确认所选作品").font(.title2)
                    Text(game?.displayTitle ?? "")
                    Text(scan?.directory ?? "").font(.caption).textSelection(.enabled)
                    Text("请再次核对存档备份。将处理上面的本体目录；不会自动清空废纸篓或宣称已经释放空间。")
                    TextField("输入作品完整显示名以确认", text: $confirmTitle)
                    HStack {
                        Button("取消") { showUninstall = false }
                        Spacer()
                        Button(game?.kind == .steam ? "打开 Steam 卸载确认" : "移到废纸篓", role: .destructive) {
                            showUninstall = false
                            uninstall()
                        }.disabled(confirmTitle != game?.displayTitle)
                    }
                }.padding(24).frame(width: 600)
            }.onDisappear { aiTask?.cancel() }
    }
    private func startScan() {
        guard let game else { return }
        busy = true
        receipt = nil
        advice = nil
        savesConfirmed = false
        status = ""
        let library = store.games
        let extra = extra
        Task {
            defer { busy = false }
            do {
                scan = try await Task.detached {
                    try StorageManagement.scan(game: game, library: library, additional: extra)
                }.value
            } catch {
                scan = nil
                status = error.localizedDescription
            }
        }
    }
    private func requestAI() {
        guard let scan else { return }
        busy = true
        aiTask = Task {
            defer { busy = false }
            do {
                advice = try await SaveAdvisor.suggest(
                    scan, model: UserDefaults.standard.string(forKey: "codexModel") ?? "")
            } catch { status = "AI 未完成：" + error.localizedDescription }
        }
    }
    private func archive() {
        guard let scan, let parent = store.choosePath(directory: true, message: "选择游戏目录外的备份父目录，建议另一块磁盘") else { return }
        busy = true
        let destination = URL(fileURLWithPath: parent).appendingPathComponent("VNSaves-" + UUID().uuidString)
        Task {
            defer { busy = false }
            do {
                receipt = try await Task.detached { try StorageManagement.archive(scan, to: destination) }.value
                status = "备份与清单：" + destination.path
            } catch {
                receipt = nil
                status = "未完成备份，不允许卸载：" + error.localizedDescription
            }
        }
    }
    private func uninstall() {
        guard let game, let receipt, let runner = store.runner,
            let bottle = store.bottles.first(where: { $0.id == game.bottleID }), closedGame, savesConfirmed
        else {
            status = "配置或确认条件已变化，请重新扫描"
            return
        }
        busy = true
        let library = store.games
        let logRoot = store.root.appendingPathComponent("StorageOperations/" + UUID().uuidString)
        Task {
            defer { busy = false }
            do {
                try FileManager.default.createDirectory(at: logRoot, withIntermediateDirectories: true)
                let idle = try await ComponentInstaller.checkIdle(
                    bottle: bottle, runner: runner, log: logRoot.appendingPathComponent("idle.log"))
                guard idle else { throw VNError.message("容器尚未停止或状态未知，未卸载。请正常退出后再试。") }
                try await Task.detached {
                    try StorageManagement.verifyBeforeUninstall(receipt: receipt, game: game, library: library)
                }.value
                if game.kind == .steam {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: runner.executable)
                    p.arguments = [
                        "--bottle", bottle.name, "--no-update", game.executable, "steam://uninstall/" + game.steamAppID,
                    ]
                    p.standardOutput = FileHandle.nullDevice
                    p.standardError = FileHandle.nullDevice
                    try p.run()
                    status = "已请求 Steam 显示该作品的卸载确认。尚未确认卸载完成；存档备份保留。"
                } else {
                    var trashed: NSURL?
                    try FileManager.default.trashItem(
                        at: URL(fileURLWithPath: game.workingDirectory), resultingItemURL: &trashed)
                    status = "本体已移到废纸篓，可恢复；尚未释放磁盘空间。存档副本保留。"
                }
                self.receipt = nil
            } catch { status = "停止处理：" + error.localizedDescription }
        }
    }
}
