import SwiftUI
import VNCore

struct MetadataEditor: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "资料"
    @State private var values: [MetadataField: String] = [:]
    @State private var original: [MetadataField: String] = [:]
    @State private var query = ""
    @State private var candidate: MetadataResult?
    @State private var selectedFields = Set(MetadataField.allCases)
    @State private var includeArtwork = false
    @State private var identityConfirmed = false
    @State private var loading = false
    @State private var request: Task<Void, Never>?
    @State private var error: String?
    @State private var notice: String?
    @State private var revisions: [MetadataRevision] = []
    @State private var restoreTarget: MetadataRevision?
    private var game: Game? { store.games.first { $0.id == gameID } }
    private var changes: [MetadataField: String] {
        Dictionary(
            uniqueKeysWithValues: MetadataField.allCases.compactMap { field in
                let value = values[field] ?? ""
                return value != (original[field] ?? "") ? (field, value) : nil
            })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelHeading(
                    title: "作品资料", subtitle: game?.displayTitle ?? "作品已移除", symbol: "text.book.closed",
                    coverPath: game?.coverPath)
                Spacer()
                Button(changes.isEmpty ? "完成" : "放弃未保存修改") { dismiss() }.keyboardShortcut(.cancelAction)
                if tab == "资料" {
                    Button("保存修改") { saveManual() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(changes.isEmpty || !store.writable)
                }
            }
            PanelTabs(items: ["资料", "匹配作品", "修改历史"], selection: $tab)
            if tab == "资料" { fieldsView } else if tab == "匹配作品" { matchingView } else { historyView }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }.padding(28).frame(width: 800, height: 610).editorSurface(coverPath: game?.coverPath)
            .onAppear {
                resetForm()
                query = game?.metadataSteamID ?? ""
                loadHistory()
            }
            .onDisappear { request?.cancel() }
            .onChange(of: query) { _, _ in
                request?.cancel()
                candidate = nil
                identityConfirmed = false
            }
            .confirmationDialog(
                "恢复这次修改前的资料？",
                isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }),
                titleVisibility: .visible
            ) {
                if let target = restoreTarget { Button("恢复“\(target.title)”的资料") { restore(target) } }
                Button("取消", role: .cancel) { restoreTarget = nil }
            } message: {
                Text("恢复标题、简介、来源和选图；启动配置、收藏、存档位置保持当前值。恢复操作也会留在历史中。")
            }
    }
    private var fieldsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("手动修正优先于已匹配的公开资料；公开资料优先于本地自动补全。每项单独保留来源。").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                    alignment: .leading, spacing: 18
                ) {
                    ForEach(MetadataField.allCases.filter { $0 != .summary }) { field in fieldEditor(field) }
                }
                fieldEditor(.summary)
            }.padding(.trailing, 8)
        }
    }
    private func fieldEditor(_ field: MetadataField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.label).font(.system(size: 13, weight: .semibold))
                if game?.metadataOrigin(field).manual == true {
                    Label("手动保留", systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if field == .summary {
                TextEditor(text: binding(field)).font(.system(size: 13)).frame(height: 100).padding(5).background(
                    .white, in: RoundedRectangle(cornerRadius: 6)
                ).overlay { RoundedRectangle(cornerRadius: 6).stroke(.quaternary) }.accessibilityLabel("编辑简介")
            } else {
                TextField(field == .genres ? "使用顿号或逗号分隔" : field.label, text: binding(field)).textFieldStyle(
                    .roundedBorder
                ).accessibilityLabel("编辑" + field.label)
            }
            if let origin = game?.metadataOrigin(field) { originView(origin) }
        }
    }
    private var matchingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("作品身份只用于补全资料。更换关联不会改变启动程序、Steam 启动 ID 或 CrossOver 容器。").font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("Steam App ID 或商店链接", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel(
                        "资料作品 ID")
                    Button(loading ? "读取中…" : "预览作品") { fetchCandidate() }.disabled(
                        loading || query.isEmpty || !changes.isEmpty)
                }
                if !changes.isEmpty { Text("请先保存或放弃资料页的修改，再匹配作品。").font(.caption).foregroundStyle(.orange) }
                if let game {
                    HStack(spacing: 20) {
                        Text("资料关联：" + (game.metadataSteamID.map { "Steam " + $0 } ?? "尚未关联"))
                        Text("启动：" + (game.kind == .steam ? "Steam " + game.steamAppID : "本地 EXE"))
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if let candidate, let identity = candidate.metadata.identity {
                    Divider()
                    HStack(alignment: .top, spacing: 18) {
                        CoverImage(path: candidate.coverPath, title: identity.name).frame(width: 85, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(identity.name).font(.headline).textSelection(.enabled)
                            Text("Steam \(identity.steamAppID) · \(candidate.metadata.productType ?? "类型未提供")").font(
                                .caption.monospacedDigit())
                            Text(
                                [candidate.metadata.developer, candidate.metadata.releaseDate].compactMap { $0 }.joined(
                                    separator: " · ")
                            ).font(.caption).foregroundStyle(.secondary)
                            if let url = URL(string: candidate.metadata.detailSource ?? ""), url.scheme == "https" {
                                Link("核对商店页面与版本 ↗", destination: url).font(.caption)
                            }
                        }
                        Spacer()
                    }
                    Text("选择本次采用的字段").font(.headline)
                    ForEach(MetadataField.allCases) { field in
                        if let value = MetadataEditing.value(field, in: candidate) {
                            Toggle(
                                isOn: Binding(
                                    get: { selectedFields.contains(field) },
                                    set: {
                                        if $0 { selectedFields.insert(field) } else { selectedFields.remove(field) }
                                    })
                            ) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(field.label + (game?.metadataOrigin(field).manual == true ? " · 当前为手动修正" : ""))
                                        .font(.callout)
                                    Text(value.isEmpty ? "（空）" : value).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(field == .summary ? 3 : 2)
                                }
                            }.toggleStyle(.checkbox)
                        }
                    }
                    Toggle("采用该作品的推荐图片，保留手动选图", isOn: $includeArtwork).toggleStyle(.checkbox)
                    Text("换到另一部作品时，旧的自动资料会清除；手动修正继续保留。勾选手动字段会用本次候选替换它，并恢复该字段自动更新。").font(.caption).foregroundStyle(
                        .secondary
                    ).fixedSize(horizontal: false, vertical: true)
                    Toggle("已核对作品名、版本与发行信息", isOn: $identityConfirmed).toggleStyle(.checkbox)
                    Button("应用所选资料") { applyCandidate(candidate) }.buttonStyle(.borderedProminent).disabled(
                        !identityConfirmed || selectedFields.isEmpty || !store.writable)
                } else if !loading {
                    Text("支持准确的 Steam 条目关联，包括为独立 EXE 补充公开资料。不会凭同名自动绑定重制版、资料集或其他版本。").font(.caption).foregroundStyle(
                        .secondary)
                }
            }.padding(.trailing, 8)
        }
    }
    private var historyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("最近 12 次资料变更前的快照，保存在本机。你可以恢复后再次编辑。").font(.caption).foregroundStyle(.secondary)
                if revisions.isEmpty {
                    ContentUnavailableView(
                        "还没有修改历史", systemImage: "clock.arrow.circlepath", description: Text("修正、重新匹配或资料刷新后会保留之前的内容。"))
                }
                ForEach(revisions) { revision in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(revision.reason + "前").font(.headline)
                            Spacer()
                            Button("恢复此版本…") { restoreTarget = revision }.disabled(!changes.isEmpty || !store.writable)
                        }
                        Text(revision.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            .foregroundStyle(.secondary)
                        Text(revision.metadata?.localizedTitle ?? revision.title).font(.callout)
                        if let summary = revision.metadata?.summary {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
                        .quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    private func originView(_ origin: MetadataOrigin) -> some View {
        HStack(spacing: 8) {
            if let url = URL(string: origin.source), url.scheme == "https" {
                Link(url.host ?? "资料来源", destination: url)
            } else {
                Text(origin.source)
            }
            if let date = origin.date { Text(date.formatted(date: .abbreviated, time: .omitted)) }
        }.font(.caption2).foregroundStyle(.secondary)
    }
    private func binding(_ field: MetadataField) -> Binding<String> {
        Binding(
            get: { values[field] ?? "" },
            set: {
                values[field] = $0
                notice = nil
            })
    }
    private func resetForm() {
        guard let game else { return }
        values = Dictionary(uniqueKeysWithValues: MetadataField.allCases.map { ($0, game.metadataValue($0)) })
        original = values
    }
    private func loadHistory() {
        do { revisions = try MetadataHistory.load(at: store.historyURL(gameID)) } catch {
            self.error = "修改历史未载入：\(error.localizedDescription)"
        }
    }
    private func saveManual() {
        guard let game else { return }
        do {
            let edited = try MetadataEditing.manual(changes, in: game)
            store.cancelMetadata(gameID)
            try store.commitMetadata(edited, reason: "手动修正")
            resetForm()
            loadHistory()
            error = nil
            notice = "已保存修改，刷新公开资料会保留这些字段。"
        } catch { self.error = error.localizedDescription }
    }
    private func fetchCandidate() {
        do {
            let id = try MetadataEditing.steamID(from: query)
            loading = true
            error = nil
            notice = nil
            candidate = nil
            identityConfirmed = false
            request?.cancel()
            request = Task {
                defer { loading = false }
                do {
                    let result = try await MetadataService.steam(
                        appID: id, cacheDirectory: store.root.appendingPathComponent("Artwork"))
                    try Task.checkCancellation()
                    candidate = result
                    selectedFields = Set(MetadataField.allCases.filter { game?.metadataOrigin($0).manual != true })
                } catch is CancellationError {} catch { self.error = "读取未完成：\(error.localizedDescription)；现有资料未改变。" }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func applyCandidate(_ candidate: MetadataResult) {
        guard let game, identityConfirmed else { return }
        do {
            let edited = try MetadataEditing.rematch(
                candidate, fields: selectedFields, includeArtwork: includeArtwork, into: game)
            store.cancelMetadata(gameID)
            try store.commitMetadata(edited, reason: "重新匹配资料")
            resetForm()
            loadHistory()
            tab = "资料"
            self.candidate = nil
            error = nil
            notice = "资料关联已更新，启动配置保持原样。"
        } catch { self.error = error.localizedDescription }
    }
    private func restore(_ revision: MetadataRevision) {
        guard let game else { return }
        do {
            store.cancelMetadata(gameID)
            try store.commitMetadata(revision.restoring(into: game), reason: "恢复历史资料")
            restoreTarget = nil
            resetForm()
            loadHistory()
            error = nil
            notice = "已恢复选定资料。"
        } catch { self.error = error.localizedDescription }
    }
}
