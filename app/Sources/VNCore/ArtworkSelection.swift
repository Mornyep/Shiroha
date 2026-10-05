import Foundation

public enum ArtworkRole: String, CaseIterable, Sendable {
    case wallpaper = "壁纸"
    case disc = "盘面"
}
public struct ArtworkSelection: Codable, Equatable, Sendable {
    public var path: String
    public var source: String
    public var reason: String
    public var userLocked: Bool
    public var horizontal: Double
    public var vertical: Double
    public var zoom: Double
    public init(
        path: String, source: String, reason: String, userLocked: Bool = false, horizontal: Double = 0.5,
        vertical: Double = 0.5, zoom: Double = 1
    ) {
        self.path = path
        self.source = source
        self.reason = reason
        self.userLocked = userLocked
        self.horizontal = Self.unit(horizontal)
        self.vertical = Self.unit(vertical)
        self.zoom = zoom.isFinite ? min(2.5, max(1, zoom)) : 1
    }
    public static func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0.5 }
    public var safeZoom: Double { zoom.isFinite ? min(2.5, max(1, zoom)) : 1 }
}
extension GameMetadata {
    public var chosenWallpaper: ArtworkSelection? {
        if let wallpaperArtwork { return wallpaperArtwork }
        if backgroundSource == "手动选择", let backgroundPath {
            return ArtworkSelection(path: backgroundPath, source: "手动选择", reason: "此前手动选择的壁纸", userLocked: true)
        }
        return nil
    }
}
public struct CuratedArtwork: Sendable {
    public let wallpaperURL: String
    public let discURL: String
    public let horizontal: Double
    public let wallpaperReason: String
    public let discReason: String
}
/// Human-reviewed per-role choices, never a ranking inferred from screenshot order.
public enum ArtworkCatalog {
    public static let revision = 6
    public static let entries: [String: CuratedArtwork] = [
        "2779910": CuratedArtwork(
            wallpaperURL: "https://www.dramaticcreate.com/manten/img/man_ss03_ss.jpg",
            discURL: "https://www.dramaticcreate.com/manten/img/man_03.jpg", horizontal: 0.5,
            wallpaperReason: "官网无对白场景，完整保留两人和庭院。", discReason: "官网插图，人物面部位于盘面上方，中心孔落在衣襟。"),
        "2052410": CuratedArtwork(
            wallpaperURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2052410/ss_9fe33923585b286c80bea857acf8ac2686edacce.1920x1080.jpg?t=1753952335",
            discURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2052410/ss_9fe33923585b286c80bea857acf8ac2686edacce.1920x1080.jpg?t=1753952335",
            horizontal: 0.42, wallpaperReason: "钟楼与城市全景，无对白或操作界面。", discReason: "钟楼插图，人物面部位于左上方，避开中心孔。"),
        "2161700": CuratedArtwork(
            wallpaperURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2161700/ss_b60f1f21f4794f0ba90bbc55c41aab4637b4103a.1920x1080.jpg?t=1764776430",
            discURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2161700/ss_b5b93089686b45d6abee593d025c91389c7dc20e.1920x1080.jpg?t=1764776430",
            horizontal: 0.72, wallpaperReason: "夕阳车厢动画画面，无战斗 HUD。", discReason: "召唤画面无 HUD，向左留出人物，中心孔避开面部。"),
        "2593370": CuratedArtwork(
            wallpaperURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2593370/ss_83ab9db443e75c7b2f86f097f70b761a51a7f946.1920x1080.jpg?t=1785987440",
            discURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2593370/ss_83ab9db443e75c7b2f86f097f70b761a51a7f946.1920x1080.jpg?t=1785987440",
            horizontal: 0.3, wallpaperReason: "烟火夜景，无对白界面，保留完整街道。", discReason: "人物置于右上方，中心孔避开面部。"),
        "2185770": CuratedArtwork(
            wallpaperURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2185770/ss_ea5a81f353d0e397e6915973443a3ffe7ac12664.1920x1080.jpg?t=1670471787",
            discURL:
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2185770/ss_6fbfe401859b34a16132231a5771eebae714a36b.1920x1080.jpg?t=1670471787",
            horizontal: 0.6, wallpaperReason: "完整夏日群像，保留画面两侧人物。", discReason: "夜空插图保留完整头部，面部位于上方，中心孔在衣服处。"),
        "4012810": CuratedArtwork(
            wallpaperURL: "https://steinsgate.jp/reboot/zh-hans/common/img/gallery/bg4.jpg?20260820",
            discURL: "https://steinsgate.jp/reboot/zh-hans/common/img/gallery/ev4.jpg?20260820", horizontal: 0.73,
            wallpaperReason: "官网屋顶场景，无对白；保留原作画面特效与署名。", discReason: "官网红莉栖插图，面部位于上方，中心孔避开脸部。"),
    ]
    public static func fetch(appID: String, role: ArtworkRole, directory: URL) async throws -> ArtworkSelection? {
        guard let item = entries[appID] else { return nil }
        let source = role == .wallpaper ? item.wallpaperURL : item.discURL
        guard let url = URL(string: source) else { return nil }
        let path = try await MetadataService.cacheArtwork(
            url, appID: appID, role: role == .wallpaper ? "wallpaper-v6" : "disc-v6", directory: directory)
        guard let size = ArtworkQuality.size(path), size.width >= 600, size.height >= 450,
            role != .wallpaper || size.width >= size.height
        else { throw VNError.message("推荐素材的尺寸不符合要求") }
        return ArtworkSelection(
            path: path, source: source, reason: role == .wallpaper ? item.wallpaperReason : item.discReason,
            horizontal: role == .disc ? item.horizontal : 0.5)
    }
}
