import SwiftUI
import VNCore

struct BookmarkCard: View {
    @Bindable var store: LibraryStore
    let game: Game
    @State private var editing: NamedBookmark?
    @State private var adding = false
    @State private var revealed = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("我的书签", systemImage: "bookmark").font(.headline)
                Text("\(game.allBookmarks.count)").foregroundStyle(.secondary)
                Spacer()
                Button("新建书签") { adding = true }.buttonStyle(.plain)
                    .disabled(game.allBookmarks.count >= 50)
            }
            if game.allBookmarks.isEmpty {
                Text("留下一处，下次接着读。").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(game.allBookmarks) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(item.name).font(.callout).fontWeight(.medium)
                        Spacer()
                        Button("编辑") { editing = item }.accessibilityLabel("编辑书签 " + item.name)
                    }
                    Text(item.value.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if item.value.hidesSpoilers {
                        Button(revealed.contains(item.id) ? "收起内容" : "展开内容 · 含剧透") {
                            if revealed.contains(item.id) { revealed.remove(item.id) } else { revealed.insert(item.id) }
                        }.font(.caption)
                    }
                    if !item.value.hidesSpoilers || revealed.contains(item.id) {
                        let value = item.value
                        if !value.chapter.isEmpty || !value.route.isEmpty {
                            Text([value.route, value.chapter].filter { !$0.isEmpty }.joined(separator: " · ")).font(
                                .callout)
                        }
                        if !value.note.isEmpty { Text(value.note).font(.callout).textSelection(.enabled) }
                        if !value.nextStep.isEmpty {
                            Text("下次：" + value.nextStep).font(.callout).textSelection(.enabled)
                        }
                    }
                }.buttonStyle(.plain).padding(.vertical, 10)
                if item.id != game.allBookmarks.last?.id { Divider().opacity(0.4) }
            }
        }
        .sheet(isPresented: $adding) { BookmarkEditor(store: store, gameID: game.id, existing: nil) }
        .sheet(item: $editing) { BookmarkEditor(store: store, gameID: game.id, existing: $0) }
        .onChange(of: game.allBookmarks) { _, _ in revealed.removeAll() }
        .onChange(of: game.id) { _, _ in revealed.removeAll() }
    }
}

struct BookmarkEditor: View {
    @Bindable var store: LibraryStore
    let gameID: UUID
    var existing: NamedBookmark? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var draft = PlayBookmark()
    @State private var error: String?
    @State private var clearing = false
    private var game: Game? { store.games.first { $0.id == gameID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PanelHeading(
                    title: existing == nil ? "新建书签" : "编辑书签", subtitle: game?.displayTitle ?? "作品已移除",
                    symbol: "bookmark", coverPath: game?.coverPath)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存书签", action: save).buttonStyle(.borderedProminent).disabled(!store.writable || game == nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("书签名称", placeholder: "例如：周末接着读", text: $name)
                    HStack(alignment: .top, spacing: 18) {
                        field("当前章节", placeholder: "第二章", text: $draft.chapter)
                        field("当前路线", placeholder: "共通线", text: $draft.route)
                    }
                    editor("停在这里", text: $draft.note, limit: 2000)
                    editor("下次想做", text: $draft.nextStep, limit: 1000)
                    Toggle("默认隐藏内容", isOn: $draft.hidesSpoilers).font(.callout)
                }.padding(2)
            }
            HStack {
                if existing != nil { Button("删除书签…", role: .destructive) { clearing = true } }
                Spacer()
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.padding(28).frame(width: 700, height: 600).editorSurface(coverPath: game?.coverPath)
            .onAppear {
                draft = existing?.value ?? PlayBookmark()
                name = existing?.name ?? "书签 \((game?.allBookmarks.count ?? 0) + 1)"
            }
            .confirmationDialog("删除这个书签？", isPresented: $clearing, titleVisibility: .visible) {
                Button("删除书签", role: .destructive) {
                    do {
                        if let existing { try store.removeBookmark(existing.id, gameID: gameID) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            } message: {
                Text("不影响游戏存档。删除前会保留本地资料库副本。")
            }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }

    private func editor(_ title: String, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(text.wrappedValue.count) / \(limit)").font(.caption)
                    .foregroundStyle(text.wrappedValue.count > limit ? .red : .secondary)
            }
            TextEditor(text: text).font(.callout).padding(8).frame(height: title == "停在这里" ? 110 : 80)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel(title)
        }
    }

    private func save() {
        do {
            draft.updatedAt = Date()
            let item = NamedBookmark(
                id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), value: draft)
            try store.saveNamedBookmark(item, gameID: gameID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
