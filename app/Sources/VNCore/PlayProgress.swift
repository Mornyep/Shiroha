import Foundation

public struct ProgressPosition: Codable, Equatable, Sendable {
    public var chapter = ""
    public var route = ""
    public var updatedAt = Date()
    public init(chapter: String = "", route: String = "") {
        self.chapter = chapter
        self.route = route
    }
    public var label: String { [route, chapter].filter { !$0.isEmpty }.joined(separator: " · ") }
}
public struct SaveSlotObservation: Codable, Equatable, Identifiable, Sendable {
    public var id: String { filename }
    public let filename: String
    public let modifiedAt: Date
    public let fingerprint: String
    public var script: String?
    public var recordedAt: Date?
    public init(filename: String, modifiedAt: Date, fingerprint: String, script: String? = nil, recordedAt: Date? = nil)
    {
        self.filename = filename
        self.modifiedAt = modifiedAt
        self.fingerprint = fingerprint
        self.script = script
        self.recordedAt = recordedAt
    }
}
public struct SaveObservation: Codable, Equatable, Sendable {
    public var scannedAt = Date()
    public var fingerprint: String
    public var slots: [SaveSlotObservation]
    public var adapter: String
    public init(fingerprint: String, slots: [SaveSlotObservation], adapter: String) {
        self.fingerprint = fingerprint
        self.slots = slots
        self.adapter = adapter
    }
    public var newest: SaveSlotObservation? {
        slots.sorted { $0.modifiedAt == $1.modifiedAt ? $0.filename < $1.filename : $0.modifiedAt > $1.modifiedAt }
            .first
    }
}
public struct GuideNote: Codable, Equatable, Sendable {
    public var title = ""
    public var url = ""
    public var version = ""
    public var language = "中文"
    public var chapter = ""
    public var route = ""
    public var target = ""
    public var hint = ""
    public var checkedAt = Date()
    public init() {}
}
public struct PlayProgress: Codable, Equatable, Sendable {
    public var target = ""
    public var gameVersion = ""
    public var manual: ProgressPosition?
    public var manualBasis: String?
    public var observation: SaveObservation?
    public var guide: GuideNote?
    public var guidePlan: GuidePlan?
    public init() {}
    public var hasNewEvidence: Bool { manual != nil && observation != nil && manualBasis != observation?.fingerprint }
    public var activeGuide: GuideNote? { guidePlan?.currentNote ?? guide }
    public var guideBlock: String? {
        guard let guide = activeGuide else { return guidePlan == nil ? "还没有关联攻略。" : "请在路线图中选择当前位置。" }
        guard let manual, !manual.label.isEmpty else { return "先核对当前章节或路线，再显示对应提示。" }
        if let plan = guidePlan, let node = plan.selectedNode, !plan.unmetPrerequisites(for: node).isEmpty {
            return "当前节点的前置条件尚未完成。"
        }
        guard !hasNewEvidence else { return "发现存档变化，请先核对进度；原来的提示已收起。" }
        guard !gameVersion.isEmpty, guide.version == gameVersion else { return "攻略适用版本与当前记录不一致。" }
        guard guide.chapter == manual.chapter, guide.route == manual.route, guide.target == target else {
            return "这条提示对应其他位置或目标，暂不显示。"
        }
        return nil
    }
    public static func validate(_ progress: PlayProgress) throws {
        try progress.guidePlan?.validate()
        guard progress.target.count <= 120, progress.gameVersion.count <= 120,
            (progress.manual?.chapter.count ?? 0) <= 120, (progress.manual?.route.count ?? 0) <= 120
        else { throw VNError.message("章节、路线、目标或版本超过 120 字。") }
        if let observation = progress.observation {
            guard observation.slots.count <= 128, observation.fingerprint.count <= 64, observation.adapter.count <= 120,
                observation.slots.allSatisfy({
                    $0.filename.count <= 1024 && ($0.script?.count ?? 0) <= 128 && $0.fingerprint.count <= 64
                })
            else { throw VNError.message("存档观察记录超出范围。") }
        }
        if let guide = progress.guide {
            guard PublicLink.url(guide.url) != nil,
                guide.url.count <= 2048, !guide.title.isEmpty, guide.title.count <= 200, !guide.version.isEmpty,
                guide.version.count <= 120,
                guide.language.count <= 40, guide.chapter.count <= 120, guide.route.count <= 120,
                guide.target.count <= 120,
                !guide.hint.isEmpty, guide.hint.count <= 2000
            else { throw VNError.message("请填写攻略标题、HTTPS 原文链接、适用版本和提示（最多 2000 字）。") }
        }
    }
}

/// A bounded reader for the observed Steam .sud header. Script labels are evidence,
/// never interpreted as a verified chapter number or the currently loaded slot.
public enum MahoyoSaveHeader {
    public static func parse(_ data: Data) -> (script: String, date: Date?)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 512, Array(bytes[0..<4]) == [0, 0, 1, 0] else { return nil }
        let raw = bytes[284..<412].prefix { $0 != 0 }
        guard let script = String(bytes: raw, encoding: .ascii),
            script.range(of: #"^[A-Za-z0-9_]{1,80}\.(chs|cht|jpn|eng)$"#, options: .regularExpression) != nil
        else { return nil }
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        let parts = DateComponents(
            year: u16(4), month: u16(6), day: u16(10), hour: u16(12), minute: u16(14), second: u16(16))
        let valid =
            (2000...2100).contains(parts.year!) && (1...12).contains(parts.month!) && (1...31).contains(parts.day!)
            && (0...23).contains(parts.hour!) && (0...59).contains(parts.minute!) && (0...59).contains(parts.second!)
        return (script, valid ? Calendar(identifier: .gregorian).date(from: parts) : nil)
    }
}
