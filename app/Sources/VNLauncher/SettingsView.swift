import AppKit
import SwiftUI
import VNCore

struct SettingsView: View {
    @Bindable var store: LibraryStore
    @AppStorage("steamMetadataEnabled") private var steamMetadata = false
    @AppStorage("aiProvider") private var provider = "codex"
    @AppStorage("codexModel") private var codexModel = ""
    @State private var settingsTab = "运行环境"
    @State private var checkingCodex = false
    @State private var transfer = false
    @AppStorage("aiEndpoint") private var endpoint = ""
    @AppStorage("aiModel") private var model = ""
    @State private var key = ""
    @State private var status = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelHeading(title: "设置", subtitle: "资料、运行环境与本地数据", symbol: "gearshape")
                Spacer()
                Button("完成") { dismiss() }
            }
            PanelTabs(items: ["运行环境", "游戏资料", "AI 助手", "本地数据"], selection: $settingsTab)
            Form {
                if settingsTab == "运行环境" {
                    Section("CrossOver") {
                        Text(store.runner.map { "CrossOver \($0.version)\n\($0.appPath)" } ?? "未发现 CrossOver")
                        HStack {
                            Button("选择应用…") { store.chooseRunner() }
                            Button("刷新容器") { store.refresh() }
                            Button("打开 CrossOver") {
                                if let runner = store.runner {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: runner.appPath))
                                }
                            }.disabled(store.runner == nil)
                        }
                        ForEach(store.bottles) { b in
                            Text("\(b.name) · \(b.configuration["WindowsVersion"] ?? "Windows 版本未记录")").font(.callout)
                        }
                        Button("发现容器内 Steam 游戏") {
                            store.discoverSteam()
                            dismiss()
                        }
                    }
                }
                if settingsTab == "游戏资料" {
                    Section("导入后自动补全") {
                        Text("自动查找游戏目录中的明确封面文件和本机 Steam 缓存，并运行本地静态扫描。 ")
                        Button("更新全部官方海报与中文资料") {
                            for game in store.games where !game.isUtility && game.metadataSteamID != nil {
                                store.enrich(game, publicDetails: true)
                            }
                            dismiss()
                        }.disabled(!store.metadataLoading.isEmpty)
                        Toggle("允许按 Steam App ID 获取公开资料与官方素材", isOn: $steamMetadata)
                        Text("开启后按 App ID 请求 Steam；已核验的作品可读取发行商官网海报。不会发送个人路径、日志或游戏文件。无需 AI 密钥。 ").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if settingsTab == "AI 助手" {
                    Section("AI · 优先使用你的 Codex") {
                        Picker("使用方式", selection: $provider) {
                            Text("Codex · ChatGPT 订阅").tag("codex")
                            Text("自定义 API").tag("api")
                        }
                        if provider == "codex" {
                            Text("复用本机 Codex CLI 的 ChatGPT 登录。消耗订阅中的 Codex 额度，不会自动切换到付费 API。 ").font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("模型（留空使用 Codex 默认）", text: $codexModel)
                            Button(checkingCodex ? "正在检查…" : "检查 Codex 登录") {
                                checkingCodex = true
                                Task {
                                    defer { checkingCodex = false }
                                    do {
                                        guard let path = CodexAdvisor.discover() else {
                                            throw VNError.message("未找到 Codex CLI，请先安装并使用 ChatGPT 登录。")
                                        }
                                        status = try await CodexAdvisor(executable: path).loginStatus()
                                    } catch { status = error.localizedDescription }
                                }
                            }.disabled(checkingCodex)
                            Text("每次先预览依赖摘要，再请求建议；不读取或复制你的登录凭据。 ").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("支持 OpenAI 兼容 chat/completions 接口。未配置时本地扫描和启动照常可用。这里保存配置不会发起请求。 ").font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("完整 HTTPS 端点", text: $endpoint)
                            TextField("模型名称", text: $model)
                            SecureField("API 密钥（保存到钥匙串）", text: $key)
                            Button("保存密钥") {
                                do {
                                    guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil,
                                        url.user == nil, url.password == nil, url.query == nil, !key.isEmpty
                                    else { throw VNError.message("端点或密钥为空/无效") }
                                    try CredentialStore.set(key, account: endpoint)
                                    key = ""
                                    status = "已保存至本机钥匙串，未发起网络请求。"
                                } catch { status = error.localizedDescription }
                            }
                            Text("每次请求前会显示完整外发摘要；按你的服务计费。模型链接需另行打开核验，不能视为已联网查证。 ").font(.caption).foregroundStyle(
                                .secondary)
                        }
                        if !status.isEmpty { Text(status).font(.caption) }
                    }
                }
                if settingsTab == "本地数据" {
                    Section("启动日志") { LogManagementView(store: store) }
                    Section("本地数据") {
                        Button("游戏库导出 / 导入…") { transfer = true }
                        Text(store.root.path).textSelection(.enabled)
                        Button("在 Finder 打开资料目录") { NSWorkspace.shared.open(store.root) }
                    }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
        }.padding(28).frame(width: 740, height: 580).editorSurface().sheet(isPresented: $transfer) {
            LibraryTransferView(store: store)
        }
    }
}
