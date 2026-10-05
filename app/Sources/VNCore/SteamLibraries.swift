import Foundation

/// Only declared Steam roots are inspected; a Wine drive link is resolved once, never enumerated.
public enum SteamLibraries {
    public static func paths(in text: String) throws -> [String] {
        guard text.utf8.count <= 1024 * 1024 else { throw VNError.message("Steam 库配置过大") }
        let chars = Array(text)
        var index = 0
        var tokens: [String] = []
        while index < chars.count {
            let c = chars[index]
            if c.isWhitespace {
                index += 1
                continue
            }
            if c == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                while index < chars.count && chars[index] != "\n" { index += 1 }
                continue
            }
            if c == "{" || c == "}" {
                tokens.append(String(c))
                index += 1
                continue
            }
            guard c == "\"" else { throw VNError.message("无效 Steam 库配置") }
            index += 1
            var value = ""
            var closed = false
            while index < chars.count {
                let next = chars[index]
                index += 1
                if next == "\"" {
                    closed = true
                    break
                }
                if next == "\\", index < chars.count, chars[index] == "\\" || chars[index] == "\"" {
                    value.append(chars[index])
                    index += 1
                } else {
                    value.append(next)
                }
            }
            guard closed, tokens.count < 10000 else { throw VNError.message("无效或过大 Steam 库配置") }
            tokens.append(value)
        }
        var cursor = 0
        var result: [String] = []
        func object(_ depth: Int, library: Bool, entry: Bool) throws {
            guard depth <= 8 else { throw VNError.message("Steam 库配置层级过深") }
            while cursor < tokens.count && tokens[cursor] != "}" {
                let key = tokens[cursor]
                cursor += 1
                guard key != "{", cursor < tokens.count else { throw VNError.message("无效 Steam 库配置") }
                let value = tokens[cursor]
                cursor += 1
                if value == "{" {
                    try object(
                        depth + 1, library: key.lowercased() == "libraryfolders",
                        entry: library && key.allSatisfy(\.isNumber))
                    guard cursor < tokens.count, tokens[cursor] == "}" else { throw VNError.message("无效 Steam 库配置") }
                    cursor += 1
                } else {
                    guard value != "}" else { throw VNError.message("无效 Steam 库配置") }
                    if (entry && key.lowercased() == "path") || (library && !key.isEmpty && key.allSatisfy(\.isNumber))
                    {
                        result.append(value)
                    }
                }
            }
        }
        try object(0, library: false, entry: false)
        guard cursor == tokens.count else { throw VNError.message("无效 Steam 库配置") }
        return Array(Set(result)).sorted()
    }
    public static func resolve(_ path: String, bottle: URL) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        guard !components.contains(".."), !components.contains("."), !normalized.contains("\0") else { return nil }
        let base: URL
        let tail: [String]
        if normalized.hasPrefix("/") {
            base = URL(fileURLWithPath: normalized)
            tail = []
        } else {
            guard components.count > 0, components[0].count == 2, components[0].last == ":",
                let drive = components[0].first, drive.isASCII, drive.isLetter
            else { return nil }
            if drive.lowercased() == "c" {
                base = bottle.appendingPathComponent("drive_c")
            } else {
                let link = bottle.appendingPathComponent("dosdevices/\(drive.lowercased()):")
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
                    return nil
                }
                base =
                    target.hasPrefix("/")
                    ? URL(fileURLWithPath: target) : link.deletingLastPathComponent().appendingPathComponent(target)
            }
            tail = Array(components.dropFirst())
        }
        // A declared drive root can be a link. No subsequent component may be a link.
        var resolved = base.standardizedFileURL.resolvingSymlinksInPath()
        for component in tail {
            resolved.appendPathComponent(component)
            guard (try? resolved.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                return nil
            }
        }
        return resolved
    }
    static func safeChild(_ url: URL, root: URL) -> Bool {
        guard FileSafety.contained(url, in: root) else { return false }
        let prefix = root.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(prefix) else { return false }
        var current = root
        for part in url.standardizedFileURL.path.dropFirst(prefix.count).split(separator: "/") {
            current.appendPathComponent(String(part))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return false }
        }
        return true
    }
    public static func roots(steam: URL, bottle: URL) -> [URL] {
        var roots = [steam.standardizedFileURL.resolvingSymlinksInPath()]
        let vdf = steam.appendingPathComponent("steamapps/libraryfolders.vdf")
        if safeChild(vdf, root: steam), let data = try? FileSafety.read(vdf, limit: 1024 * 1024),
            let text = String(data: data, encoding: .utf8), let paths = try? paths(in: text)
        {
            roots += paths.compactMap { resolve($0, bottle: bottle) }
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }.prefix(64).map { $0 }
    }
}
