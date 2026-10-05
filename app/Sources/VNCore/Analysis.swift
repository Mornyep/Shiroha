import Foundation

public enum FindingState: String, Codable, Sendable {
    case detected = "已检测满足（静态候选）"
    case missing = "确认缺失"
    case verify = "需要验证"
    case conflict = "兼容问题线索"
}
public struct Finding: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public let component: String
    public let architecture: String?
    public let state: FindingState
    public let evidence: String
    public let action: String
    public init(component: String, architecture: String? = nil, state: FindingState, evidence: String, action: String) {
        self.component = component
        self.architecture = architecture
        self.state = state
        self.evidence = evidence
        self.action = action
    }
}
public struct AnalysisReport: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let gameID: UUID
    public let date: Date
    public let fingerprint: String
    public let bottleFingerprint: String
    public let runnerVersion: String
    public let systemVersion: String
    public let architecture: String
    public let findings: [Finding]
    public let notes: [String]
}
public enum Analyzer {
    public static func scan(game: Game, bottle: Bottle?, runner: Runner?) throws -> AnalysisReport {
        let root = URL(fileURLWithPath: game.workingDirectory)
        let walk = try FileSafety.walk(root)
        var notes = ["仅静态检查；动态 LoadLibrary、COM、视频与存读档仍需实测。", "扫描范围：用户所选工作目录；不跟随符号链接。"]
        if walk.limited { notes.append("达到 4000 项上限，结果不完整。") }
        var findings: [Finding] = []
        var architecture = "未知"
        var hash = "未能读取"
        var architectures = Set<String>()
        var executables = [URL(fileURLWithPath: game.executable)]
        if game.kind == .steam {
            executables = Array(
                walk.files.filter { $0.pathExtension.lowercased() == "exe" }.sorted { $0.path < $1.path }.prefix(12))
            notes.append("Steam 模式按游戏目录最多检查 12 个 EXE；不把 Steam 客户端依赖当作游戏依赖。")
        }
        var fingerprints: [String] = []
        for exe in executables {
            try Task.checkCancellation()
            do {
                let data = try FileSafety.read(exe)
                fingerprints.append(FileSafety.fingerprint(data))
                let info = try PEReader.parse(data)
                architectures.insert(info.architecture)
                findings.append(
                    Finding(
                        component: exe.lastPathComponent, state: .verify,
                        evidence: "PE \(info.architecture)；普通导入 \(info.imports.count)；延迟导入 \(info.delayed.count)",
                        action: "架构识别不代表游戏兼容。"))
                for dll in Set(info.imports + info.delayed).sorted() {
                    findings.append(
                        resolve(
                            dll: dll, architecture: info.architecture, directory: exe.deletingLastPathComponent(),
                            bottle: bottle, runner: runner))
                }
            } catch is CancellationError { throw CancellationError() } catch {
                findings.append(
                    Finding(
                        component: exe.lastPathComponent, state: .verify, evidence: error.localizedDescription,
                        action: "格式异常不等于文件损坏；请核对发行版本与补丁。"))
            }
        }
        if !architectures.isEmpty { architecture = architectures.sorted().joined(separator: " / ") }
        if !fingerprints.isEmpty { hash = FileSafety.fingerprint(Data(fingerprints.joined().utf8)) }
        let names = walk.files.map { $0.lastPathComponent.lowercased() }
        for (label, matches) in [
            ("KiriKiri", names.filter { $0.hasSuffix(".xp3") }), ("Unity", names.filter { $0 == "unityplayer.dll" }),
            ("Ren’Py", names.filter { $0.hasSuffix(".rpa") }),
        ] where !matches.isEmpty {
            findings.append(
                Finding(
                    component: label + " 引擎线索", state: .verify,
                    evidence: "特征文件：" + matches.prefix(3).joined(separator: "、"), action: "中等置信；专有插件和发行版本仍需确认。"))
        }
        let installers = names.filter { $0.contains("vcredist") || $0.contains("dxsetup") || $0.contains("vc_redist") }
        if !installers.isEmpty {
            findings.append(
                Finding(
                    component: "附带安装包", state: .verify, evidence: installers.prefix(10).joined(separator: "、"),
                    action: "仅发现文件，未执行；存在安装包不代表需要安装。"))
        }
        var bottleHash = "未选择"
        if let bottle {
            let root = URL(fileURLWithPath: bottle.path)
            var fingerprintParts: [String] = []
            for file in ["cxbottle.conf", "system.reg", "user.reg"] {
                let url = root.appendingPathComponent(file)
                guard FileSafety.contained(url, in: root), let data = try? FileSafety.read(url, limit: 16 * 1024 * 1024)
                else {
                    notes.append("未读取 \(file)，容器清单不完整。")
                    continue
                }
                fingerprintParts.append(FileSafety.fingerprint(data))
                if file.hasSuffix(".reg"), let text = String(data: data, encoding: .utf8) {
                    let records = text.components(separatedBy: .newlines).filter { $0.hasPrefix("\"DisplayName\"=") }
                        .prefix(80)
                    findings += records.map {
                        Finding(
                            component: "安装记录", state: .verify, evidence: String($0.prefix(240)),
                            action: "注册表记录不证明安装完整或位数满足。")
                    }
                    for marker in ["DllOverrides", "CodePage", "FontSubstitutes"] where text.contains(marker) {
                        notes.append("\(file) 存在 \(marker)；加载优先级/区域/字体映射需要针对游戏核验。")
                    }
                }
            }
            bottleHash = FileSafety.fingerprint(Data(fingerprintParts.joined().utf8))
            notes.append(
                "容器配置："
                    + ["Arch", "Template", "WindowsVersion"].map { "\($0)=\(bottle.configuration[$0] ?? "未知")" }.joined(
                        separator: "；"))
        }
        if findings.isEmpty { notes.append("没有可解析的 EXE；请明确选择真正入口。") }
        return AnalysisReport(
            gameID: game.id, date: Date(), fingerprint: hash, bottleFingerprint: bottleHash,
            runnerVersion: runner?.version ?? "未发现",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString, architecture: architecture,
            findings: findings, notes: notes)
    }
    public static func resolve(dll: String, architecture: String, directory: URL, bottle: Bottle?, runner: Runner?)
        -> Finding
    {
        func candidate(_ dir: URL) -> URL? {
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return urls.first { $0.lastPathComponent.lowercased() == dll && FileSafety.contained($0, in: dir) }
        }
        var candidates: [(URL, String)] = []
        if let local = candidate(directory) { candidates.append((local, "游戏私有目录")) }
        if let bottle {
            let root = URL(fileURLWithPath: bottle.path)
            for sub in ["system32", "syswow64"] {
                let dir = root.appendingPathComponent("drive_c/windows/" + sub)
                if FileSafety.contained(dir, in: root), let file = candidate(dir) {
                    candidates.append((file, "容器 " + sub))
                }
            }
        }
        var wrong: [String] = []
        var privateConflict = false
        for (url, origin) in candidates {
            guard let data = try? FileSafety.read(url), let info = try? PEReader.parse(data) else {
                wrong.append(origin + "：格式无法解析")
                if origin == "游戏私有目录" { privateConflict = true }
                continue
            }
            guard architecture != "unknown", info.architecture == architecture else {
                wrong.append(origin + "：" + info.architecture)
                if origin == "游戏私有目录" { privateConflict = true }
                continue
            }
            var source = "来源未核实"
            if let runner {
                let arch = architecture == "x86" ? "i386-windows" : "x86_64-windows"
                let builtIn = URL(
                    fileURLWithPath: runner.appPath + "/Contents/SharedSupport/CrossOver/lib/wine/" + arch + "/" + dll)
                if let built = try? FileSafety.read(builtIn),
                    FileSafety.fingerprint(data) == FileSafety.fingerprint(built)
                {
                    source = "与当前 CrossOver 自带实现哈希一致"
                }
            }
            if privateConflict {
                return Finding(
                    component: dll, architecture: architecture, state: .verify,
                    evidence: wrong.joined(separator: "；") + "；另有同架构容器候选",
                    action: "游戏私有 DLL 可能先被加载。需核对实际加载顺序，不把容器候选视为已满足。")
            }
            return Finding(
                component: dll, architecture: architecture, state: .detected,
                evidence: "\(origin)；PE \(info.architecture)；\(source)",
                action: "候选满足架构；DLL 覆盖、实际加载、导出符号和运行行为尚未验证。不要据此重复安装。")
        }
        let core = ["kernel32.dll", "user32.dll", "ntdll.dll", "gdi32.dll", "advapi32.dll", "ole32.dll", "shell32.dll"]
        let system = core.contains(dll) || dll.hasPrefix("api-ms-") || dll.hasPrefix("ext-ms-")
        return Finding(
            component: dll, architecture: architecture, state: .verify,
            evidence: wrong.isEmpty ? "适用候选目录未找到同架构实现；静态扫描不覆盖全部加载规则。" : wrong.joined(separator: "；"),
            action: system ? "属于 Windows 系统 API/契约，通常由 Wine 提供；不要下载单个 DLL。" : "核对运行错误与官方组件来源后再制定补装方案；当前不宣称确认缺失。")
    }
}
