import SwiftUI
import VNCore

private enum DetailSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case play = "游玩"
    case guide = "攻略"
    case reviews = "评论"
    var id: String { rawValue }
}

struct StoryDetailView: View {
    @Bindable var store: LibraryStore
    let game: Game
    let artwork: Namespace.ID
    let configure: () -> Void
    let inspect: () -> Void
    let editMetadata: () -> Void
    @State private var detailsVisible = false
    @State private var membership = false
    @State private var sources = false
    @State private var section = DetailSection.overview
    @State private var fullSummary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(145.0, min(230.0, geometry.size.width * 0.29, (geometry.size.height - 245) / 1.5))
            HStack(alignment: .top, spacing: geometry.size.width < 950 ? 28 : 46) {
                ScrollView {
                    VStack(spacing: 16) {
                        GameCase(path: game.coverPath, title: game.displayTitle)
                            .frame(width: width, height: width * 1.5)
                            .matchedGeometryEffect(id: game.id, in: artwork)
                            .accessibilityLabel(game.displayTitle + "海报")
                        CoverRatings(game: game) { sources = true }
                        Button {
                            store.launch(game)
                        } label: {
                            Label("开始游戏", systemImage: "play.fill")
                                .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity).padding(
                                    .vertical, 10)
                        }.buttonStyle(PrimaryCapsule()).disabled(store.isDemo)
                        HStack(spacing: 20) {
                            Button(action: configure) { Label("配置", systemImage: "slider.horizontal.3") }
                            Button {
                                var edited = game
                                edited.favorite.toggle()
                                store.update(edited)
                            } label: {
                                Label(game.favorite ? "已收藏" : "收藏", systemImage: game.favorite ? "heart.fill" : "heart")
                            }
                        }.font(.caption).buttonStyle(.plain)
                        Menu("更多操作", systemImage: "ellipsis") {
                            Button("加入收藏集") { membership = true }
                            Button("编辑资料与图片", action: editMetadata)
                            Button("兼容检查", action: inspect)
                            Button("评分与来源") { sources = true }
                        }.menuStyle(.borderlessButton).font(.caption).fixedSize()
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden).frame(width: width)
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(game.displayTitle).font(.system(size: 30, weight: .semibold))
                            .tracking(-0.5).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            .help(game.displayTitle).textSelection(.enabled)
                        HStack(spacing: 10) {
                            Text(game.state.rawValue)
                            if let date = game.metadata?.releaseDate { Text(date) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    sectionNavigation
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            switch section {
                            case .overview: overview
                            case .play:
                                ProgressCard(store: store, game: game, section: .progress)
                                Divider().opacity(0.4)
                                BookmarkCard(store: store, game: game)
                            case .guide:
                                ProgressCard(store: store, game: game, section: .guide)
                                Divider().opacity(0.4)
                                GuidePlanCard(store: store, game: game)
                                Divider().opacity(0.4)
                                GuideSourcesView(game: game)
                            case .reviews: SteamReviewsView(store: store, game: game)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8).padding(.bottom, 24)
                    }.scrollIndicators(.hidden).id(section)
                }.padding(.top, 5)
                    .opacity(detailsVisible ? 1 : 0)
                    .offset(y: detailsVisible || reduceMotion ? 0 : 12)
            }.frame(maxWidth: 1100).frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 20)
                .task(id: game.id) {
                    if reduceMotion {
                        detailsVisible = true
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    withAnimation(.easeOut(duration: 0.30)) { detailsVisible = true }
                }
        }
        .sheet(isPresented: $membership) { CollectionMembershipView(store: store, gameID: game.id) }
        .sheet(isPresented: $sources) { SourceDetailsSheet(store: store, gameID: game.id) }
        .onChange(of: game.id) { _, _ in
            section = .overview
            fullSummary = false
        }
    }

    private var sectionNavigation: some View {
        PanelTabs(
            items: DetailSection.allCases.map(\.rawValue),
            selection: Binding(get: { section.rawValue }, set: { section = DetailSection(rawValue: $0) ?? .overview })
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("作品内容")
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(game.metadata?.summary.map(MetadataService.plainText) ?? "还没有作品简介。")
                .font(.system(size: 15)).lineSpacing(7).lineLimit(fullSummary ? nil : 8).textSelection(.enabled)
            if (game.metadata?.summary?.count ?? 0) > 250 {
                Button(fullSummary ? "收起简介" : "展开简介") { fullSummary.toggle() }.buttonStyle(.plain).font(.caption)
            }
            if let developer = game.metadata?.developer, !developer.isEmpty {
                LabeledContent("开发", value: developer).font(.callout)
            }
            if let genres = game.metadata?.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if !(game.collectionIDs ?? []).isEmpty {
                Text(
                    store.collections.filter { (game.collectionIDs ?? []).contains($0.id) }.map(\.name).joined(
                        separator: " · ")
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Divider().opacity(0.4)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.progress?.manual.map { $0.label.isEmpty ? "留下你的阅读位置" : $0.label } ?? "留下你的阅读位置")
                        .font(.callout).lineLimit(2)
                    if !game.allBookmarks.isEmpty {
                        Text("\(game.allBookmarks.count) 个书签").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("游玩记录") { section = .play }.buttonStyle(QuietButton())
            }
            if let source = game.metadata?.detailSource, let url = PublicLink.url(source) {
                Link("Steam 作品页面 ↗", destination: url).font(.caption)
            }
            SteamRefreshButton(store: store, game: game)
        }
    }
}

private struct CoverRatings: View {
    let game: Game
    let openSources: () -> Void

    var body: some View {
        Button(action: openSources) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(PublicSource.allCases) { source in
                    let profile = game.metadata?.publicProfiles?.first { $0.source == source }
                    rating(source.rawValue, value: profile?.score.map { String(format: "%.1f", $0) } ?? "—")
                }
                if let reviews = game.metadata?.reviews, reviews.totalReviews > 0 {
                    rating(
                        "Steam",
                        value: String(
                            format: "%.0f%%", Double(reviews.totalPositive) / Double(reviews.totalReviews) * 100))
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("评分与来源")
            .help("查看评分人数、口径与来源，或关联新条目")
    }

    private func rating(_ source: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(source).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct SourceDetailsSheet: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("评分与来源").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                if let game = store.games.first(where: { $0.id == gameID }) {
                    PublicSourcesCard(store: store, game: game)
                    if let reviews = game.metadata?.reviews {
                        Divider().padding(.vertical, 16)
                        Text("Steam · \(reviews.totalPositive) / \(reviews.totalReviews) 条好评")
                        Text("全语言评论汇总 · " + reviews.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(28).frame(width: 660, height: 570)
    }
}

struct SteamRefreshButton: View {
    @Bindable var store: LibraryStore
    let game: Game
    var body: some View {
        if game.metadataSteamID != nil {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    store.enrich(game, publicDetails: true)
                } label: {
                    Label(
                        store.metadataLoading.contains(game.id) ? "正在读取…" : "更新 Steam 资料",
                        systemImage: "arrow.clockwise")
                }.buttonStyle(.plain).font(.caption).disabled(store.metadataLoading.contains(game.id))
                if let status = store.metadataStatus[game.id] {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
