import SwiftUI
import VNCore

struct CollectionsView: View {
    @Bindable var store: LibraryStore
    var browse: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var editing: GameCollection?
    @State private var removing: GameCollection?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PanelHeading(title: "我的收藏集", subtitle: "按你的方式，把喜欢的故事放在一起", symbol: "rectangle.stack")
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField("新收藏集名称", text: $name).textFieldStyle(.roundedBorder).onSubmit { create() }
                Button("创建收藏集") { create() }.disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.writable)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.collections) { collection in
                        let members = store.games.filter {
                            ($0.collectionIDs ?? []).contains(collection.id) && !$0.isUtility
                        }
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.04)).frame(
                                    width: 58, height: 74)
                                if let first = members.first {
                                    CoverImage(path: first.coverPath, title: first.displayTitle).frame(
                                        width: 44, height: 66
                                    ).clipShape(RoundedRectangle(cornerRadius: 2)).rotationEffect(.degrees(-4)).shadow(
                                        color: .black.opacity(0.1), radius: 5, y: 3)
                                } else {
                                    Image(systemName: "rectangle.stack").font(.title2).foregroundStyle(.secondary)
                                }
                            }.accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(collection.name).font(.headline)
                                Text("\(members.count) 部作品").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("浏览") {
                                browse(collection.id)
                                dismiss()
                            }.buttonStyle(QuietButton()).accessibilityLabel("浏览“\(collection.name)”")
                            Menu {
                                Button("重命名") { editing = collection }
                                Button("删除收藏集…", role: .destructive) { removing = collection }
                            } label: {
                                Image(systemName: "ellipsis")
                            }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("管理“\(collection.name)”")
                        }.panelSection()
                    }
                    if store.collections.isEmpty {
                        ContentUnavailableView(
                            "为收藏起个名字", systemImage: "rectangle.stack.badge.plus",
                            description: Text("例如：下一部想玩、日语阅读、夏日氛围。作品可以加入多个收藏集。"))
                    }
                }
            }
            Text("在作品详情选择“加入收藏集”。删除收藏集只移除分组，作品和游戏文件都会保留。").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 720, height: 570).editorSurface()
            .sheet(item: $editing) { collection in CollectionNameEditor(store: store, collection: collection) }
            .confirmationDialog(
                "删除“\(removing?.name ?? "")”？",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible
            ) {
                if let collection = removing {
                    Button("删除收藏集", role: .destructive) {
                        do {
                            try store.removeCollection(collection.id)
                            removing = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
            } message: {
                Text("保留所有作品，只移除分组关联。删除前会保存一份本地游戏库副本。")
            }
    }
    private func create() {
        do {
            try store.createCollection(name)
            name = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct CollectionNameEditor: View {
    @Bindable var store: LibraryStore
    let collection: GameCollection
    @State private var name = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("重命名收藏集").font(.title2)
            TextField("名称", text: $name).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存名称") {
                    do {
                        try store.renameCollection(collection.id, to: name)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 400).editorSurface().onAppear { name = collection.name }
    }
}

struct CollectionMembershipView: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    @State private var selected = Set<UUID>()
    @State private var name = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var game: Game? { store.games.first { $0.id == gameID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PanelHeading(
                    title: "加入收藏集", subtitle: game?.displayTitle ?? "作品已移除", symbol: "rectangle.stack",
                    coverPath: game?.coverPath)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存关联") {
                    do {
                        try store.saveMembership(selected, gameID: gameID)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!store.writable || game == nil)
            }
            Text("一部作品可以放入多个收藏集。").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.collections) { collection in
                        Toggle(
                            collection.name,
                            isOn: Binding(
                                get: { selected.contains(collection.id) },
                                set: {
                                    if $0 { selected.insert(collection.id) } else { selected.remove(collection.id) }
                                })
                        ).toggleStyle(.checkbox).panelSection()
                    }
                    if store.collections.isEmpty { Text("还没有收藏集，可以在下方创建。").foregroundStyle(.secondary).padding(24) }
                }
            }
            HStack {
                TextField("新收藏集名称", text: $name).textFieldStyle(.roundedBorder)
                Button("新建并勾选") {
                    do {
                        let id = try store.createCollection(name)
                        selected.insert(id)
                        name = ""
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.writable)
            }
            Text("新建会立即保存收藏集；勾选关系在“保存关联”后生效。").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }.padding(28).frame(width: 680, height: 540).editorSurface(coverPath: game?.coverPath)
            .onAppear { selected = Set(game?.collectionIDs ?? []) }
    }
}
