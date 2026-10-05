import AppKit
import Darwin
import SwiftUI
import VNCore

struct ProgressLink: Codable, Equatable {
    var directory: String
    var paused = false
}
@MainActor final class SaveWatch {
    private var sources: [any DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    func stop() {
        pending?.cancel()
        pending = nil
        for source in sources { source.cancel() }
        sources = []
    }
    @discardableResult func arm(paths: [String], changed: @escaping @MainActor () -> Void) -> Bool {
        var complete = paths.count <= 129
        for source in sources { source.cancel() }
        sources = []
        for path in paths.prefix(129) {
            let fd = open(path, O_EVTONLY | O_NOFOLLOW)
            guard fd >= 0 else {
                complete = false
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .delete, .rename, .attrib, .extend], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in
                    self?.pending?.cancel()
                    self?.pending = Task { @MainActor in
                        do {
                            try await Task.sleep(for: .milliseconds(800))
                            try Task.checkCancellation()
                            changed()
                        } catch {}
                    }
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
        return complete
    }
    deinit {
        pending?.cancel()
        for source in sources { source.cancel() }
    }
}
extension LibraryStore {
    func saveProgress(_ progress: PlayProgress, gameID: UUID) throws {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { throw VNError.message("作品已移除。") }
        try PlayProgress.validate(progress)
        var proposed = games
        proposed[index].progress = progress
        try commitPersonalLibrary(games: proposed, collections: collections)
    }
    func restoreProgressLinks() {
        let file = root.appendingPathComponent("progress-links.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                progressLinks = try JSONDecoder().decode([UUID: ProgressLink].self, from: Data(contentsOf: file))
            } catch {
                progressLinkError = "观察关联记录无法读取，已保留原文件。"
                return
            }
        }
        let active = progressLinks.keys.filter { id in
            progressLinks[id]?.paused == false && games.contains(where: { $0.id == id })
        }.sorted { $0.uuidString < $1.uuidString }
        for (index, id) in active.enumerated() {
            if index < 12 { refreshProgress(id) } else { progressMessages[id] = "最多同时观察 12 部作品；请先暂停其他作品。" }
        }
    }
    func setProgressLink(_ link: ProgressLink?, id: UUID) throws {
        guard writable, progressLinkError == nil else { throw VNError.message(progressLinkError ?? "游戏库不可写。") }
        var proposed = progressLinks
        proposed[id] = link
        if link?.paused == false {
            guard
                proposed.filter({ entry in !entry.value.paused && games.contains(where: { $0.id == entry.key }) }).count
                    <= 12
            else { throw VNError.message("最多同时观察 12 部作品；请先暂停其他作品。") }
        }
        try Storage.save(proposed, to: root.appendingPathComponent("progress-links.json"))
        progressTasks[id]?.cancel()
        progressTasks[id] = nil
        progressWatches[id]?.stop()
        progressWatches[id] = nil
        progressLinks = proposed
        progressMessages[id] = nil
        if link?.paused == false { refreshProgress(id) }
    }
    func chooseProgressDirectory(_ game: Game) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择这部作品的存档文件夹。只读观察，不会修改或上传存档。"
        if game.metadataSteamID == "2052410" {
            let steam = URL(fileURLWithPath: game.executable).deletingLastPathComponent()
            let candidate = steam.appendingPathComponent("steamapps/common/WITCH ON THE HOLY NIGHT/UserData")
            if FileManager.default.fileExists(atPath: candidate.path) { panel.directoryURL = candidate }
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                guard let resolved = realpath(url.path, nil) else { throw VNError.message("无法解析所选目录。") }
                defer { free(resolved) }
                try setProgressLink(ProgressLink(directory: String(cString: resolved)), id: game.id)
            } catch { progressMessages[game.id] = error.localizedDescription }
        }
    }
    func refreshProgress(_ id: UUID) {
        guard writable, let link = progressLinks[id], !link.paused, let game = games.first(where: { $0.id == id })
        else { return }
        guard progressWatches[id] != nil || progressWatches.count < 12 else {
            progressMessages[id] = "最多同时观察 12 部作品；请先暂停其他作品。"
            return
        }
        progressTasks[id]?.cancel()
        let directory = URL(fileURLWithPath: link.directory)
        let mahoyo = game.metadataSteamID == "2052410"
        // Watch the chosen root even if a scan fails (e.g. a file is still being written).
        if progressWatches[id] == nil {
            let watch = SaveWatch()
            progressWatches[id] = watch
            watch.arm(paths: [link.directory]) { [weak self] in self?.refreshProgress(id) }
        }
        progressMessages[id] = "等待文件稳定后读取…"
        progressTasks[id] = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                try await SaveSnapshotReader.stable(directory: directory, mahoyo: mahoyo)
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard let self, self.progressLinks[id] == link, let current = self.games.first(where: { $0.id == id }),
                    current.metadataSteamID == game.metadataSteamID
                else { return }
                var progress = current.progress ?? PlayProgress()
                if progress.observation?.fingerprint != result.observation.fingerprint {
                    progress.observation = result.observation
                    try self.saveProgress(progress, gameID: id)
                }
                self.progressMessages[id] =
                    result.observation.slots.isEmpty
                    ? "目录内没有可读取的存档候选。" : "已检查 · " + Date().formatted(date: .omitted, time: .shortened)
                let complete =
                    self.progressWatches[id]?.arm(paths: result.watchedPaths) { [weak self] in self?.refreshProgress(id)
                    } ?? false
                if !complete { self.progressMessages[id] = "部分文件无法建立观察；请手动刷新或重新关联。" }
            } catch is CancellationError {} catch { self?.progressMessages[id] = error.localizedDescription }
        }
    }
    func stopProgress(_ id: UUID) {
        progressTasks[id]?.cancel()
        progressTasks[id] = nil
        progressWatches[id]?.stop()
        progressWatches[id] = nil
    }
}
