import SwiftUI
import VNCore

struct GuidePlanCard: View {
    @Bindable var store: LibraryStore
    let game: Game
    @State private var editing = false
    @State private var mapVisible = false
    @State private var error: String?
    private var plan: GuidePlan? { game.progress?.guidePlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("路线攻略").font(.headline)
                Spacer()
                Button(plan == nil ? "新建攻略" : "编辑攻略") { editing = true }.buttonStyle(.plain)
            }
            if let plan {
                Text(plan.title).font(.callout).fontWeight(.medium)
                Text("\(plan.completedNodeIDs.count) / \(plan.nodes.count) 个节点已手动标记完成")
                    .font(.caption).foregroundStyle(.secondary)
                if plan.nodes.isEmpty {
                    Text("添加第一个节点后，可以手动设置当前位置。").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button(mapVisible ? "收起路线图" : "查看路线图 · 含剧透") { mapVisible.toggle() }.buttonStyle(.plain)
                    if mapVisible { routeMap(plan) }
                }
                DisclosureGroup("来源与版本") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.version + " · " + plan.language)
                        if !plan.target.isEmpty { Text("目标：" + plan.target) }
                        Text("手动核对于 " + plan.checkedAt.formatted(date: .abbreviated, time: .omitted))
                        if let url = PublicLink.url(plan.sourceURL) { Link("查看原文 ↗", destination: url) }
                    }.font(.caption)
                }.font(.caption)
            } else {
                Text("把有来源的攻略整理成节点，选择当前位置后逐步查看。").font(.callout).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .sheet(isPresented: $editing) { GuidePlanEditor(store: store, gameID: game.id) }
        .onChange(of: game.id) { _, _ in
            mapVisible = false
            error = nil
        }
        .onChange(of: game.progress?.observation?.fingerprint) { _, _ in mapVisible = false }
    }

    private func routeMap(_ plan: GuidePlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("这里的完成标记由你核对，不会改变游戏存档。").font(.caption).foregroundStyle(.secondary)
            ForEach(plan.nodes) { node in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Image(
                            systemName: plan.completedNodeIDs.contains(node.id)
                                ? "checkmark.circle.fill"
                                : plan.selectedNodeID == node.id ? "location.circle" : "circle"
                        )
                        .foregroundStyle(plan.selectedNodeID == node.id ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(node.title).fontWeight(.medium)
                            Text([node.route, node.chapter].filter { !$0.isEmpty }.joined(separator: " · ")).font(
                                .caption
                            ).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(plan.selectedNodeID == node.id ? "当前位置" : "设为当前") { select(node.id) }
                            .disabled(!plan.unmetPrerequisites(for: node).isEmpty)
                            .accessibilityLabel("设为当前节点 " + node.title)
                    }
                    if !node.prerequisites.isEmpty {
                        Text("前置：" + names(node.prerequisites, in: plan)).font(.caption).foregroundStyle(.secondary)
                    }
                    if !node.next.isEmpty {
                        Text("→ " + names(node.next, in: plan)).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(plan.completedNodeIDs.contains(node.id) ? "取消完成标记" : "标记已完成") { toggleCompletion(node.id) }
                        .font(.caption).accessibilityLabel(
                            (plan.completedNodeIDs.contains(node.id) ? "取消完成 " : "完成节点 ") + node.title)
                }.buttonStyle(.plain).padding(.vertical, 8)
                if node.id != plan.nodes.last?.id { Divider().opacity(0.4) }
            }
        }.font(.callout)
    }

    private func names(_ ids: [UUID], in plan: GuidePlan) -> String {
        ids.compactMap { id in plan.nodes.first { $0.id == id }?.title }.joined(separator: "、")
    }

    private func select(_ id: UUID) {
        change { progress in
            guard var plan = progress.guidePlan else { return }
            try plan.select(id)
            guard let node = plan.selectedNode else { return }
            progress.guidePlan = plan
            progress.manual = ProgressPosition(chapter: node.chapter, route: node.route)
            progress.manualBasis = progress.observation?.fingerprint
            progress.gameVersion = plan.version
            progress.target = plan.target
        }
    }

    private func toggleCompletion(_ id: UUID) {
        change { progress in
            guard var plan = progress.guidePlan else { return }
            if plan.completedNodeIDs.contains(id) {
                plan.completedNodeIDs.removeAll { $0 == id }
            } else {
                plan.completedNodeIDs.append(id)
            }
            progress.guidePlan = plan
        }
    }

    private func change(_ update: (inout PlayProgress) throws -> Void) {
        do {
            guard let current = store.games.first(where: { $0.id == game.id }) else { return }
            var progress = current.progress ?? PlayProgress()
            try update(&progress)
            try store.saveProgress(progress, gameID: game.id)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct GuidePlanEditor: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GuidePlan()
    @State private var original: GuidePlan?
    @State private var nodeEditor: GuideNode?
    @State private var error: String?
    @State private var removing = false
    private var game: Game? { store.games.first { $0.id == gameID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("编辑路线攻略").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存攻略", action: save).buttonStyle(.borderedProminent)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("攻略名称", text: $draft.title)
                    field("原文 HTTPS 链接", text: $draft.sourceURL)
                    HStack {
                        field("适用版本", text: $draft.version)
                        field("语言", text: $draft.language)
                    }
                    field("目标路线或结局（可留空）", text: $draft.target)
                    Divider()
                    HStack {
                        Text("节点").font(.headline)
                        Spacer()
                        Button("添加节点") { nodeEditor = GuideNode() }.disabled(draft.nodes.count >= 200)
                    }
                    ForEach(draft.nodes) { node in
                        HStack {
                            Text(node.title).lineLimit(1)
                            Spacer()
                            Button("上移") { move(node.id, delta: -1) }.disabled(node.id == draft.nodes.first?.id)
                            Button("下移") { move(node.id, delta: 1) }.disabled(node.id == draft.nodes.last?.id)
                            Button("编辑") { nodeEditor = node }.accessibilityLabel("编辑节点 " + node.title)
                            Button("移除") { draft.removeNode(node.id) }.accessibilityLabel("移除节点 " + node.title)
                        }.font(.callout).buttonStyle(.plain).padding(.vertical, 5)
                    }
                }.padding(2)
            }
            HStack {
                if game?.progress?.guidePlan != nil { Button("删除整份攻略…", role: .destructive) { removing = true } }
                Spacer()
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.padding(28).frame(width: 700, height: 610).editorSurface(coverPath: game?.coverPath)
            .onAppear {
                original = game?.progress?.guidePlan
                if let plan = original {
                    draft = plan
                } else {
                    draft.version = game?.progress?.gameVersion ?? ""
                    draft.target = game?.progress?.target ?? ""
                }
            }
            .sheet(item: $nodeEditor) { node in
                GuideNodeEditor(node: node, siblings: draft.nodes) { edited in
                    if let index = draft.nodes.firstIndex(where: { $0.id == edited.id }) {
                        draft.nodes[index] = edited
                    } else {
                        draft.nodes.append(edited)
                    }
                }
            }
            .confirmationDialog("删除这份路线攻略？", isPresented: $removing, titleVisibility: .visible) {
                Button("删除攻略", role: .destructive) {
                    do {
                        guard let game else { return }
                        guard game.progress?.guidePlan == original else {
                            throw VNError.message("攻略已在其他位置修改，请关闭后重新打开。")
                        }
                        try Storage.save(
                            LibraryDocument(games: store.games, collections: store.collections),
                            to: store.root.appendingPathComponent("LibraryBackups/guide-\(UUID().uuidString).json"))
                        var progress = game.progress ?? PlayProgress()
                        progress.guidePlan = nil
                        try store.saveProgress(progress, gameID: gameID)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            } message: {
                Text("删除前保留本地副本，不影响书签或游戏存档。")
            }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }

    private func move(_ id: UUID, delta: Int) {
        guard let index = draft.nodes.firstIndex(where: { $0.id == id }), draft.nodes.indices.contains(index + delta)
        else { return }
        draft.nodes.swapAt(index, index + delta)
    }

    private func save() {
        do {
            guard let game else { return }
            guard game.progress?.guidePlan == original else { throw VNError.message("攻略已在其他位置修改，请关闭后重新打开。") }
            draft.checkedAt = Date()
            try draft.validate()
            var progress = game.progress ?? PlayProgress()
            progress.guidePlan = draft
            try store.saveProgress(progress, gameID: gameID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct GuideNodeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var node: GuideNode
    let siblings: [GuideNode]
    let save: (GuideNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("攻略节点").font(.title2)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("完成编辑") {
                    save(node)
                    dismiss()
                }.buttonStyle(.borderedProminent)
                    .disabled(node.title.isEmpty || node.hint.isEmpty || (node.chapter.isEmpty && node.route.isEmpty))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("节点名称", text: $node.title).accessibilityLabel("节点名称")
                    HStack {
                        TextField("章节", text: $node.chapter).accessibilityLabel("节点章节")
                        TextField("路线", text: $node.route).accessibilityLabel("节点路线")
                    }
                    Text("当前提示 · 最多 1600 字").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $node.hint).frame(height: 140).accessibilityLabel("节点提示")
                    TextField("留档提醒（可留空）", text: $node.saveReminder).accessibilityLabel("留档提醒")
                    if siblings.contains(where: { $0.id != node.id }) {
                        DisclosureGroup("前置条件与后续分支") {
                            ForEach(siblings.filter { $0.id != node.id }) { sibling in
                                HStack {
                                    Text(sibling.title).lineLimit(1)
                                    Spacer()
                                    Toggle("前置", isOn: membership(sibling.id, in: $node.prerequisites))
                                    Toggle("后续", isOn: membership(sibling.id, in: $node.next))
                                }.font(.callout)
                            }
                        }
                    }
                }.textFieldStyle(.roundedBorder).padding(2)
            }
        }.padding(26).frame(width: 630, height: 530)
    }

    private func membership(_ id: UUID, in values: Binding<[UUID]>) -> Binding<Bool> {
        Binding(
            get: { values.wrappedValue.contains(id) },
            set: { enabled in
                values.wrappedValue.removeAll { $0 == id }
                if enabled { values.wrappedValue.append(id) }
            })
    }
}
