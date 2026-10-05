import AppKit
import SwiftUI
import VNCore

struct LibraryTransferView: View {
    @Bindable var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = LibraryMergeMode.addOnly
    @State private var preview: LibraryTransferPreview?
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?
    @State private var undoCollectionsBefore: [GameCollection]?
    @State private var undoCollectionsAfter: [GameCollection]?
    @State private var undoBefore: [Game]?
    @State private var undoAfter: [Game]?
    @State private var relocation: Game?
    private var previewResult: LibraryMergeResult? {
        preview.map { LibraryMerge.apply($0.games, to: store.games, mode: mode) }
    }
    private var newCollectionCount: Int {
        preview?.collections.filter { incoming in
            !store.collections.contains { PersonalLibrary.nameKey($0.name) == PersonalLibrary.nameKey(incoming.name) }
        }.count ?? 0
    }
    private var unresolved: [Game] { store.games.filter { !$0.isUtility && missingLocation($0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PanelHeading(title: "游戏库迁移", subtitle: "把整理好的收藏带到另一台电脑", symbol: "arrow.left.arrow.right")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
            Text("将整理信息、进度与攻略笔记、游玩书签、收藏集、选图和启动路径保存到本地资料包。游戏本体、存档、运行日志与登录信息不包含在内。").font(.callout).foregroundStyle(
                .secondary)
            HStack(spacing: 14) {
                Button("导出游戏库…") { exportLibrary() }.disabled(
                    busy || (store.games.isEmpty && store.collections.isEmpty))
                Button("选择资料包…") { chooseImport() }.disabled(busy)
                if undoBefore != nil { Button("撤销本次导入") { undoImport() }.disabled(busy) }
            }
            if let preview, let result = previewResult {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.sourceURL.lastPathComponent).font(.headline)
                        Text(
                            "\(preview.games.count) 项作品 · \(preview.collections.count) 个收藏集 · \(preview.assetCount) 张图片"
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("取消预览") { self.preview = nil }.disabled(busy)
                }
                Picker("已有作品", selection: $mode) {
                    ForEach(LibraryMergeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().disabled(busy)
                Text("将添加 \(result.added) 项、更新 \(result.updated) 项、跳过 \(result.skipped) 项。已有作品的顺序、启动程序、参数、容器和存档位置保留。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(
                    "新增 \(newCollectionCount) 个收藏集，同名收藏集合并。更新已有作品时，资料包中的进度、攻略笔记、书签和分组关联会一并替换；旧资料包未包含这些字段时保留本机记录。存档观察授权不随资料包迁移。"
                ).font(.caption).foregroundStyle(.secondary)
                List(preview.games) { game in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.displayTitle).lineLimit(1)
                            if let existing = LibraryMerge.existingIndex(for: game, in: store.games) {
                                Text("本机：" + store.games[existing].displayTitle).font(.caption).foregroundStyle(
                                    .secondary
                                ).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(
                            LibraryMerge.existingIndex(for: game, in: store.games) == nil
                                ? "新增" : (mode == .addOnly ? "跳过" : "更新资料")
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(minHeight: 100)
                Button("确认导入") { importPreview(preview) }.buttonStyle(.borderedProminent).disabled(
                    busy || !store.writable || (result.added + result.updated == 0 && newCollectionCount == 0))
            } else {
                Divider()
                HStack {
                    Text("迁移后的位置检查").font(.headline)
                    Spacer()
                    Text("\(unresolved.count) 项待定位").font(.caption).foregroundStyle(.secondary)
                }
                if unresolved.isEmpty {
                    ContentUnavailableView(
                        "当前路径与容器引用可找到", systemImage: "externaldrive.badge.checkmark",
                        description: Text("这里只检查引用是否存在，不代表游戏已通过运行验证。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("换电脑或移动文件夹后，重新选择游戏目录、入口与容器。收藏、系列、选图和资料关联会保留。").font(.caption).foregroundStyle(.secondary)
                    List(unresolved) { game in
                        HStack {
                            Text(game.displayTitle).lineLimit(1)
                            Spacer()
                            Button("重新定位…") { relocation = game }
                        }
                    }
                }
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(28).frame(width: 780, height: 600, alignment: .topLeading).editorSurface()
            .sheet(item: $relocation) { game in DetailView(store: store, original: game) }
    }
    private func missingLocation(_ game: Game) -> Bool {
        !FileManager.default.fileExists(atPath: game.executable)
            || !FileManager.default.fileExists(atPath: game.workingDirectory)
            || !store.bottles.contains { $0.id == game.bottleID }
    }
    private func exportLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择导出位置；将创建新的 .vncollection 资料包，不覆盖已有文件。"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let name =
            "VNCollection-" + Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)) + "-"
            + UUID().uuidString.prefix(6) + ".vncollection"
        let target = folder.appendingPathComponent(name, isDirectory: true)
        let games = store.games
        let collections = store.collections
        busy = true
        error = nil
        status = nil
        Task {
            defer { busy = false }
            do {
                let receipt = try await Task.detached(priority: .utility) {
                    try LibraryTransfer.export(games: games, collections: collections, to: target)
                }.value
                status = "已导出 \(receipt.exportedCount) 项作品与 \(receipt.assetCount) 张图片：\(target.path)"
            } catch { self.error = "导出未完成：\(error.localizedDescription)" }
        }
    }
    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择 .vncollection 资料包目录；先读取预览，确认后才导入。"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        busy = true
        error = nil
        status = nil
        preview = nil
        Task {
            defer { busy = false }
            do {
                preview = try await Task.detached(priority: .utility) { try LibraryTransfer.preview(at: source) }.value
            } catch { self.error = "资料包未通过检查：\(error.localizedDescription)" }
        }
    }
    private func importPreview(_ preview: LibraryTransferPreview) {
        let cache = store.root.appendingPathComponent("Artwork")
        let selectedMode = mode
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let incoming = try await Task.detached(priority: .utility) {
                    try LibraryTransfer.importArtwork(from: preview, to: cache)
                }.value
                guard store.writable else { throw VNError.message("游戏库当前不可写。") }
                let before = store.games
                let beforeCollections = store.collections
                let merged = try PersonalLibrary.mergeCollections(
                    preview.collections, into: beforeCollections, games: incoming)
                let result = LibraryMerge.apply(merged.games, to: before, mode: selectedMode)
                let backup = store.root.appendingPathComponent("LibraryBackups/\(UUID().uuidString).json")
                try Storage.save(LibraryDocument(games: before, collections: beforeCollections), to: backup)
                try store.commitPersonalLibrary(games: result.games, collections: merged.collections)
                for id in store.progressLinks.keys { store.refreshProgress(id) }
                for game in result.games where before.first(where: { $0.id == game.id }) != game {
                    store.cancelMetadata(game.id)
                }
                undoCollectionsBefore = beforeCollections
                undoCollectionsAfter = merged.collections
                undoBefore = before
                undoAfter = result.games
                self.preview = nil
                status = "已添加 \(result.added) 项、更新 \(result.updated) 项。导入前副本已保存；请在下方处理待定位项目。"
            } catch { self.error = "导入未完成：\(error.localizedDescription)" }
        }
    }
    private func undoImport() {
        guard let before = undoBefore, let after = undoAfter, store.writable else { return }
        do {
            guard store.collections == undoCollectionsAfter, let oldCollections = undoCollectionsBefore else {
                throw VNError.message("导入后收藏集又有修改，已停止撤销以保留新内容。")
            }
            let restored = try LibraryMerge.undo(before: before, after: after, current: store.games)
            try store.commitPersonalLibrary(games: restored, collections: oldCollections)
            for id in store.progressLinks.keys { store.refreshProgress(id) }
            undoCollectionsBefore = nil
            undoCollectionsAfter = nil
            undoBefore = nil
            undoAfter = nil
            error = nil
            status = "已恢复导入前的游戏库。"
        } catch { self.error = error.localizedDescription }
    }
}
