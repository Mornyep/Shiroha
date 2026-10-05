import SwiftUI
import VNCore

struct ProgressCard: View {
    enum Section { case progress, guide }
    @Bindable var store: LibraryStore
    let game: Game
    var section = Section.progress
    @State private var editor = false
    @State private var guideEditor = false
    @State private var revealed = false
    @State private var slotsVisible = false
    @State private var observationVisible = false
    private var progress: PlayProgress { game.progress ?? PlayProgress() }
    private var link: ProgressLink? { store.progressLinks[game.id] }
    private var observationPending: Bool {
        guard link?.paused == false else { return false }
        return !(store.progressMessages[game.id]?.hasPrefix("已检查") ?? false)
    }

    var body: some View {
        Group {
            switch section {
            case .progress: progressContent
            case .guide: guideContent
            }
        }
        .sheet(isPresented: $editor) { ProgressEditor(store: store, gameID: game.id, guideMode: false) }
        .sheet(isPresented: $guideEditor) { ProgressEditor(store: store, gameID: game.id, guideMode: true) }
        .onChange(of: observationPending) { _, pending in if pending { revealed = false } }
        .onChange(of: game.progress) { _, _ in
            revealed = false
            slotsVisible = false
        }
        .onChange(of: game.id) { _, _ in
            revealed = false
            slotsVisible = false
            observationVisible = false
        }
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("游玩进度").font(.headline)
                Spacer()
                Button("记录位置") { editor = true }.buttonStyle(.plain)
            }
            if let position = progress.manual, !position.label.isEmpty {
                Text(position.label).font(.system(size: 19, weight: .medium))
                Text("手动核对 · " + position.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("尚未记录位置").font(.callout).foregroundStyle(.secondary)
            }
            if !progress.target.isEmpty { Text("目标 · " + progress.target).font(.callout) }
            if progress.hasNewEvidence {
                Label("存档有变化，请重新核对位置。", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout).foregroundStyle(.orange)
            }
            DisclosureGroup("存档观察", isExpanded: $observationVisible) {
                observationContent.padding(.top, 8)
            }.font(.callout)
            if link?.paused == true {
                Text("观察已暂停").font(.caption).foregroundStyle(.secondary)
            } else if link != nil, let message = store.progressMessages[game.id], !message.hasPrefix("已检查") {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var observationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let observation = progress.observation {
                Text(link == nil ? "历史记录 · 未关联目录" : "最近一次观察").font(.caption).foregroundStyle(.secondary)
                if let newest = observation.newest {
                    Text(newest.script.map { "脚本 \($0) · 章节待核对" } ?? "发现存档，章节未识别").font(.callout)
                    Text(newest.filename + " · " + newest.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Button(slotsVisible ? "收起文件记录" : "查看 \(observation.slots.count) 个文件") { slotsVisible.toggle() }
                    .buttonStyle(.plain)
                if slotsVisible {
                    ForEach(observation.slots) { slot in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(slot.filename)
                            Text(
                                (slot.script ?? "未识别格式") + " · "
                                    + slot.modifiedAt.formatted(date: .abbreviated, time: .shortened)
                            )
                            .foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                }
            }
            HStack(spacing: 14) {
                Button(link == nil ? "选择存档目录" : "更换目录") { store.chooseProgressDirectory(game) }
                if let link {
                    Button(link.paused ? "恢复" : "暂停") {
                        act {
                            var value = link
                            value.paused.toggle()
                            try store.setProgressLink(value, id: game.id)
                        }
                    }
                    Button("刷新") { store.refreshProgress(game.id) }.disabled(link.paused)
                    Button("解除") { act { try store.setProgressLink(nil, id: game.id) } }
                }
            }.buttonStyle(.plain).font(.caption).disabled(!store.writable)
            if let error = store.progressLinkError { Text(error).font(.caption).foregroundStyle(.secondary) }
            Text("只读观察。最近写入的档位不一定是当前阅读位置，读旧档但未保存时无法得知。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var guideContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("当前位置提示").font(.headline)
                Spacer()
                if progress.guidePlan?.selectedNode == nil {
                    Button(progress.guide == nil ? "添加单条提示" : "编辑单条提示") { guideEditor = true }.buttonStyle(.plain).font(
                        .caption)
                }
            }
            if observationPending {
                Text("正在观察存档，提示暂时收起。").font(.callout).foregroundStyle(.secondary)
            } else if let block = progress.guideBlock {
                Text(block).font(.callout).foregroundStyle(.secondary)
            } else {
                Button(revealed ? "收起提示" : "查看下一步") { revealed.toggle() }.buttonStyle(QuietButton())
                if revealed, let guide = progress.activeGuide {
                    Text(guide.hint).font(.callout).lineSpacing(6).textSelection(.enabled)
                }
            }
            if let guide = progress.activeGuide {
                DisclosureGroup("提示来源") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(guide.title)
                        Text(guide.version + " · " + guide.language)
                        if let url = PublicLink.url(guide.url) { Link("原文 · 可能含剧透 ↗", destination: url) }
                    }.font(.caption)
                }.font(.caption)
            }
        }
    }

    private func act(_ operation: () throws -> Void) {
        do { try operation() } catch { store.progressMessages[game.id] = error.localizedDescription }
    }
}

struct ProgressEditor: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    let guideMode: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PlayProgress()
    @State private var position = ProgressPosition()
    @State private var guide = GuideNote()
    @State private var error: String?
    @State private var startingObservation: SaveObservation?
    private var game: Game? { store.games.first { $0.id == gameID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PanelHeading(
                    title: guideMode ? "关联这一处的攻略" : "核对游玩进度", subtitle: game?.displayTitle ?? "作品已移除",
                    symbol: guideMode ? "signpost.right" : "book.pages", coverPath: game?.coverPath)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.buttonStyle(.borderedProminent).disabled(!store.writable)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if guideMode {
                        field("攻略标题", text: $guide.title)
                        field("原文 HTTPS 链接", text: $guide.url)
                        HStack {
                            field("适用版本", text: $guide.version)
                            field("语言", text: $guide.language)
                        }
                        HStack {
                            field("对应章节", text: $guide.chapter)
                            field("对应路线（可留空）", text: $guide.route)
                        }
                        field("对应目标", text: $guide.target)
                        Text("下一步提示／留档建议").font(.headline)
                        TextEditor(text: $guide.hint).font(.callout).padding(8).frame(height: 110).background(
                            .white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8)
                        ).accessibilityLabel("下一步攻略提示")
                        Text("保存你已核对原文的一条提示。只有位置、目标和版本均相符时才提供展开；不会从链接自动生成答案。").font(.caption).foregroundStyle(
                            .secondary)
                    } else {
                        HStack {
                            field("当前章节", text: $position.chapter)
                            field("当前路线（可留空）", text: $position.route)
                        }
                        field("本次目标", text: $draft.target)
                        field("当前游戏版本", text: $draft.gameVersion)
                        if let slot = startingObservation?.newest {
                            Text("供核对的最近记录：" + slot.filename + "\n" + (slot.script ?? "格式未识别")).font(.callout)
                                .textSelection(.enabled)
                        }
                        Text("按游戏画面核对后保存。更换目标只影响攻略，不改变游戏路线。手动进度与书签独立保留。").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(2)
            }
            HStack {
                if guideMode && game?.progress?.guide != nil { Button("移除这条提示", role: .destructive) { removeGuide() } }
                Spacer()
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.padding(28).frame(width: 720, height: guideMode ? 600 : 490).editorSurface(coverPath: game?.coverPath)
            .onAppear {
                draft = game?.progress ?? PlayProgress()
                position = draft.manual ?? ProgressPosition()
                startingObservation = draft.observation
                if let existing = draft.guide {
                    guide = existing
                } else {
                    guide.chapter = position.chapter
                    guide.route = position.route
                    guide.target = draft.target
                    guide.version = draft.gameVersion
                }
            }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }
    private func save() {
        do {
            var current = game?.progress ?? PlayProgress()
            if guideMode {
                guide.checkedAt = Date()
                current.guide = guide
            } else {
                guard current.observation == startingObservation else { throw VNError.message("编辑期间发现了新存档，请取消后重新核对。") }
                position.updatedAt = Date()
                current.manual = position.label.isEmpty ? nil : position
                current.manualBasis = current.observation?.fingerprint
                current.target = draft.target
                current.gameVersion = draft.gameVersion
            }
            try store.saveProgress(current, gameID: gameID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func removeGuide() {
        do {
            var current = game?.progress ?? PlayProgress()
            current.guide = nil
            try store.saveProgress(current, gameID: gameID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
