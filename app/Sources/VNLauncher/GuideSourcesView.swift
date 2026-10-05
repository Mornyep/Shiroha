import SwiftUI
import VNCore

struct GuideSourcesView: View {
    let game: Game
    @State private var guides = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(guides ? "收起攻略来源" : "浏览攻略来源（可能含后续剧透）") { guides.toggle() }.buttonStyle(.plain).font(.callout)
            if guides {
                if let id = game.metadataSteamID,
                    let url = URL(string: "https://steamcommunity.com/app/" + id + "/guides/?browsefilter=toprated")
                {
                    Link("Steam 社区攻略目录 ↗", destination: url).font(.callout)
                    Text("社区作者 · 多语言 · 请按当前发行版本核对。目录排序不代表已核验每篇攻略。").font(.caption).foregroundStyle(.secondary)
                }
                if game.metadataSteamID == "2052410" {
                    Link(
                        "魔法使之夜 · Steam 社区流程指南 ↗",
                        destination: URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=3139660103")!
                    ).font(.callout)
                    Text("英文 · Steam PC 版 · 包含主线与额外故事说明，可能含完整剧透。作者与更新日期见原文；尚未逐节点核验。").font(.caption).foregroundStyle(
                        .secondary)
                    Link(
                        "TYPE-MOON 官方作品说明 ↗",
                        destination: URL(string: "https://typemoon.com/products/mahoyo/windows/keyword.html")!
                    ).font(.callout)
                    Text("日文 · 原版 Windows 作品说明，不是重制版逐步攻略。").font(.caption).foregroundStyle(.secondary)
                }
                Text("可在上方「关联攻略」保存自己的原文链接、适用版本和当前提示。这里的来源链接不会自动推断进度或展开后续选项。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
