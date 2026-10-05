import AppKit
import ImageIO
import SwiftUI
import VNCore

struct WallpaperChrome: View {
    let path: String?
    @State private var tint = Color.gray
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                tint.opacity(0.19)
                Color.white.opacity(0.22)
            }
        }.overlay(alignment: .bottom) { Color.white.opacity(0.4).frame(height: 0.5) }
            .task(id: path) {
                let components = await Task.detached(priority: .utility) { () -> [Double]? in
                    guard let path,
                        let data = try? FileSafety.read(URL(fileURLWithPath: path), limit: 20 * 1024 * 1024),
                        let source = CGImageSourceCreateWithData(data as CFData, nil),
                        let image = CGImageSourceCreateThumbnailAtIndex(
                            source, 0,
                            [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceThumbnailMaxPixelSize: 32,
                            ] as CFDictionary)
                    else { return nil }
                    var pixel = [UInt8](repeating: 0, count: 4)
                    let success = pixel.withUnsafeMutableBytes { buffer -> Bool in
                        guard
                            let context = CGContext(
                                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                        else { return false }
                        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                        return true
                    }
                    return success ? pixel.prefix(3).map { Double($0) / 255 } : nil
                }.value
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    tint = components.map { Color(red: $0[0], green: $0[1], blue: $0[2]) } ?? .gray
                }
            }.allowsHitTesting(false)
    }
}
struct LibraryOrganizationView: View {
    @Bindable var store: LibraryStore
    @AppStorage("librarySort") private var sorting = "manual"
    @State private var transfer = false
    @State private var removing: Game?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PanelHeading(title: "整理游戏库", subtitle: "排列作品，让收藏更有条理", symbol: "books.vertical")
                Spacer()
                Button("导出 / 导入…") { transfer = true }
                Button("完成") { dismiss() }
            }
            PanelTabs(items: ["手动排列", "按中文名称", "同系列相邻"], values: ["manual", "title", "series"], selection: $sorting)
            Text("给同系列作品填写相同的系列名称。手动模式可拖动行，或使用上下箭头；只改变游戏库顺序。").font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(LibraryOrdering.ordered(store.games, mode: sorting)) { game in
                    HStack(spacing: 12) {
                        CoverImage(path: game.coverPath, title: game.displayTitle).frame(width: 36, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(game.displayTitle).lineLimit(1)
                            TextField(
                                "系列名称（可选）",
                                text: Binding(
                                    get: { store.games.first { $0.id == game.id }?.series ?? "" },
                                    set: { value in
                                        var changed = store.games.first { $0.id == game.id } ?? game
                                        changed.series = value
                                        store.update(changed)
                                    })
                            ).textFieldStyle(.roundedBorder)
                        }
                        Button {
                            store.reorder(game.id, delta: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }.disabled(sorting != "manual").help("向前移动")
                        Button {
                            store.reorder(game.id, delta: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }.disabled(sorting != "manual").help("向后移动")
                        Button {
                            removing = game
                        } label: {
                            Image(systemName: "trash")
                        }.help("从游戏库移除")
                    }.padding(.vertical, 5).listRowBackground(Color.white.opacity(0.38))
                }.onMove { indices, target in store.moveVisible(indices, to: target) }.moveDisabled(sorting != "manual")
            }.scrollContentBackground(.hidden)
            Text("Steam 公共运行库等工具项已隐藏。移除库项不会删除游戏或存档；卸载本体请使用作品配置里的空间管理。").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 780, height: 600).editorSurface()
            .sheet(isPresented: $transfer) { LibraryTransferView(store: store) }
            .confirmationDialog(
                "从游戏库移除“\(removing?.displayTitle ?? "")”？游戏与存档文件会保留。",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
            ) {
                Button("仅移除库项", role: .destructive) {
                    if let game = removing { store.remove(game.id) }
                    removing = nil
                }
            }
    }
}
