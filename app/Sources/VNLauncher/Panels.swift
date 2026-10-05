import AppKit
import SwiftUI
import VNCore

struct CandidateView: View {
    @Bindable var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeading(title: "导入作品", subtitle: "选择真正的启动入口", symbol: "square.and.arrow.down")
            Text("目录可能含安装器或卸载程序。只添加你明确选择的项目，不会运行它。 ").foregroundStyle(.secondary)
            List(store.candidates) { game in
                HStack {
                    VStack(alignment: .leading) {
                        Text(game.displayTitle)
                        Text(game.kind == .steam ? "Steam \(game.steamAppID) · \(game.source)" : game.executable).font(
                            .caption
                        ).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("添加") {
                        store.add(game)
                        dismiss()
                    }
                }
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
            }
        }.padding(28).frame(width: 720, height: 520).editorSurface()
    }
}
struct DetailView: View {
    @Bindable var store: LibraryStore
    let original: Game
    @State private var game: Game
    @State private var args: String
    @State private var configurationTab = "作品"
    @State private var configurationError: String?
    @State private var titleEdited = false
    @State private var coverEdited = false
    @State private var storage = false
    @State private var remove = false
    @State private var backupBusy = false
    @State private var backupMessage = ""
    @State private var backupConfirm = false
    @Environment(\.dismiss) private var dismiss
    init(store: LibraryStore, original: Game) {
        self.store = store
        self.original = original
        _game = State(initialValue: original)
        _args = State(initialValue: original.arguments.joined(separator: "\n"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelHeading(
                    title: "作品配置", subtitle: game.displayTitle, symbol: "slider.horizontal.3", coverPath: game.coverPath
                )
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    do {
                        game.arguments = args.components(separatedBy: .newlines).filter { !$0.isEmpty }
                        try store.saveConfiguration(
                            game, original: original, titleEdited: titleEdited, coverEdited: coverEdited)
                        dismiss()
                    } catch { configurationError = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(
                    game.title.trimmingCharacters(in: .whitespaces).isEmpty || !store.writable)
            }
            if let configurationError { Text(configurationError).font(.caption).foregroundStyle(.red) }
            PanelTabs(items: ["作品", "启动", "运行记录", "存档与空间"], selection: $configurationTab)
            Form {
                if configurationTab == "作品" {
                    Section("资料") {
                        TextField(
                            "标题",
                            text: Binding(
                                get: { game.title },
                                set: {
                                    game.title = $0
                                    titleEdited = true
                                }))
                        TextField("别名 / 版本", text: $game.alias)
                        Picker("游玩状态", selection: $game.state) {
                            ForEach(LibraryState.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("收藏", isOn: $game.favorite)
                        HStack {
                            Text(game.coverPath == nil ? "未设置封面" : "已引用本地封面")
                            Spacer()
                            Button("选择封面…") {
                                if let p = store.choosePath(directory: false, message: "选择本地封面图片") {
                                    game.coverPath = p
                                    coverEdited = true
                                    if game.metadata == nil { game.metadata = GameMetadata() }
                                    game.metadata?.coverSource = "手动选择"
                                }
                            }
                        }
                    }
                    Section("自动补全与来源") {
                        Button("补全缺少的封面与公开资料") { store.enrich(game) }
                        if let status = store.metadataStatus[game.id] { Text(status).font(.caption) }
                        if let current = store.games.first(where: { $0.id == game.id }), let meta = current.metadata {
                            if let summary = meta.summary { Text(summary).textSelection(.enabled) }
                            if let developer = meta.developer { LabeledContent("开发", value: developer) }
                            if let publisher = meta.publisher { LabeledContent("发行", value: publisher) }
                            if let date = meta.releaseDate { LabeledContent("发行日期", value: date) }
                            if let source = meta.coverSource {
                                Text("封面来源：" + source).font(.caption).textSelection(.enabled)
                            }
                            if let source = meta.backgroundSource {
                                Text("背景来源：" + source).font(.caption).textSelection(.enabled)
                            }
                            if let source = meta.localizedTitleSource {
                                Text("中文显示名来源：" + source).font(.caption).textSelection(.enabled)
                            }
                            if let source = meta.detailSource, let url = PublicLink.url(source) {
                                Link("打开资料来源", destination: url)
                            }
                        }
                        Text("先读本地文件和 Steam 缓存；可在设置开启按 App ID 获取公开商店资料。手动编辑优先。 ").font(.caption).foregroundStyle(
                            .secondary)
                    }
                }
                if configurationTab == "启动" {
                    Section("启动配置") {
                        Picker("入口方式", selection: $game.kind) {
                            ForEach(EntryKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        if game.kind == .steam {
                            TextField("Steam App ID", text: $game.steamAppID)
                            Text("启动程序应选择容器内 steam.exe；工作目录选择实际游戏目录。").font(.caption).foregroundStyle(.secondary)
                        }
                        Picker(
                            "CrossOver 容器",
                            selection: Binding(
                                get: { game.bottleID ?? "" }, set: { game.bottleID = $0.isEmpty ? nil : $0 })
                        ) {
                            Text("请选择，不使用默认容器").tag("")
                            ForEach(store.bottles) { Text($0.name).tag($0.id) }
                        }
                        if let id = game.bottleID, !store.bottles.contains(where: { $0.id == id }) {
                            Text("原容器不可用，请重新选择。").foregroundStyle(.orange)
                        }
                        pathRow("启动程序", value: game.executable) {
                            if let p = store.choosePath(directory: false, message: "重新定位启动 EXE") { game.executable = p }
                        }
                        pathRow("工作目录", value: game.workingDirectory) {
                            if let p = store.choosePath(directory: true, message: "选择游戏工作目录") {
                                game.workingDirectory = p
                            }
                        }
                        Text("附加参数：每行一个参数，不使用 Shell 引号或转义。").font(.caption)
                        TextEditor(text: $args).font(.system(.body, design: .monospaced)).frame(height: 65)
                        Text(game.source).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if configurationTab == "运行记录" {
                    Section("本地检查与日志") {
                        Button("在 Finder 显示游戏") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: game.executable)])
                        }
                        ForEach(store.sessions.filter { $0.gameID == game.id }.prefix(8)) { session in
                            VStack(alignment: .leading) {
                                Text(session.status)
                                HStack {
                                    Text(session.started.formatted()).font(.caption).foregroundStyle(.secondary)
                                    Button("打开日志") { NSWorkspace.shared.open(URL(fileURLWithPath: session.logPath)) }
                                }
                            }
                        }
                        Text("关闭本应用不会终止游戏；这里不提供全局停止 Wine。OP/ED、声音、输入、存读档未实测。 ").font(.caption).foregroundStyle(
                            .secondary)
                    }
                    Section("手动实测记录") {
                        ForEach(["实际游戏窗口", "输入与退出", "OP / ED", "声音", "文字显示", "存档与读档"], id: \.self) { item in
                            Toggle(
                                item,
                                isOn: Binding(
                                    get: { game.runtimeChecks?[item] ?? false },
                                    set: {
                                        if game.runtimeChecks == nil { game.runtimeChecks = [:] }
                                        game.runtimeChecks?[item] = $0
                                    }))
                        }
                        Text("仅在你实际验证后勾选；独立于静态扫描和游玩状态，保存后作为你的手动记录。 ").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if configurationTab == "存档与空间" {
                    Section("存档副本") {
                        pathRow("已确认存档目录", value: game.saveDirectory ?? "未选择") {
                            game.saveDirectory = store.choosePath(directory: true, message: "选择你确认的存档目录；不会自动推测")
                        }
                        Button("校验备份到新目录…") { backupConfirm = true }.disabled(game.saveDirectory == nil || backupBusy)
                        Button("验证恢复到独立新目录…") { restoreCopy() }.disabled(backupBusy)
                        if backupBusy { ProgressView("复制并校验中…") }
                        if !backupMessage.isEmpty { Text(backupMessage).font(.caption).textSelection(.enabled) }
                        Text("仅覆盖你选择的目录；跳过符号链接，不覆盖现有文件。备份前请退出游戏。 ").font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("空间管理 · 保留存档后卸载…") {
                            store.selectedID = game.id
                            storage = true
                        }
                        Button("从游戏库移除…", role: .destructive) { remove = true }
                    }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
        }.padding(28).frame(width: 760, height: 610).editorSurface(coverPath: game.coverPath)
            .onChange(of: store.games.first(where: { $0.id == game.id })) { _, latest in
                guard let latest else { return }
                if !coverEdited { game.coverPath = latest.coverPath }
                if !titleEdited { game.title = latest.title }
                game.metadata = latest.metadata
                if coverEdited {
                    if game.metadata == nil { game.metadata = GameMetadata() }
                    game.metadata?.coverSource = "手动选择"
                }
            }
            .sheet(isPresented: $storage) { StorageView(store: store) }
            .confirmationDialog("只移除资料项，游戏和存档文件不会删除。", isPresented: $remove) {
                Button("移除资料项", role: .destructive) {
                    store.remove(game.id)
                    dismiss()
                }
            }
            .confirmationDialog("请确认游戏已经退出，存档目录没有正在写入。", isPresented: $backupConfirm) {
                Button("已退出，选择备份位置") {
                    if let path = game.saveDirectory { performCopy(source: URL(fileURLWithPath: path)) }
                }
            }
    }
    private func pathRow(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                Spacer()
                Button("选择…", action: action)
            }
            Text(value).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
        }
    }
    private func restoreCopy() {
        if let p = store.choosePath(directory: true, message: "选择要验证恢复的备份目录；只复制到新位置，不覆盖原存档") {
            performCopy(source: URL(fileURLWithPath: p))
        }
    }
    private func performCopy(source: URL) {
        guard let parent = store.choosePath(directory: true, message: "选择父目录；将在其中建立新的 VNBackup 子目录") else { return }
        let destination = URL(fileURLWithPath: parent).appendingPathComponent("VNBackup-" + UUID().uuidString)
        backupBusy = true
        Task {
            do {
                let result = try await Task.detached {
                    try SaveBackup.copyAndVerify(source: source, destination: destination)
                }.value
                try Storage.save(
                    result, to: store.root.appendingPathComponent("Backups/\(destination.lastPathComponent).json"))
                backupMessage = "已逐文件校验 \(result.hashes.count) 项：\(destination.path)"
            } catch { backupMessage = "未完成：\(error.localizedDescription)" }
            backupBusy = false
        }
    }
}
struct AnalysisView: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    @State private var showPayload = false
    @State private var advice: AdviceResponse?
    @State private var errorText = ""
    @State private var aiTask: Task<Void, Never>?
    @State private var aiBusy = false
    @State private var installPlan: VCInstallPlan?
    @State private var installConfirmation = false
    @State private var installBusy = false
    @State private var installStatus = ""
    @State private var installedGame: Game?
    @State private var installedReport: AnalysisReport?
    @State private var acceptedBoundary = false
    @Environment(\.dismiss) private var dismiss
    private var game: Game? { store.games.first { $0.id == gameID } }
    private var report: AnalysisReport? { store.reports[gameID] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelHeading(
                    title: "兼容检查", subtitle: game?.displayTitle ?? "游戏不可用", symbol: "checkmark.shield",
                    coverPath: game?.coverPath)
                Spacer()
                Button("关闭") { dismiss() }.disabled(installBusy)
            }
            HStack {
                Button(report == nil ? "开始本地扫描" : "重新扫描") {
                    if let game {
                        advice = nil
                        store.scan(game)
                    }
                }.disabled(store.scanningID != nil || aiBusy || installBusy)
                if store.scanningID == gameID {
                    ProgressView().controlSize(.small)
                    Text("只读扫描，最多 4000 项").font(.caption)
                    Button("取消") { store.scanTask?.cancel() }
                }
                Spacer()
                Button("查看外发摘要…") { showPayload = true }.disabled(
                    report == nil || aiBusy || installBusy || store.scanningID != nil)
            }
            if let report {
                Text(
                    "\(report.date.formatted()) · \(report.architecture) · CrossOver \(report.runnerVersion) · 静态快照，变化后请重新扫描"
                ).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        DisclosureGroup("扫描范围与限制") {
                            ForEach(report.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                        HStack(spacing: 24) {
                            metric("确认缺失", report.findings.filter { $0.state == .missing }.count, .red)
                            metric(
                                "待核验",
                                report.findings.filter { $0.state == .verify || $0.state == .conflict }.filter {
                                    $0.component != "安装记录"
                                }.count, .orange)
                            metric("候选已找到", report.findings.filter { $0.state == .detected }.count, .secondary)
                        }.padding(.vertical, 6)
                        Text("未找到候选 ≠ 确认缺失。先看下面具体依赖；字体、视频与实际加载仍须运行验证。").font(.caption).foregroundStyle(.secondary)
                        ForEach(ComponentInventory.groups(report)) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.title).font(.headline)
                                    Spacer()
                                    Text(group.id == "records" ? "\(group.findings.count) 条记录" : group.summary).font(
                                        .caption
                                    ).foregroundStyle(.secondary)
                                }
                                if group.id != "records", !group.unresolved.isEmpty {
                                    Text(Array(Set(group.unresolved.map(\.component))).sorted().joined(separator: "、"))
                                        .font(.callout).textSelection(.enabled)
                                }
                                if group.id == "vc14", !group.unresolved.isEmpty {
                                    Text("可尝试补装微软 VC++ v14；只安装到独立副本，原容器保留。已有组件但存在冲突时，请先检查详细证据。").font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        ForEach(VCInstallPlan.eligibleArchitectures(report), id: \.self) { arch in
                                            Button("补装 VC++ · " + arch + "…") { prepareInstall(arch) }.disabled(
                                                installBusy || aiBusy || store.scanningID != nil || store.isDemo)
                                        }
                                    }
                                }
                                if group.id == "directx", !group.unresolved.isEmpty {
                                    Text("旧 DirectX 当前提供官方方案核对，不自动安装。不要下载散装 DLL。").font(.caption).foregroundStyle(
                                        .secondary)
                                }
                                DisclosureGroup(group.id == "records" ? "展开安装记录（不代表组件可用）" : "查看具体依赖与证据") {
                                    ForEach(group.findings) { f in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(f.component == "安装记录" ? f.evidence : f.component).font(
                                                .callout.weight(.medium))
                                            if f.component != "安装记录" {
                                                Text(
                                                    (f.architecture.map { $0 + " · " } ?? "") + f.state.rawValue + " · "
                                                        + f.evidence
                                                ).font(.caption)
                                            }
                                            Text(f.action).font(.caption).foregroundStyle(.secondary)
                                        }.textSelection(.enabled).padding(.vertical, 5)
                                    }
                                }
                            }.panelSection()
                        }
                        if !installStatus.isEmpty {
                            Text(installStatus).font(.callout).textSelection(.enabled)
                            if installBusy { ProgressView() }
                            if let installedGame, let installedReport {
                                Text(
                                    "副本复扫：找到 \(installedReport.findings.filter { $0.state == .detected }.count) 项静态候选。游戏运行尚未验证。"
                                ).font(.caption)
                                Button("使用此副本启动本作品") {
                                    guard let current = game, let plan = installPlan, current.bottleID == plan.source.id
                                    else {
                                        errorText = "配置已变化，请在游戏详情中选择副本。"
                                        return
                                    }
                                    var updated = current
                                    updated.bottleID = installedGame.bottleID
                                    updated.executable = installedGame.executable
                                    updated.workingDirectory = installedGame.workingDirectory
                                    store.refresh()
                                    store.update(updated)
                                    store.reports[gameID] = installedReport
                                    self.installedGame = nil
                                    installStatus += "\n已切换本作品的容器。原容器保留，可在配置中改回；未启动游戏。"
                                }.disabled(!store.writable)
                            }
                        }
                        if let advice {
                            Divider()
                            Text("AI 补充建议 · 未执行").font(.headline)
                            ForEach(advice.advice) { item in
                                DisclosureGroup(item.conclusion) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text("置信：\(item.confidence) · \(item.scope)")
                                        Text(item.action)
                                        Text("验证：" + item.verification)
                                        Text("证据：" + item.evidenceIDs.joined(separator: ", ")).font(.caption)
                                        ForEach(item.sources, id: \.self) { source in
                                            if let url = PublicLink.url(source) {
                                                Link("未核验来源 · " + (url.host ?? source), destination: url)
                                            }
                                        }
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                        ForEach(
                            RepairPlanner.proposals(
                                report: report, bottle: store.bottles.first { $0.id == game?.bottleID })
                        ) { plan in
                            DisclosureGroup("候选方案 · " + plan.action.rawValue) {
                                Text("目标：\(plan.targetBottle) · \(plan.architecture)")
                                Text(plan.prerequisite)
                                Text(plan.recoveryBoundary)
                                Text(plan.validation)
                                Link("官方组件资料", destination: plan.officialSource)
                                Text("依据：" + plan.evidenceIDs.joined(separator: ", ")).font(.caption)
                            }
                        }
                        Text("补装后会重新扫描。安装器成功不等于游戏故障解决；原容器和安装日志均保留。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "本地证据优先", systemImage: "doc.text.magnifyingglass", description: Text("检查无需 AI，也不会安装运行库。")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if aiBusy {
                HStack {
                    ProgressView("等待 AI 响应…")
                    Button("取消请求") { aiTask?.cancel() }
                }
            }
            if !errorText.isEmpty { Text(errorText).foregroundStyle(.orange).font(.caption) }
        }.padding(28).frame(width: 780, height: 620, alignment: .topLeading).editorSurface(coverPath: game?.coverPath)
            .sheet(isPresented: $showPayload) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("确认本次外发内容").font(.title2)
                    Text(
                        "只发送下面的 JSON。没有游戏名、个人路径、原始日志、存档或二进制文件。\(usesCodex ? "使用 ChatGPT 的 Codex 订阅额度；不会转用 API。" : "请求按所配置 API 服务计费。") "
                    )
                    Text(
                        "目标："
                            + (usesCodex
                                ? "本机 Codex · ChatGPT 订阅"
                                : (UserDefaults.standard.string(forKey: "aiEndpoint") ?? "未配置"))
                    ).font(.caption)
                    ScrollView {
                        Text(payload).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(
                            maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button("取消") { showPayload = false }
                        Spacer()
                        Button("同意本次发送并请求建议") {
                            showPayload = false
                            requestAI()
                        }.disabled(
                            usesCodex
                                ? CodexAdvisor.discover() == nil
                                : (UserDefaults.standard.string(forKey: "aiEndpoint") ?? "").isEmpty)
                    }
                }.padding(24).frame(width: 630, height: 540)
            }.sheet(isPresented: $installConfirmation) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("确认补装 VC++ v14").font(.title2)
                    if let plan = installPlan {
                        Text("作品：" + (game?.displayTitle ?? ""))
                        Text("源容器：\(plan.source.name)\n新副本：\(plan.destination.name)\n组件架构：\(plan.architecture)")
                            .textSelection(.enabled)
                        Text("下载微软官方安装包 → 建立 APFS 容器副本 → 只在副本中安装 → 重新扫描。会占用磁盘；不自动启动游戏，也不自动切换容器。")
                        Link(
                            "微软组件说明及许可条款",
                            destination: URL(
                                string: "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist")!)
                        Text("原容器保留，但副本仍可能映射到外部游戏、存档或 Mac 目录；这些外部内容不属于容器备份。安装可能弹出窗口，取消或失败会保留副本与日志。").font(.callout)
                            .foregroundStyle(.secondary)
                        Toggle("已退出源容器的游戏与 Steam，了解恢复边界并同意安装许可", isOn: $acceptedBoundary)
                        HStack {
                            Button("取消") { installConfirmation = false }
                            Spacer()
                            Button("建立副本并安装") {
                                installConfirmation = false
                                beginInstall()
                            }.buttonStyle(.borderedProminent).disabled(!acceptedBoundary)
                        }
                    }
                }.padding(24).frame(width: 600)
            }.interactiveDismissDisabled(installBusy).onDisappear { aiTask?.cancel() }
    }
    private func metric(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)").font(.title2.monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func prepareInstall(_ architecture: String) {
        guard let report, let bottle = store.bottles.first(where: { $0.id == game?.bottleID }) else {
            errorText = "请先绑定容器并扫描"
            return
        }
        do {
            installPlan = try VCInstallPlan(report: report, bottle: bottle, architecture: architecture)
            acceptedBoundary = false
            installConfirmation = true
        } catch { errorText = error.localizedDescription }
    }
    private func beginInstall() {
        guard let plan = installPlan, let game, let report, let runner = store.runner else { return }
        installBusy = true
        installedGame = nil
        installedReport = nil
        errorText = ""
        let directory = store.root.appendingPathComponent("Repairs/" + plan.destination.name)
        Task {
            defer { installBusy = false }
            do {
                _ = try await ComponentInstaller.install(
                    plan: plan, game: game, report: report, runner: runner, directory: directory
                ) { status in await MainActor.run { installStatus = status } }
                let copy = plan.remap(game)
                let checked = try await Task.detached {
                    try Analyzer.scan(game: copy, bottle: plan.destination, runner: runner)
                }.value
                installedGame = copy
                installedReport = checked
                installStatus = "安装器已退出，副本已复扫。日志：" + directory.path
            } catch { installStatus = "未完成：" + error.localizedDescription + "\n日志 / 恢复线索：" + directory.path }
        }
    }
    private var usesCodex: Bool { (UserDefaults.standard.string(forKey: "aiProvider") ?? "codex") == "codex" }
    private var payload: String {
        guard let report, let data = try? AdviceInput(report: report).json() else { return "无摘要" }
        return String(decoding: data, as: UTF8.self)
    }
    private func requestAI() {
        guard let report else { return }
        let input = AdviceInput(report: report)
        aiBusy = true
        errorText = ""
        aiTask = Task {
            defer { aiBusy = false }
            do {
                let endpoint = UserDefaults.standard.string(forKey: "aiEndpoint") ?? ""
                let model = UserDefaults.standard.string(forKey: "aiModel") ?? ""
                guard let selected = game else { throw VNError.message("游戏已移除") }
                let bottle = store.bottles.first { $0.id == selected.bottleID }
                let runner = store.runner
                let worker = Task.detached(priority: .utility) {
                    try Analyzer.scan(game: selected, bottle: bottle, runner: runner)
                }
                let current = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard current.fingerprint == report.fingerprint, current.bottleFingerprint == report.bottleFingerprint,
                    current.runnerVersion == report.runnerVersion
                else {
                    store.reports[gameID] = current
                    throw VNError.message("游戏或容器证据已变化，尚未发送。请重新查看外发摘要。")
                }
                if usesCodex {
                    guard let path = CodexAdvisor.discover() else {
                        throw VNError.message("未找到 Codex CLI，请先安装并使用 ChatGPT 登录。")
                    }
                    advice = try await CodexAdvisor(
                        executable: path, model: UserDefaults.standard.string(forKey: "codexModel") ?? ""
                    ).explain(input)
                } else {
                    guard let url = URL(string: endpoint) else { throw VNError.message("请先在设置配置 API 服务") }
                    let key = try CredentialStore.get(account: endpoint)
                    advice = try await HTTPAdvisor(endpoint: url, model: model, key: key).explain(input)
                }
            } catch is CancellationError { errorText = "请求已取消，本地结果保留。" } catch {
                errorText = "AI 未完成：\(error.localizedDescription)；本地扫描和启动不受影响。"
            }
        }
    }
}
