import AppKit
import SwiftUI
import VNCore

// Shared renderer ensures editor and case have identical crop and spindle geometry.
struct DiscFace: View {
    let art: ArtworkSelection?
    let title: String
    @State private var image: NSImage?
    var body: some View {
        GeometryReader { g in
            let diameter = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(Color(red: 0.65, green: 0.66, blue: 0.63))
                ZStack {
                    Color(red: 0.14, green: 0.21, blue: 0.25)
                    if let art, let image, image.size.width > 0, image.size.height > 0 {
                        let d = diameter * 0.98
                        let scale = max(d / image.size.width, d / image.size.height) * art.safeZoom
                        let w = image.size.width * scale
                        let h = image.size.height * scale
                        Image(nsImage: image).resizable().frame(width: w, height: h)
                            .position(
                                x: w / 2 - (w - d) * ArtworkSelection.unit(art.horizontal),
                                y: h / 2 - (h - d) * ArtworkSelection.unit(art.vertical))
                    } else {
                        VStack(spacing: diameter * 0.20) {
                            Text(title).font(.system(size: max(9, diameter * 0.065), weight: .medium)).lineLimit(3)
                            Text("COLLECTION").font(.system(size: max(6, diameter * 0.035), design: .monospaced))
                                .tracking(2)
                        }.padding(diameter * 0.14).foregroundStyle(.white.opacity(0.9))
                    }
                }.frame(width: diameter * 0.98, height: diameter * 0.98).clipShape(Circle())
                Circle().fill(
                    AngularGradient(
                        colors: [.white.opacity(0.10), .clear, .white.opacity(0.025), .clear, .white.opacity(0.05)],
                        center: .center))
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: diameter * 0.006).frame(
                    width: diameter * 0.17, height: diameter * 0.17)
                Circle().fill(Color(white: 0.13)).frame(width: diameter * 0.10, height: diameter * 0.10)
                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: diameter * 0.006) }
            }.frame(width: diameter, height: diameter).shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }.task(id: art?.path) {
            image = nil
            if let path = art?.path { image = await CoverCache.shared.image(path) }
        }.accessibilityLabel(art == nil ? "文字收藏盘面，未选择插图" : "盘面预览，含中心孔")
    }
}

struct ArtworkStudio: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var role = ArtworkRole.wallpaper
    @State private var wallpaper: ArtworkSelection?
    @State private var disc: ArtworkSelection?
    @State private var changed: Set<String> = []
    @State private var loaded = false
    @State private var fetching = false
    @State private var error: String?
    private var game: Game? { store.games.first { $0.id == gameID } }
    private var selection: ArtworkSelection? { role == .wallpaper ? wallpaper : disc }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelHeading(
                    title: "图片资料", subtitle: game?.displayTitle ?? "作品已移除", symbol: "photo.on.rectangle",
                    coverPath: game?.coverPath)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(
                    changed.isEmpty || fetching || game == nil)
            }
            PanelTabs(
                items: ArtworkRole.allCases.map(\.rawValue),
                selection: Binding(
                    get: { role.rawValue }, set: { role = ArtworkRole(rawValue: $0) ?? .wallpaper }
                ))
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.16))
                            if role == .disc {
                                DiscFace(art: disc, title: game?.displayTitle ?? "").frame(width: 290, height: 290)
                                    .padding(
                                        15)
                            } else if let wallpaper, let image = NSImage(contentsOfFile: wallpaper.path) {
                                Image(nsImage: image).resizable().scaledToFit().padding(10)
                            } else {
                                Text("尚未选择壁纸").foregroundStyle(.white.opacity(0.8))
                            }
                        }.frame(width: 360, height: 320).clipped()
                        Text(role == .disc ? "与盒内盘面使用相同裁切与中心孔。" : "完整显示原图，不裁切；预览不加模糊。").font(.caption).foregroundStyle(
                            .secondary)
                        if let selection, let size = ArtworkQuality.size(selection.path) {
                            Text(size.label).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Button("选择本地图片…") { chooseLocal() }
                        Button(fetching ? "正在载入…" : "使用已审选的官方素材") { fetchRecommended() }.disabled(
                            fetching
                                || game.flatMap { $0.metadataSteamID }.flatMap { ArtworkCatalog.entries[$0] } == nil)
                        if role == .disc, disc != nil {
                            Divider()
                            adjustment("水平构图", keyPath: \.horizontal, range: 0...1)
                            adjustment("垂直构图", keyPath: \.vertical, range: 0...1)
                            adjustment("缩放", keyPath: \.zoom, range: 1...2.5)
                            Text("让面部避开中心孔，并检查头顶和圆形边缘。切换壁纸不会改变盘面。").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(
                                    horizontal: false, vertical: true)
                        }
                        if let selection {
                            Divider()
                            Text(selection.reason).font(.callout).fixedSize(horizontal: false, vertical: true)
                            if let url = URL(string: selection.source), url.scheme == "https" {
                                Link("查看图片来源 ↗", destination: url)
                            } else {
                                Text(selection.source).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("保存后锁定此用途的选择，刷新公开资料不会覆盖。插图盘面为展示设计。").font(.caption).foregroundStyle(.secondary).fixedSize(
                            horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }.padding(28).frame(width: 780, height: 600).editorSurface(coverPath: game?.coverPath).onAppear {
            guard !loaded else { return }
            loaded = true
            wallpaper = game?.metadata?.chosenWallpaper
            disc = game?.metadata?.discArtwork
        }
    }
    private func adjustment(
        _ label: String, keyPath: WritableKeyPath<ArtworkSelection, Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption)
            Slider(
                value: Binding(
                    get: { disc?[keyPath: keyPath] ?? range.lowerBound },
                    set: { value in
                        disc?[keyPath: keyPath] = value
                        changed.insert(ArtworkRole.disc.rawValue)
                    }), in: range
            ).accessibilityLabel(label)
        }
    }
    private func chooseLocal() {
        guard let path = store.choosePath(directory: false, message: "选择\(role.rawValue)图片"),
            let size = ArtworkQuality.size(path)
        else { return }
        guard role != .wallpaper || size.width >= size.height else {
            error = "壁纸请选择横版图片，以保留完整构图。"
            return
        }
        set(ArtworkSelection(path: path, source: "手动选择", reason: "本地图片，请检查预览后保存。", userLocked: true), for: role)
    }
    private func set(_ art: ArtworkSelection, for target: ArtworkRole) {
        if target == .wallpaper { wallpaper = art } else { disc = art }
        changed.insert(target.rawValue)
        error = nil
    }
    private func fetchRecommended() {
        guard let game, let id = game.metadataSteamID else { return }
        let target = role
        fetching = true
        error = nil
        Task {
            defer { fetching = false }
            do {
                if let art = try await ArtworkCatalog.fetch(
                    appID: id, role: target, directory: store.root.appendingPathComponent("Artwork"))
                {
                    set(art, for: target)
                }
            } catch { self.error = "素材未载入：\(error.localizedDescription)" }
        }
    }
    private func save() {
        guard var current = game else { return }
        for art in [
            changed.contains(ArtworkRole.wallpaper.rawValue) ? wallpaper : nil,
            changed.contains(ArtworkRole.disc.rawValue) ? disc : nil,
        ].compactMap({ $0 }) {
            guard ArtworkQuality.size(art.path) != nil else {
                error = "图片已不可读取，请重新选择。"
                return
            }
        }
        var meta = current.metadata ?? GameMetadata()
        if changed.contains(ArtworkRole.wallpaper.rawValue), var art = wallpaper {
            art.userLocked = true
            meta.wallpaperArtwork = art
            meta.backgroundPath = art.path
            meta.backgroundSource = "手动选择"
        }
        if changed.contains(ArtworkRole.disc.rawValue), var art = disc {
            art.userLocked = true
            meta.discArtwork = art
        }
        current.metadata = meta
        do {
            try store.commitMetadata(current, reason: "调整选图")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
