import AppKit
import SwiftUI
import VNCore

struct LogManagementView: View {
    @Bindable var store: LibraryStore
    @AppStorage("logRetentionDays") private var days = 14
    @AppStorage("logTotalMB") private var total = 64
    @AppStorage("logActiveMB") private var active = 4
    @State private var logs: [LauncherLog] = []
    @State private var result = ""
    @State private var confirm = false
    private func refresh() { logs = LauncherLogs.list(store.logsRoot, protected: store.activeLogPaths) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "\(logs.count) 份日志 · \(ByteCountFormatter.string(fromByteCount: logs.reduce(0) { $0 + $1.bytes }, countStyle: .file))"
            )
            Picker("保留天数", selection: $days) { ForEach([7, 14, 30], id: \.self) { Text("\($0) 天").tag($0) } }
            Picker("历史容量", selection: $total) { ForEach([16, 64, 256], id: \.self) { Text("\($0) MB").tag($0) } }
            Picker("单份活跃输出", selection: $active) { ForEach([1, 4, 16], id: \.self) { Text("\($0) MB").tag($0) } }
            Text("启动器存活时每 15 秒检查，超限活跃日志截短。关闭后游戏继续写文件，容量控制暂停；被进程持有的日志不会清理。历史超期或超量日志移至废纸篓，可在 Finder 恢复。").font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("打开日志目录") { NSWorkspace.shared.open(store.logsRoot) }
                Button("清理未使用日志…") {
                    refresh()
                    confirm = true
                }.disabled(!logs.contains { !$0.active })
                Button("刷新") { refresh() }
            }
            ForEach(logs.prefix(8)) { log in
                HStack {
                    Text(log.date.formatted(date: .abbreviated, time: .shortened))
                    Text(ByteCountFormatter.string(fromByteCount: log.bytes, countStyle: .file))
                    if log.active { Text("使用中").foregroundStyle(.secondary) }
                    Spacer()
                    Button("查看") { NSWorkspace.shared.open(log.url) }
                }.font(.caption)
            }
            if !result.isEmpty { Text(result).font(.caption) }
        }.onAppear { refresh() }
            .onChange(of: days) {
                store.maintainLogs()
                refresh()
            }.onChange(of: total) {
                store.maintainLogs()
                refresh()
            }.onChange(of: active) {
                store.maintainLogs()
                refresh()
            }
            .confirmationDialog("将当前未使用日志移至废纸篓？", isPresented: $confirm) {
                Button("移至废纸篓") {
                    do {
                        try store.cleanInactiveLogs()
                        result = "清理完成，可从废纸篓恢复。"
                    } catch { result = error.localizedDescription }
                    refresh()
                }
            } message: {
                Text("仅处理 VNLauncher 的 UUID.log，使用中的日志会保留。游戏、容器和存档不会参与。")
            }
    }
}
