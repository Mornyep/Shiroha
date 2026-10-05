import Foundation

/// A deliberately finite table of official localized names, keyed by Steam identity.
/// Unknown titles keep their original names; no generated translations.
public enum LocalizedMetadata {
    public struct Title: Sendable {
        public let title: String
        public let source: String
    }
    public static func steamTitle(appID: String) -> Title? {
        switch appID {
        // Verified against the publisher's Steam Simplified Chinese listing, 2026-10-06.
        case "2052410": Title(title: "魔法使之夜", source: "https://store.steampowered.com/app/2052410/?l=schinese")
        case "4012810": Title(title: "命运石之门 RE:BOOT", source: "https://steinsgate.jp/reboot/zh-hans/ · 中文系列名与原副标题")
        case "228980": Title(title: "Steam 公共运行库", source: "Steamworks Common Redistributables · 功能中文说明")
        default: nil
        }
    }
    static func containsHan(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }
}
