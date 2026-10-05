import Foundation

public enum RepairAction: String, Codable, Sendable {
    case reviewVCRuntime = "核对 VC++ v14 运行库"
    case reviewDirectXLegacy = "核对旧 DirectX 可选组件"
}
public struct RepairProposal: Identifiable, Codable, Sendable {
    public var id: String { action.rawValue }
    public let action: RepairAction
    public let targetBottle: String
    public let architecture: String
    public let evidenceIDs: [String]
    public let officialSource: URL
    public let prerequisite: String
    public let recoveryBoundary: String
    public let validation: String
}
public enum RepairPlanner {
    public static func proposals(report: AnalysisReport, bottle: Bottle?) -> [RepairProposal] {
        guard let bottle else { return [] }
        let rules: [(RepairAction, [String], String)] = [
            (
                .reviewVCRuntime, ["vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll"],
                "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist"
            ),
            (
                .reviewDirectXLegacy, ["d3dx9_43.dll", "d3dcompiler_43.dll", "xinput1_3.dll", "xaudio2_7.dll"],
                "https://www.microsoft.com/en-us/download/details.aspx?id=8109"
            ),
        ]
        return rules.compactMap { action, components, source in
            let matches = report.findings.filter { components.contains($0.component) && $0.state != .detected }
            guard !matches.isEmpty, let url = URL(string: source) else { return nil }
            return RepairProposal(
                action: action, targetBottle: bottle.name, architecture: report.architecture,
                evidenceIDs: matches.map(\.id), officialSource: url,
                prerequisite: "静态结果不足以确认缺失。先核对同架构加载错误；共享容器应建立专用副本，再确认安装来源、目标和影响。",
                recoveryBoundary: "未执行、未备份。容器副本不覆盖外部游戏、存档或映射盘；无法承诺无损回滚。",
                validation: "安装前后分别复扫，并实测最初失败的功能。组件安装退出码不等于游戏问题已修复。")
        }
    }
}
