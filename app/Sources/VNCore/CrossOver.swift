import Foundation

public enum CrossOver {
    public static var bottlesRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/CrossOver/Bottles")
    }
    public static func discoverRunner(at path: String? = nil) -> Runner? {
        let paths =
            path.map { [$0] } ?? [
                "/Applications/CrossOver.app",
                FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/CrossOver.app",
            ]
        for p in paths {
            guard FileManager.default.isExecutableFile(atPath: p + "/Contents/SharedSupport/CrossOver/bin/wine"),
                let bundle = Bundle(path: p),
                let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            else { continue }
            return Runner(appPath: p, version: version)
        }
        return nil
    }
    public static func configuration(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\""), let range = line.range(of: "=") else { continue }
            result[String(line[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))] =
                String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        return result
    }
    public static func discoverBottles(root: URL = bottlesRoot) -> [Bottle] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]))
            ?? []
        return urls.compactMap { url in
            guard FileSafety.contained(url, in: root),
                (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                let data = try? FileSafety.read(url.appendingPathComponent("cxbottle.conf"), limit: 1024 * 1024),
                let conf = String(data: data, encoding: .utf8)
            else { return nil }
            return Bottle(name: url.lastPathComponent, path: url.path, configuration: configuration(conf))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func command(game: Game, bottle: Bottle, runner: Runner) throws -> LaunchCommand {
        guard game.bottleID == bottle.id, !bottle.name.isEmpty, !bottle.name.hasPrefix("-"), !bottle.name.contains("/")
        else { throw VNError.message("请选择有效容器") }
        guard FileManager.default.isExecutableFile(atPath: runner.executable) else {
            throw VNError.message("CrossOver 入口不可用，请重新选择")
        }
        guard FileManager.default.fileExists(atPath: bottle.path + "/cxbottle.conf") else {
            throw VNError.message("容器不可用")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: game.workingDirectory, isDirectory: &isDir), isDir.boolValue else {
            throw VNError.message("工作目录离线或已移动，请重新定位")
        }
        guard game.executable.hasPrefix("/"), FileManager.default.fileExists(atPath: game.executable),
            URL(fileURLWithPath: game.executable).pathExtension.lowercased() == "exe"
        else { throw VNError.message("启动 EXE 不存在，请重新定位") }
        // --no-update avoids implicit bottle upgrades. Native paths are handled by the CrossOver wrapper.
        var args = ["--bottle", bottle.name, "--no-update", "--workdir", game.workingDirectory, game.executable]
        if game.kind == .steam {
            guard !game.steamAppID.isEmpty, game.steamAppID.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw VNError.message("Steam App ID 必须是数字")
            }
            args += ["-applaunch", game.steamAppID]
        }
        args += game.arguments
        return LaunchCommand(executable: runner.executable, arguments: args, directory: game.workingDirectory)
    }
    public static func steamGames(in bottle: Bottle) throws -> [Game] {
        let root = URL(fileURLWithPath: bottle.path)
        let candidates = ["drive_c/Program Files (x86)/Steam", "drive_c/Program Files/Steam"]
        var found: [Game] = []
        for candidate in candidates {
            let steam = root.appendingPathComponent(candidate)
            guard SteamLibraries.safeChild(steam.appendingPathComponent("steam.exe"), root: root),
                FileManager.default.fileExists(atPath: steam.appendingPathComponent("steam.exe").path)
            else { continue }
            for library in SteamLibraries.roots(steam: steam, bottle: root) {
                let apps = library.appendingPathComponent("steamapps")
                guard SteamLibraries.safeChild(apps, root: library) else { continue }
                let files =
                    (try? FileManager.default.contentsOfDirectory(
                        at: apps, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(2000)
                where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                    guard SteamLibraries.safeChild(file, root: library),
                        let data = try? FileSafety.read(file, limit: 256 * 1024),
                        let text = String(data: data, encoding: .utf8)
                    else { continue }
                    func value(_ key: String) -> String? {
                        let re = try? NSRegularExpression(pattern: "\"" + key + "\"\\s*\"([^\"]*)\"")
                        guard let match = re?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                            let range = Range(match.range(at: 1), in: text)
                        else { return nil }
                        return String(text[range])
                    }
                    guard let id = value("appid"), !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }),
                        file.lastPathComponent == "appmanifest_\(id).acf", let title = value("name"),
                        let dir = value("installdir"), !dir.isEmpty, !dir.contains("/"), !dir.contains("\\"),
                        dir != ".", dir != ".."
                    else { continue }
                    let gameDir = apps.appendingPathComponent("common").appendingPathComponent(dir)
                    guard SteamLibraries.safeChild(gameDir, root: library),
                        (try? gameDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    else { continue }
                    var game = Game(
                        title: title, executable: steam.appendingPathComponent("steam.exe").path,
                        workingDirectory: gameDir.path)
                    game.kind = .steam
                    game.steamAppID = id
                    game.bottleID = bottle.id
                    guard !game.isUtility, !found.contains(where: { $0.steamAppID == id }) else { continue }
                    game.source = "Steam appmanifest；" + file.path
                    found.append(game)
                }
            }
        }
        return found
    }
}
