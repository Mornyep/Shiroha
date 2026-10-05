import Darwin
import Foundation

/// Uses the official installed CLI's ChatGPT session. Never reads or copies its credentials.
public struct CodexAdvisor: AIAdvisor {
    public let executable: URL
    public let model: String
    public init(executable: URL, model: String = "") {
        self.executable = executable
        self.model = model
    }
    public static func discover() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex",
        ]
        return paths.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
    public func loginStatus() async throws -> String {
        let result = try await CodexProcess.run(
            executable: executable, arguments: ["-c", "cli_auth_credentials_store=\"auto\"", "login", "status"],
            input: nil, timeout: 8)
        let status = String(decoding: result.output + result.error, as: UTF8.self)
        guard result.code == 0, status.localizedCaseInsensitiveContains("logged in using chatgpt") else {
            throw VNError.message("Codex 尚未使用 ChatGPT 登录。请在终端完成 codex login；不会自动使用 API 密钥。")
        }
        return "已通过 ChatGPT 登录 · 使用 Codex 订阅额度"
    }
    public static func arguments(directory: URL, schema: URL, output: URL, model: String) -> [String] {
        var args = [
            "exec", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--skip-git-repo-check", "--sandbox",
            "read-only", "--color", "never", "--json", "--cd", directory.path, "--output-schema", schema.path,
            "--output-last-message", output.path,
        ]
        // Each override is process-local. Never change the user's Codex configuration.
        let config = [
            "cli_auth_credentials_store=\"auto\"", "approval_policy=\"never\"", "model_provider=\"openai\"",
            "web_search=\"disabled\"", "project_doc_max_bytes=0", "skills.max_context_tokens=1",
            "history.persistence=\"none\"", "mcp_servers={}",
        ]
        for value in config { args += ["-c", value] }
        for feature in [
            "shell_tool", "unified_exec", "apps", "plugins", "hooks", "memories", "multi_agent", "multi_agent_v2",
            "skill_search", "skill_mcp_dependency_install", "shell_snapshot", "browser_use", "browser_use_external",
            "computer_use", "in_app_browser", "image_generation", "view_image", "tool_suggest",
        ] { args += ["--disable", feature] }
        args += ["--enable", "skip_host_skill_discovery"]
        if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { args += ["--model", model] }
        return args + ["-"]
    }
    public func explain(_ input: AdviceInput) async throws -> AdviceResponse {
        _ = try await loginStatus()
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VNAdvisor-" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = directory.appendingPathComponent("response.schema.json")
        let output = directory.appendingPathComponent("response.json")
        try Self.schema.write(to: schema)
        let prompt =
            HTTPAdvisor.instructions
            + "\nUse only the JSON evidence below. Do not use tools, read files, browse, run commands or load skills. Do not infer a game title. This is a single explanation, not a coding task.\n"
            + String(decoding: try input.json(), as: UTF8.self)
        let result = try await CodexProcess.run(
            executable: executable,
            arguments: Self.arguments(directory: directory, schema: schema, output: output, model: model),
            input: Data(prompt.utf8), timeout: 100)
        guard result.code == 0 else {
            throw VNError.message("Codex 请求未完成（退出码 \(result.code)）。请检查订阅额度、网络与 Codex 登录；没有转用 API。")
        }
        guard !Self.containsToolExecution(result.output) else { throw VNError.message("Codex 返回了预期外工具事件，建议已丢弃。") }
        return try HTTPAdvisor.validate(FileSafety.read(output, limit: 256 * 1024), input: input)
    }
    public static func containsToolExecution(_ data: Data) -> Bool {
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            if let item = event["item"] as? [String: Any], let type = item["type"] as? String,
                !["agent_message", "reasoning", "error"].contains(type)
            {
                return true
            }
        }
        return false
    }
    static let schema = Data(
        #"{"type":"object","additionalProperties":false,"properties":{"advice":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"conclusion":{"type":"string"},"evidenceIDs":{"type":"array","items":{"type":"string"}},"confidence":{"type":"string","enum":["low","medium","high"]},"sources":{"type":"array","items":{"type":"string"}},"scope":{"type":"string"},"action":{"type":"string"},"verification":{"type":"string"}},"required":["conclusion","evidenceIDs","confidence","sources","scope","action","verification"]}}},"required":["advice"]}"#
            .utf8)
}

struct CodexProcessResult: Sendable {
    let code: Int32
    let output: Data
    let error: Data
}
enum CodexProcess {
    static func run(executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) async throws
        -> CodexProcessResult
    {
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw VNError.message("未找到可执行的 Codex CLI")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VNCodexIO-" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let out = directory.appendingPathComponent("stdout")
        let err = directory.appendingPathComponent("stderr")
        let stdin = directory.appendingPathComponent("stdin")
        try Data().write(to: out)
        try Data().write(to: err)
        try (input ?? Data()).write(to: stdin)
        let outHandle = try FileHandle(forWritingTo: out)
        let errHandle = try FileHandle(forWritingTo: err)
        let inHandle = try FileHandle(forReadingFrom: stdin)
        defer {
            try? outHandle.close()
            try? errHandle.close()
            try? inHandle.close()
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // Exclude API keys, provider overrides and inherited app-server session variables.
        let env = ProcessInfo.processInfo.environment
        process.environment = Dictionary(
            uniqueKeysWithValues: ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG"].compactMap { key in
                env[key].map { (key, $0) }
            })
        process.standardInput = inHandle
        process.standardOutput = outHandle
        process.standardError = errHandle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw VNError.message("Codex 请求超时，已停止本次进程。") }
                for file in [out, err] {
                    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size < 2 * 1024 * 1024 else { throw VNError.message("Codex 输出超过上限") }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
        } catch {
            // Only this directly owned process; never terminate Codex desktop, Steam, or Wine.
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw error
        }
        return CodexProcessResult(
            code: process.terminationStatus, output: try FileSafety.read(out, limit: 2 * 1024 * 1024),
            error: try FileSafety.read(err, limit: 2 * 1024 * 1024))
    }
}
