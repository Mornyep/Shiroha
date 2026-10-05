import AppKit
import SwiftUI
import VNCore

struct LibraryView: View {
    @Bindable var store: LibraryStore
    @AppStorage("librarySort") private var sorting = "manual"
    @AppStorage("posterSandIntensity") private var sandIntensity = 0.8
    @State private var metadataGame: Game?
    @State private var artworkGame: Game?
    @State private var storage = false
    @State private var organize = false
    @State private var collections = false
    @State private var collectionID: UUID?
    @State private var backgroundSettings = false
    @State private var filter = "全部"
    @State private var section = "全部"
    @State private var search = ""
    @State private var showSearch = false
    @State private var detail: Game?
    @State private var storyID: UUID?
    @Namespace private var artwork
    @Namespace private var tabs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var analysis: Game?
    @State private var settings = false
    @FocusState private var searchFocused: Bool
    private var games: [Game] {
        let list = store.games.filter { game in
            !game.isUtility && (collectionID == nil || (game.collectionIDs ?? []).contains(collectionID!))
                && (filter == "全部" || game.state.rawValue == filter) && (section != "收藏" || game.favorite)
                && (section != "最近" || game.lastLaunched != nil)
                && (search.isEmpty || game.searchableTitle.localizedCaseInsensitiveContains(search))
        }
        if section == "最近" {
            return list.sorted { ($0.lastLaunched ?? .distantPast) > ($1.lastLaunched ?? .distantPast) }
        }
        return LibraryOrdering.ordered(list, mode: sorting)
    }
    private var selected: Game? { games.first { $0.id == store.selectedID } ?? games.first }
    private var wallpaper: String? { (store.games.first { $0.id == storyID } ?? selected)?.coverPath }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                if storyID != nil {
                    Button {
                        closeStory()
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }.buttonStyle(QuietButton()).keyboardShortcut(.escape, modifiers: [])
                } else {
                    HStack(spacing: 25) {
                        ForEach(["全部", "在玩", "已通关"], id: \.self) { value in
                            Button {
                                withAnimation(motion) { filter = value }
                            } label: {
                                Text(value).font(.system(size: 13, weight: filter == value ? .semibold : .regular))
                                    .foregroundStyle(filter == value ? Color.primary : .secondary)
                                    .padding(.vertical, 12)
                                    .overlay(alignment: .bottom) {
                                        if filter == value {
                                            Capsule().fill(Color.primary.opacity(0.75)).frame(height: 2)
                                                .matchedGeometryEffect(id: "filter", in: tabs)
                                        }
                                    }
                            }.buttonStyle(.plain).accessibilityAddTraits(filter == value ? .isSelected : [])
                        }
                    }
                }
                Spacer(minLength: 12)
                Button {
                    organize = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 30, height: 30)
                }.buttonStyle(.plain).help("整理游戏库").accessibilityLabel("整理游戏库")
                Button {
                    backgroundSettings = true
                } label: {
                    Image(systemName: "photo").frame(width: 30, height: 30)
                }.buttonStyle(.plain).help("调整中间背景").accessibilityLabel("调整中间背景")
                    .popover(isPresented: $backgroundSettings) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("海报取色").font(.headline)
                            HStack {
                                Text("浓淡")
                                Slider(value: $sandIntensity, in: 0...1)
                                Text("\(Int(sandIntensity * 100))").monospacedDigit().frame(width: 28)
                            }
                            Button("选择壁纸与盘面…") {
                                backgroundSettings = false
                                artworkGame = store.games.first { $0.id == storyID } ?? selected
                            }
                            Text("从当前海报提取颜色，以柔和曲面铺成流沙背景。原有壁纸选图仍保留在资料中。").font(.caption).foregroundStyle(.secondary)
                        }.padding(20).frame(width: 320)
                    }
                if storyID == nil {
                    HStack(spacing: 9) {
                        Button {
                            withAnimation(motion) {
                                showSearch.toggle()
                                if !showSearch { search = "" }
                            }
                            searchFocused = showSearch
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }.buttonStyle(.plain).help("搜索游戏").accessibilityLabel("搜索游戏")
                        if showSearch {
                            TextField("搜索作品", text: $search).textFieldStyle(.plain).frame(width: 155).focused(
                                $searchFocused)
                            Button {
                                search = ""
                                withAnimation(motion) { showSearch = false }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            }.buttonStyle(.plain).accessibilityLabel("收起搜索")
                        }
                    }.font(.system(size: 14)).padding(.horizontal, 12).frame(height: 34)
                        .background(showSearch ? Color.black.opacity(0.035) : .clear, in: Capsule())
                    Button {
                        store.importFile()
                    } label: {
                        Image(systemName: "plus")
                    }.buttonStyle(QuietButton()).help("导入游戏").accessibilityLabel("导入游戏")
                }
            }.padding(.leading, 98).padding(.trailing, 30).frame(height: 62).background {
                WallpaperChrome(path: wallpaper)
            }
            if store.isDemo {
                Text("界面演示 · 合成测试资料 · 不代表已安装游戏").font(.caption).foregroundStyle(.secondary).padding(.top, 5)
            }
            HStack(spacing: 0) {
                VStack(spacing: 20) {
                    nav("books.vertical", "全部", "游戏库")
                    nav("heart", "收藏", "收藏")
                    nav("clock", "最近", "最近启动")
                    Button {
                        collections = true
                    } label: {
                        Image(systemName: "rectangle.stack").frame(width: 40, height: 40).background(
                            collectionID != nil ? Color.black.opacity(0.055) : .clear,
                            in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).help("我的收藏集").accessibilityLabel("我的收藏集")
                    Button {
                        settings = true
                    } label: {
                        Image(systemName: "gearshape").frame(width: 40, height: 40)
                    }.buttonStyle(.plain).help("设置").accessibilityLabel("设置")
                    Button {
                        storage = true
                    } label: {
                        Image(systemName: "externaldrive").frame(width: 40, height: 40)
                    }.buttonStyle(.plain).help("空间管理").accessibilityLabel("空间管理")
                    Spacer()
                }.font(.system(size: 20)).padding(.top, 20).frame(width: 64).background {
                    WallpaperChrome(path: wallpaper)
                }
                VStack(spacing: 0) {
                    if storyID == nil, let collection = store.collections.first(where: { $0.id == collectionID }) {
                        HStack {
                            Label(collection.name, systemImage: "rectangle.stack").font(
                                .system(size: 14, weight: .medium))
                            Text("\(games.count) 部作品").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("全部作品") {
                                collectionID = nil
                                filter = "全部"
                                search = ""
                            }.buttonStyle(.plain).font(.caption)
                        }.padding(.horizontal, 36).padding(.top, 18)
                    }
                    if let id = storyID, let game = store.games.first(where: { $0.id == id }) {
                        StoryDetailView(
                            store: store, game: game, artwork: artwork, configure: { detail = game },
                            inspect: { analysis = game }, editMetadata: { metadataGame = game }
                        )
                        .transition(.identity)
                    } else if let game = selected {
                        CoverFlow(
                            games: games, selectedID: Binding(get: { selected?.id }, set: { store.selectedID = $0 }),
                            artwork: artwork, open: openStory
                        )
                        .frame(maxHeight: 440).padding(.top, 10)
                        Text(game.displayTitle).font(.system(size: 25, weight: .semibold)).lineLimit(2)
                            .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 4)
                        Text(game.alias.isEmpty ? game.state.rawValue : game.alias).font(.system(size: 15))
                            .foregroundStyle(.secondary).lineLimit(1).help(game.alias).padding(.horizontal, 30).padding(
                                .top, 5)
                        HStack(spacing: 24) {
                            Button {
                                store.launch(game)
                            } label: {
                                Label("开始游戏", systemImage: "play.fill").font(.system(size: 16, weight: .medium))
                                    .padding(.horizontal, 20).padding(.vertical, 7)
                            }.buttonStyle(PrimaryCapsule()).disabled(store.isDemo)
                            Button("探索作品") { openStory(game) }.buttonStyle(.plain).font(.system(size: 15))
                        }.padding(.top, 18)
                        if !FileManager.default.fileExists(atPath: game.executable) {
                            Button("游戏位置已改变 · 重新定位") { detail = game }.buttonStyle(.plain).font(.caption)
                                .foregroundStyle(.secondary).padding(.top, 12)
                        } else if let series = game.series, !series.isEmpty {
                            Text(series).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(series).padding(
                                .horizontal, 30
                            ).padding(.top, 12)
                        }
                        Spacer(minLength: 16)
                        HStack {
                            Spacer()
                            Button {
                                move(-1)
                            } label: {
                                Image(systemName: "chevron.left")
                            }.disabled(selected?.id == games.first?.id).help("上一款")
                            Text("\((games.firstIndex { $0.id == game.id } ?? 0) + 1) / \(games.count)")
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 76)
                            Button {
                                move(1)
                            } label: {
                                Image(systemName: "chevron.right")
                            }.disabled(selected?.id == games.last?.id).help("下一款")
                            Spacer()
                        }.buttonStyle(.plain).padding(.horizontal, 26).padding(.bottom, 26)
                    } else {
                        Spacer()
                        Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 44, weight: .ultraLight))
                            .foregroundStyle(.secondary)
                        Text(store.games.isEmpty ? "把故事放在这里" : "没有符合条件的游戏").font(.title2).padding(.top, 16)
                        Text(collectionID != nil ? "从作品详情加入这个收藏集，或切换筛选条件。" : "选择 EXE 或拖入游戏目录，文件会留在原处。").foregroundStyle(
                            .secondary
                        ).padding(.top, 6)
                        if collectionID != nil {
                            Button("查看全部作品") {
                                collectionID = nil
                                filter = "全部"
                                search = ""
                            }.buttonStyle(QuietButton()).padding(.top, 20)
                        } else {
                            HStack {
                                Button("导入游戏…") { store.importFile() }.buttonStyle(.borderedProminent)
                                Button("发现 Steam 游戏") { store.discoverSteam() }.buttonStyle(.bordered)
                            }.padding(.top, 20)
                        }
                        Text(
                            store.runner.map { "CrossOver \($0.version) · \(store.bottles.count) 个现有容器" }
                                ?? "未发现 CrossOver · 可在设置中选择"
                        ).font(.caption).foregroundStyle(.secondary).padding(.top, 18)
                        Spacer()
                    }
                }.frame(maxWidth: .infinity)
            }
        }.background { GameBackdrop(path: wallpaper, intensity: sandIntensity) }.tint(
            Color(red: 0.24, green: 0.31, blue: 0.31)
        )
        .overlay(alignment: .topTrailing) { if store.busy { ProgressView().controlSize(.small).padding(70) } }
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first {
                store.importURL(url)
                return true
            }
            return false
        }
        .sheet(item: $metadataGame) { game in MetadataEditor(store: store, gameID: game.id) }
        .sheet(item: $artworkGame) { game in ArtworkStudio(store: store, gameID: game.id) }
        .sheet(item: $detail) { game in DetailView(store: store, original: game) }
        .sheet(item: $analysis) { game in AnalysisView(store: store, gameID: game.id) }
        .sheet(isPresented: $storage) { StorageView(store: store) }
        .sheet(isPresented: $collections) {
            CollectionsView(store: store) { id in
                collectionID = id
                section = "全部"
                filter = "全部"
                search = ""
                storyID = nil
            }
        }
        .onChange(of: store.collections.map(\.id)) { _, ids in
            if let collectionID, !ids.contains(collectionID) { self.collectionID = nil }
        }
        .sheet(isPresented: $organize) { LibraryOrganizationView(store: store) }
        .sheet(isPresented: $settings) { SettingsView(store: store) }
        .sheet(isPresented: $store.showCandidates) { CandidateView(store: store) }
        .alert("提示", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("好") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
        .onChange(of: games.map(\.id)) { _, ids in
            if !ids.contains(store.selectedID ?? UUID()) { store.selectedID = ids.first }
        }
    }
    private var motion: Animation? { reduceMotion ? nil : LibraryMotion.navigation }
    private func openStory(_ game: Game) {
        store.selectedID = game.id
        searchFocused = false
        withAnimation(motion) { storyID = game.id }
    }
    private func closeStory() {
        withAnimation(motion) { storyID = nil }
    }
    private func move(_ delta: Int) {
        guard let game = selected, let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        store.selectedID = games[min(max(i + delta, 0), games.count - 1)].id
    }
    private func nav(_ symbol: String, _ value: String, _ label: String) -> some View {
        Button {
            withAnimation(motion) {
                section = value
                collectionID = nil
                storyID = nil
            }
        } label: {
            Image(systemName: symbol).foregroundStyle(
                section == value && collectionID == nil ? Color(red: 0.24, green: 0.31, blue: 0.31) : .primary
            ).frame(width: 42, height: 42).background(
                section == value && collectionID == nil ? Color.black.opacity(0.055) : .clear,
                in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
struct CoverFlow: View {
    let games: [Game]
    @Binding var selectedID: UUID?
    let artwork: Namespace.ID
    let open: (Game) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverLocation: CGPoint?
    @State private var drag: CGFloat = 0
    @State private var scrollWork: DispatchWorkItem?
    @FocusState private var focused: Bool
    var index: Int { games.firstIndex { $0.id == selectedID } ?? 0 }
    var body: some View {
        GeometryReader { geo in
            let height = min(geo.size.height - 30, 420)
            let size = min(height * 2 / 3, geo.size.width * 0.32)
            let stride = max(145.0, size * 0.90)
            ZStack {
                Color.clear
                ForEach(Array(games.enumerated()).filter { abs($0.offset - index) <= 3 }, id: \.element.id) { i, game in
                    let distance = CGFloat(i - index) + drag / stride
                    GameCase(
                        path: game.coverPath, title: game.displayTitle,
                        pointer: i == index ? posterPointer(in: geo.size, width: size) : nil, tracksLocalPointer: false
                    )
                    .frame(width: size, height: size * 1.5)
                    .matchedGeometryEffect(id: game.id, in: artwork)
                    .shadow(color: .black.opacity(abs(distance) < 0.5 ? 0.09 : 0.03), radius: 22, y: 16)
                    .scaleEffect(max(0.70, 1 - abs(distance) * 0.18))
                    .rotation3DEffect(
                        .degrees(reduceMotion ? 0 : Double(max(-1, min(1, distance))) * -38), axis: (x: 0, y: 1, z: 0),
                        perspective: 0.28
                    )
                    .offset(x: position(distance, stride: stride))
                    .zIndex(10 - Double(abs(distance)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(game.displayTitle)，第 \(i + 1) 款，共 \(games.count) 款")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        focused = true
                        if i == index { open(game) } else { snap(to: i) }
                    }
                    .onTapGesture {
                        focused = true
                        if i == index { open(game) } else { snap(to: i) }
                    }
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
                .contentShape(Rectangle())
                .overlay {
                    FlowInputSurface(
                        onDrag: { delta, ended in
                            hoverLocation = nil
                            scrollWork?.cancel()
                            drag = bounded(delta, stride: stride)
                            if ended { snap(to: index - Int((drag / stride).rounded())) }
                        },
                        onScroll: { delta, ended in
                            scrollWork?.cancel()
                            drag = bounded(drag + delta, stride: stride)
                            let work = DispatchWorkItem { snap(to: index - Int((drag / stride).rounded())) }
                            scrollWork = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + (ended ? 0.04 : 0.16), execute: work)
                        },
                        onTap: { x in
                            let offset = x - geo.size.width / 2
                            guard abs(offset) > size / 2 else {
                                focused = true
                                if !games.isEmpty { open(games[index]) }
                                return
                            }
                            let candidates = games.indices.sorted {
                                abs(position(CGFloat($0 - index), stride: stride) - offset)
                                    < abs(position(CGFloat($1 - index), stride: stride) - offset)
                            }
                            if let target = candidates.first { snap(to: target) }
                        }, onKey: { delta in snap(to: index + delta) },
                        onOpen: {
                            if !games.isEmpty { open(games[index]) }
                        }, onHover: { hoverLocation = $0 }
                    ).accessibilityHidden(true)
                }

        }.focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(.return) {
                if !games.isEmpty { open(games[index]) }
                return .handled
            }
            .onKeyPress(.leftArrow) {
                snap(to: index - 1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                snap(to: index + 1)
                return .handled
            }
            .onAppear { focused = true }
            .onDisappear { scrollWork?.cancel() }
    }
    private func posterPointer(in size: CGSize, width: CGFloat) -> CGPoint? {
        guard let point = hoverLocation, drag == 0 else { return nil }
        let rectangle = CGRect(
            x: (size.width - width) / 2, y: (size.height - width * 1.5) / 2, width: width, height: width * 1.5)
        guard rectangle.contains(point) else { return nil }
        return CGPoint(
            x: (point.x - rectangle.minX) / rectangle.width, y: (point.y - rectangle.minY) / rectangle.height)
    }
    private func position(_ value: CGFloat, stride: CGFloat) -> CGFloat {
        if abs(value) <= 1 { return value * stride }
        return (value < 0 ? -1 : 1) * stride * (1 + (abs(value) - 1) * 0.68)
    }
    private func bounded(_ value: CGFloat, stride: CGFloat) -> CGFloat {
        let low = -CGFloat(games.count - 1 - index) * stride
        let high = CGFloat(index) * stride
        return value < low ? low + (value - low) * 0.2 : (value > high ? high + (value - high) * 0.2 : value)
    }
    private func snap(to i: Int) {
        hoverLocation = nil
        guard !games.isEmpty else { return }
        withAnimation(reduceMotion ? nil : LibraryMotion.selection) {
            selectedID = games[min(max(i, 0), games.count - 1)].id
            drag = 0
        }
    }
}
struct CoverImage: View {
    let path: String?
    let title: String
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "book.closed").font(.system(size: 52, weight: .ultraLight))
                    Text(title).font(.title2).lineLimit(3).multilineTextAlignment(.center)
                    Text("添加本地封面").font(.caption).foregroundStyle(.secondary)
                }.padding(30).foregroundStyle(.secondary)
            }
        }.task(id: path) { if let path { image = await CoverCache.shared.image(path) } else { image = nil } }
    }
}
@MainActor final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, NSImage>()
    func image(_ path: String) async -> NSImage? {
        let key = path as NSString
        if let value = cache.object(forKey: key) { return value }
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let data = try? FileSafety.read(URL(fileURLWithPath: path), limit: 20 * 1024 * 1024),
                let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        }.value
        guard !Task.isCancelled, let cg else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }
}
struct FlowInputSurface: NSViewRepresentable {
    var onDrag: (CGFloat, Bool) -> Void
    var onScroll: (CGFloat, Bool) -> Void
    var onTap: (CGFloat) -> Void
    var onKey: (Int) -> Void
    var onOpen: () -> Void
    var onHover: (CGPoint?) -> Void
    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) {
        view.onDrag = onDrag
        view.onScroll = onScroll
        view.onTap = onTap
        view.onKey = onKey
        view.onOpen = onOpen
        view.onHover = onHover
    }
    @MainActor final class InputView: NSView {
        var onDrag: ((CGFloat, Bool) -> Void)?
        var onScroll: ((CGFloat, Bool) -> Void)?
        var onTap: ((CGFloat) -> Void)?
        var onKey: ((Int) -> Void)?
        var onOpen: (() -> Void)?
        var onHover: ((CGPoint?) -> Void)?
        private var hoverTracking: NSTrackingArea?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTracking { removeTrackingArea(hoverTracking) }
            let area = NSTrackingArea(
                rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverTracking = area
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }
        override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onHover?(CGPoint(x: point.x, y: bounds.height - point.y))
        }
        override func mouseExited(with event: NSEvent) { onHover?(nil) }
        var start: CGFloat = 0
        var dragged = false
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) {
            onHover?(nil)
            window?.makeFirstResponder(self)
            start = convert(event.locationInWindow, from: nil).x
            dragged = false
        }
        override func mouseDragged(with event: NSEvent) {
            let delta = convert(event.locationInWindow, from: nil).x - start
            if abs(delta) > 3 { dragged = true }
            if dragged { onDrag?(delta, false) }
        }
        override func mouseUp(with event: NSEvent) {
            let x = convert(event.locationInWindow, from: nil).x
            if dragged { onDrag?(x - start, true) } else { onTap?(x) }
        }
        override func scrollWheel(with event: NSEvent) {
            guard abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) else {
                super.scrollWheel(with: event)
                return
            }
            window?.makeFirstResponder(self)
            onScroll?(
                event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 12),
                event.phase == .ended || event.momentumPhase == .ended)
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 123 {
                onKey?(-1)
            } else if event.keyCode == 124 {
                onKey?(1)
            } else if event.keyCode == 36 || event.keyCode == 76 {
                onOpen?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

struct PrimaryCapsule: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
            .background(
                Color(red: 0.24, green: 0.31, blue: 0.31).opacity(
                    enabled ? (configuration.isPressed ? 0.78 : 1) : 0.45), in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
            .padding(.horizontal, 12).frame(height: 34)
            .background(Color.black.opacity(configuration.isPressed ? 0.08 : 0.035), in: Capsule())
    }
}
