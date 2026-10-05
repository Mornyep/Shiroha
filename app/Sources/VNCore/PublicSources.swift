import Foundation

public enum PublicSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case bangumi = "Bangumi"
    case vndb = "VNDB"
    public var id: String { rawValue }
    public func validID(_ value: String) -> Bool {
        let digits = self == .vndb ? String(value.dropFirst()) : value
        return (self != .vndb || value.first == "v") && !digits.isEmpty && digits.count <= 12
            && digits.allSatisfy { $0.isASCII && $0.isNumber } && (UInt64(digits) ?? 0) > 0
    }
}
public struct PublicProfile: Codable, Equatable, Identifiable, Sendable {
    public var source: PublicSource
    public var sourceID: String
    public var title: String
    public var originalTitle: String
    public var summary: String
    public var released: String
    public var score: Double?
    public var votes: Int
    public var rank: Int?
    public var matchedSteamID: String? = nil
    public var fetchedAt: Date
    public var id: String { source.rawValue + ":" + sourceID }
    public var url: URL? {
        guard source.validID(sourceID) else { return nil }
        return URL(string: source == .bangumi ? "https://bgm.tv/subject/" + sourceID : "https://vndb.org/" + sourceID)
    }
    public var scoreLabel: String { score.map { String(format: "%.2f / 10", $0) } ?? "暂无评分" }
    public var method: String { source == .vndb ? "贝叶斯评分（原站 100 分制换算）" : "站内评分" }
}

/// Public, bounded reads only. No credentials, cookies, save paths or game files enter requests.
public actor PublicSourceClient {
    public static let shared = PublicSourceClient()
    private var nextRequest: [PublicSource: Date] = [:]
    private var cache: [String: (Date, [PublicProfile])] = [:]
    public func search(_ source: PublicSource, query: String) async throws -> [PublicProfile] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 150 else { throw VNError.message("请输入 1–150 字的作品名。") }
        return try await request(source, query: query, id: nil)
    }
    public func matchSteam(appID: String) async throws -> [PublicProfile] {
        guard MetadataService.validSteamID(appID), (UInt64(appID) ?? 0) > 0 else {
            throw VNError.message("Steam App ID 无效。")
        }
        return try await request(.vndb, query: "", id: nil, steamID: appID)
    }
    public func refresh(_ profile: PublicProfile) async throws -> PublicProfile {
        guard profile.source.validID(profile.sourceID) else { throw VNError.message("来源 ID 无效。") }
        let results = try await request(profile.source, query: "", id: profile.sourceID)
        guard var result = results.first(where: { $0.sourceID == profile.sourceID }) else {
            throw VNError.message("原条目暂不可用，已保留上次资料。")
        }
        result.matchedSteamID = profile.matchedSteamID
        return result
    }
    private func request(_ source: PublicSource, query: String, id: String?, steamID: String? = nil) async throws
        -> [PublicProfile]
    {
        let key = source.rawValue + (steamID.map { ":steam:" + $0 } ?? (id.map { ":id:" + $0 } ?? ":q:" + query))
        if let entry = cache[key], Date().timeIntervalSince(entry.0) < 300 { return entry.1 }
        guard Date() >= (nextRequest[source] ?? .distantPast) else { throw VNError.message("请求较频繁，请稍后再试；原资料仍保留。") }
        nextRequest[source] = Date().addingTimeInterval(3)
        let url: URL
        var body: [String: Any]?
        if source == .bangumi {
            url = URL(
                string: id.map { "https://api.bgm.tv/v0/subjects/" + $0 }
                    ?? "https://api.bgm.tv/v0/search/subjects?limit=8")!
            if id == nil { body = ["keyword": query, "sort": "match", "filter": ["type": [4]]] }
        } else {
            url = URL(string: "https://api.vndb.org/kana/vn")!
            let filter: [Any]
            if let steamID {
                filter = ["release", "=", ["extlink", "=", ["steam", steamID]]]
            } else {
                filter = id.map { ["id", "=", $0] } ?? ["search", "=", query]
            }
            body = ["filters": filter, "fields": "title,alttitle,description,released,rating,votecount", "results": 8]
        }
        var request = URLRequest(url: url)
        request.setValue("VNLauncher/0.14 (macOS; public metadata reader)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: SourceRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw VNError.message("来源响应无效。") }
        if response.statusCode == 429 {
            nextRequest[source] = Date().addingTimeInterval(60)
            throw VNError.message("来源正在限流，请一分钟后重试。")
        }
        guard (200..<300).contains(response.statusCode), response.expectedContentLength <= 2_097_152 else {
            throw VNError.message("\(source.rawValue) 请求失败（HTTP \(response.statusCode)），已保留旧资料。")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_097_152 else { throw VNError.message("来源响应超过大小上限。") }
            data.append(byte)
        }
        var result = try Self.parse(data, source: source, single: source == .bangumi && id != nil)
        if let steamID { for index in result.indices { result[index].matchedSteamID = steamID } }
        if cache.count >= 40 { cache.removeAll() }
        cache[key] = (Date(), result)
        return result
    }
    public static func parse(_ data: Data, source: PublicSource, single: Bool = false, date: Date = Date()) throws
        -> [PublicProfile]
    {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = single ? [object] : object[source == .bangumi ? "data" : "results"] as? [[String: Any]]
        else { throw VNError.message("来源格式无法识别。") }
        return rows.prefix(8).compactMap { row in
            let id = source == .bangumi ? (row["id"] as? Int).map(String.init) : row["id"] as? String
            guard let id, source.validID(id), source != .bangumi || row["type"] as? Int == 4 else { return nil }
            func string(_ key: String, _ limit: Int = 300) -> String {
                String((row[key] as? String ?? "").prefix(limit))
            }
            let original = source == .bangumi ? string("name") : string("alttitle")
            let localized = source == .bangumi ? string("name_cn") : string("title")
            let title = localized.isEmpty ? original : localized
            guard !title.isEmpty else { return nil }
            let rating = row["rating"] as? [String: Any] ?? [:]
            let raw = source == .bangumi ? rating["score"] as? Double : (row["rating"] as? Double).map { $0 / 10 }
            let votes = max(0, source == .bangumi ? rating["total"] as? Int ?? 0 : row["votecount"] as? Int ?? 0)
            let score = raw.flatMap { $0.isFinite && $0 > 0 && $0 <= 10 && votes > 0 ? $0 : nil }
            return PublicProfile(
                source: source, sourceID: id, title: title, originalTitle: original,
                summary: string(source == .bangumi ? "summary" : "description", 8000),
                released: string(source == .bangumi ? "date" : "released", 40), score: score, votes: votes,
                rank: (rating["rank"] as? Int).flatMap { $0 > 0 ? $0 : nil }, fetchedAt: date)
        }
    }
}
private final class SourceRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? { nil }
}
