import Foundation

public struct SteamReview: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let recommended: Bool
    public let playtimeMinutes: Int
    public let source: String
}
public struct SteamReviews: Codable, Equatable, Sendable {
    public let totalReviews: Int
    public let totalPositive: Int
    public let items: [SteamReview]
    public let fetchedAt: Date
}
extension MetadataService {
    public static func steamReviews(appID: String) async throws -> SteamReviews {
        guard validSteamID(appID) else { throw VNError.message("Steam App ID 无效") }
        let url = URL(
            string:
                "https://store.steampowered.com/appreviews/\(appID)?json=1&filter=recent&language=all&num_per_page=6&purchase_type=all"
        )!
        return try parseReviews(await boundedFetch(url, limit: 1024 * 1024), appID: appID)
    }
    public static func validSteamID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 20 && value.allSatisfy { $0.isASCII && $0.isNumber }
    }
    public static func parseReviews(_ data: Data, appID: String) throws -> SteamReviews {
        guard validSteamID(appID), data.count <= 1024 * 1024,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["success"] as? Int == 1,
            let summary = object["query_summary"] as? [String: Any], let rows = object["reviews"] as? [[String: Any]],
            let total = summary["total_reviews"] as? Int, let positive = summary["total_positive"] as? Int,
            total >= 0, positive >= 0, positive <= total
        else { throw VNError.message("Steam 评论格式不可用，保留已有资料。") }
        var seen = Set<String>()
        let items = rows.prefix(6).compactMap { row -> SteamReview? in
            guard let id = row["recommendationid"] as? String, validSteamID(id), seen.insert(id).inserted,
                let author = row["author"] as? [String: Any], let steamID = author["steamid"] as? String,
                validSteamID(steamID),
                let text = row["review"] as? String, let recommended = row["voted_up"] as? Bool
            else { return nil }
            return SteamReview(
                id: id, text: String(text.prefix(16000)), recommended: recommended,
                playtimeMinutes: max(0, author["playtime_forever"] as? Int ?? 0),
                source: "https://steamcommunity.com/profiles/\(steamID)/recommended/\(appID)/")
        }
        return SteamReviews(totalReviews: total, totalPositive: positive, items: items, fetchedAt: Date())
    }
}
