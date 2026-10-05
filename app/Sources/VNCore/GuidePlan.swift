import Foundation

public struct GuideNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var chapter: String
    public var route: String
    public var hint: String
    public var saveReminder: String
    public var prerequisites: [UUID]
    public var next: [UUID]

    public init(
        id: UUID = UUID(), title: String = "", chapter: String = "", route: String = "", hint: String = "",
        saveReminder: String = "", prerequisites: [UUID] = [], next: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.chapter = chapter
        self.route = route
        self.hint = hint
        self.saveReminder = saveReminder
        self.prerequisites = prerequisites
        self.next = next
    }
}

/// A guide is a user-curated graph. Its position is never inferred from a file timestamp.
public struct GuidePlan: Codable, Equatable, Sendable {
    public var title = ""
    public var sourceURL = ""
    public var version = ""
    public var language = "中文"
    public var target = ""
    public var nodes: [GuideNode] = []
    public var selectedNodeID: UUID?
    public var completedNodeIDs: [UUID] = []
    public var checkedAt = Date()

    public init() {}

    public var selectedNode: GuideNode? { nodes.first { $0.id == selectedNodeID } }

    public var currentNote: GuideNote? {
        guard let node = selectedNode else { return nil }
        var note = GuideNote()
        note.title = title
        note.url = sourceURL
        note.version = version
        note.language = language
        note.target = target
        note.chapter = node.chapter
        note.route = node.route
        note.hint = node.hint + (node.saveReminder.isEmpty ? "" : "\n\n留档提醒：" + node.saveReminder)
        note.checkedAt = checkedAt
        return note
    }

    public func unmetPrerequisites(for node: GuideNode) -> [UUID] {
        node.prerequisites.filter { !completedNodeIDs.contains($0) }
    }

    public mutating func select(_ id: UUID) throws {
        guard let node = nodes.first(where: { $0.id == id }), unmetPrerequisites(for: node).isEmpty else {
            throw VNError.message("先核对并标记前置节点，再设置当前位置。")
        }
        selectedNodeID = id
    }

    public mutating func removeNode(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        for index in nodes.indices {
            nodes[index].next.removeAll { $0 == id }
            nodes[index].prerequisites.removeAll { $0 == id }
        }
        completedNodeIDs.removeAll { $0 == id }
        if selectedNodeID == id { selectedNodeID = nil }
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
            PublicLink.url(sourceURL) != nil, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            version.count <= 120, language.count <= 40, target.count <= 120,
            nodes.count <= 200
        else {
            throw VNError.message("请填写攻略名称、HTTPS 来源和适用版本；最多 200 个节点。")
        }
        let ids = Set(nodes.map(\.id))
        guard ids.count == nodes.count, Set(completedNodeIDs).count == completedNodeIDs.count,
            Set(completedNodeIDs).isSubset(of: ids), selectedNodeID.map(ids.contains) ?? true
        else {
            throw VNError.message("攻略包含重复或失效的节点关联。")
        }
        for node in nodes {
            guard !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, node.title.count <= 120,
                !node.chapter.isEmpty || !node.route.isEmpty, node.chapter.count <= 120, node.route.count <= 120,
                !node.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, node.hint.count <= 1600,
                node.saveReminder.count <= 300,
                Set(node.prerequisites).count == node.prerequisites.count, Set(node.next).count == node.next.count,
                Set(node.prerequisites + node.next).isSubset(of: ids), !node.prerequisites.contains(node.id),
                !node.next.contains(node.id)
            else {
                throw VNError.message("节点需有名称、章节或路线及提示；关联必须指向其他已存在节点。")
            }
        }
        // A prerequisite loop makes every affected node unreachable. Next-step links may loop for replay.
        var visiting = Set<UUID>()
        var visited = Set<UUID>()
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        func visit(_ id: UUID) throws {
            guard !visiting.contains(id) else { throw VNError.message("前置条件形成循环，请解除其中一个关联。") }
            guard !visited.contains(id) else { return }
            visiting.insert(id)
            for dependency in byID[id]?.prerequisites ?? [] { try visit(dependency) }
            visiting.remove(id)
            visited.insert(id)
        }
        for id in ids { try visit(id) }
    }
}

public enum PublicLink {
    public static func url(_ value: String) -> URL? {
        guard value.count <= 2048, let url = URL(string: value), url.scheme == "https",
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
            url.port == nil || url.port == 443
        else { return nil }
        return url
    }
}
