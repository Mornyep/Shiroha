import SwiftUI
import VNCore

struct SteamReviewsView: View {
    @Bindable var store: LibraryStore
    let game: Game
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Steam 玩家评论").font(.headline)
                Spacer()
                if let reviews = game.metadata?.reviews {
                    Text("\(reviews.totalReviews) 条").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let reviews = game.metadata?.reviews {
                Text("近期公开评论样本，可能含剧透。").font(.callout).foregroundStyle(.secondary)
                if reviews.items.isEmpty {
                    Text("暂无公开评论。").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button(revealed ? "收起评论" : "展开评论") { revealed.toggle() }.buttonStyle(QuietButton())
                    if revealed { ForEach(reviews.items) { ReviewCard(review: $0) } }
                }
            } else {
                Text("还没有载入评论。").font(.callout).foregroundStyle(.secondary)
            }
            SteamRefreshButton(store: store, game: game)
        }.onChange(of: game.id) { _, _ in revealed = false }
    }
}

private struct ReviewCard: View {
    let review: SteamReview
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    review.recommended ? "推荐" : "不推荐",
                    systemImage: review.recommended ? "hand.thumbsup" : "hand.thumbsdown")
                Spacer()
                Text(String(format: "%.1f 小时", Double(review.playtimeMinutes) / 60)).foregroundStyle(.secondary)
            }.font(.caption)
            Text(review.text).font(.callout).lineSpacing(5).lineLimit(expanded ? nil : 4).textSelection(.enabled)
            HStack {
                if review.text.count > 200 { Button(expanded ? "收起" : "阅读全文") { expanded.toggle() } }
                Spacer()
                if let url = PublicLink.url(review.source) { Link("Steam 原文 ↗", destination: url) }
            }.font(.caption).buttonStyle(.plain)
        }.padding(.vertical, 12)
        Divider().opacity(0.4)
    }
}
