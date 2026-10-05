import SwiftUI
import VNCore

struct PublicSourcesCard: View {
    @Bindable var store: LibraryStore
    let game: Game
    @State private var matching = false
    @State private var busy: String?
    @State private var status: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("资料与评分").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("关联来源") { matching = true }.buttonStyle(.plain).font(.caption)
            }
            Text("各站独立评分，可能合并不同发行版本；不计算综合分。关联后可离线查看。").font(.caption).foregroundStyle(.secondary)
            ForEach((game.metadata?.publicProfiles ?? []).prefix(2)) { profile in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(profile.source.rawValue).fontWeight(.medium)
                        Text(profile.scoreLabel).monospacedDigit()
                        Text("\(profile.votes) 人评分").foregroundStyle(.secondary)
                    }.font(.callout)
                    Text(profile.title + " · " + profile.released).font(.caption)
                    if let id = profile.matchedSteamID {
                        Text("发行条目关联 Steam " + id).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(profile.method + (profile.rank.map { " · 站内排名 \($0)" } ?? "")).font(.caption2).foregroundStyle(
                        .secondary)
                    DisclosureGroup("来源简介（可能含剧透）") {
                        Text(profile.summary.isEmpty ? "来源未提供简介。" : profile.summary).font(.callout).lineSpacing(5)
                            .textSelection(.enabled)
                    }.font(.caption)
                    HStack {
                        if let url = profile.url { Link("查看条目与评价 ↗", destination: url) }
                        Button("刷新") { refresh(profile) }.disabled(busy != nil).accessibilityLabel(
                            "刷新 " + profile.source.rawValue)
                        Spacer()
                        Button("解除关联") { remove(profile) }.disabled(busy != nil).accessibilityLabel(
                            "解除 " + profile.source.rawValue + " 关联")
                    }.buttonStyle(.plain).font(.caption)
                    Text("获取于 " + profile.fetchedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
                        .foregroundStyle(.tertiary)
                }.padding(.vertical, 8)
            }
            if (game.metadata?.publicProfiles ?? []).isEmpty {
                Text("尚未关联 Bangumi / VNDB。搜索作品名后核对条目，不会替换手动资料。").font(.callout).foregroundStyle(.secondary)
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }.sheet(isPresented: $matching) { PublicSourceMatcher(store: store, gameID: game.id).id(game.id) }
    }
    private func refresh(_ profile: PublicProfile) {
        let identity = game.metadataSteamID
        busy = profile.id
        status = "正在读取 " + profile.source.rawValue + "…"
        Task {
            defer { busy = nil }
            do {
                let fresh = try await PublicSourceClient.shared.refresh(profile)
                guard var current = store.games.first(where: { $0.id == game.id }), current.metadataSteamID == identity,
                    let index = current.metadata?.publicProfiles?.firstIndex(where: { $0.id == profile.id })
                else { return }
                current.metadata?.publicProfiles?[index] = fresh
                try store.commitMetadata(current, reason: "刷新 " + profile.source.rawValue)
                status = "已更新（同一请求 5 分钟内使用缓存）。"
            } catch { status = error.localizedDescription }
        }
    }
    private func remove(_ profile: PublicProfile) {
        guard var current = store.games.first(where: { $0.id == game.id }) else { return }
        current.metadata?.publicProfiles?.removeAll { $0.source == profile.source }
        do {
            try store.commitMetadata(current, reason: "解除 " + profile.source.rawValue)
            status = nil
        } catch { status = error.localizedDescription }
    }
}

struct PublicSourceMatcher: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var source = PublicSource.bangumi
    @State private var query = ""
    @State private var candidates: [PublicProfile] = []
    @State private var status = "只发送你填写的作品名，不发送游戏路径、存档或个人记录。"
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var identity: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("关联公开资料来源").font(.title2).fontWeight(.semibold)
            Text("核对原名、发行日期与原站条目。确认仅保存该来源，不替换标题、简介、封面或启动配置。").font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("来源", selection: $source) { ForEach(PublicSource.allCases) { Text($0.rawValue).tag($0) } }.frame(
                    width: 180
                ).disabled(busy)
                TextField("作品名", text: $query).onSubmit { search() }.disabled(busy)
                Button("搜索") { search() }.disabled(
                    busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if source == .vndb, identity != nil {
                Button("按 Steam 发行条目匹配") { search(steamMatch: true) }.disabled(busy)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(candidates) { profile in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.title).font(.headline)
                            Text(profile.originalTitle + " · " + profile.released).font(.caption)
                            Text(profile.scoreLabel + " · \(profile.votes) 人评分 · " + profile.sourceID).font(.caption)
                            if let id = profile.matchedSteamID {
                                Text("已匹配 Steam " + id + " 的发行关联").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                if let url = profile.url { Link("核对原站 ↗", destination: url) }
                                Spacer()
                                Button("确认关联此条目") { save(profile) }
                            }.font(.callout)
                        }.padding(16).background(.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 690, height: 560)
            .onAppear {
                if let game = store.games.first(where: { $0.id == gameID }) {
                    query = game.displayTitle
                    identity = game.metadataSteamID
                }
            }
            .onChange(of: source) { _, _ in
                candidates = []
                status = "搜索并核对该来源中的作品条目。"
            }
            .onDisappear { task?.cancel() }
    }
    private func search(steamMatch: Bool = false) {
        guard !busy else { return }
        busy = true
        candidates = []
        status = "正在查询 " + source.rawValue + "…"
        let selected = source
        let keyword = query
        task = Task {
            defer { busy = false }
            do {
                let found: [PublicProfile]
                if steamMatch, let identity {
                    found = try await PublicSourceClient.shared.matchSteam(appID: identity)
                } else {
                    found = try await PublicSourceClient.shared.search(selected, query: keyword)
                }
                try Task.checkCancellation()
                candidates = found
                status = found.isEmpty ? "没有找到公开游戏条目；可改用日文原名或英文名。" : "找到 \(found.count) 个候选；同名条目需核对。"
            } catch is CancellationError {} catch { status = error.localizedDescription }
        }
    }
    private func save(_ profile: PublicProfile) {
        guard var current = store.games.first(where: { $0.id == gameID }), current.metadataSteamID == identity else {
            status = "作品身份已改变，请关闭后重新关联。"
            return
        }
        var meta = current.metadata ?? GameMetadata()
        var profiles = (meta.publicProfiles ?? []).filter { $0.source != profile.source }
        profiles.append(profile)
        meta.publicProfiles = profiles
        current.metadata = meta
        do {
            try store.commitMetadata(current, reason: "确认 " + profile.source.rawValue + " 条目")
            dismiss()
        } catch { status = error.localizedDescription }
    }
}
