import Foundation

public enum GameConfiguration {
    public static func sameAnalysisInputs(_ lhs: Game, _ rhs: Game) -> Bool {
        lhs.id == rhs.id && lhs.executable == rhs.executable && lhs.workingDirectory == rhs.workingDirectory
            && lhs.kind == rhs.kind && lhs.steamAppID == rhs.steamAppID && lhs.bottleID == rhs.bottleID
    }

    /// Apply only fields owned by the configuration form. Save observations and other panels may change while it is open.
    public static func applying(_ draft: Game, original: Game, to current: Game, titleEdited: Bool, coverEdited: Bool)
        throws -> Game
    {
        guard draft.id == original.id, original.id == current.id else { throw VNError.message("作品身份已改变，请重新打开配置。") }
        var result = current
        if titleEdited { result = try MetadataEditing.manual([.title: draft.title], in: result) }
        if coverEdited {
            result.coverPath = draft.coverPath
            if result.metadata == nil { result.metadata = GameMetadata() }
            result.metadata?.coverSource = "手动选择"
        }
        if draft.alias != original.alias { result.alias = draft.alias }
        if draft.state != original.state { result.state = draft.state }
        if draft.favorite != original.favorite { result.favorite = draft.favorite }
        if draft.kind != original.kind { result.kind = draft.kind }
        if draft.steamAppID != original.steamAppID { result.steamAppID = draft.steamAppID }
        if draft.bottleID != original.bottleID { result.bottleID = draft.bottleID }
        if draft.executable != original.executable { result.executable = draft.executable }
        if draft.workingDirectory != original.workingDirectory { result.workingDirectory = draft.workingDirectory }
        if draft.arguments != original.arguments { result.arguments = draft.arguments }
        if draft.saveDirectory != original.saveDirectory { result.saveDirectory = draft.saveDirectory }
        if draft.runtimeChecks != original.runtimeChecks {
            result.runtimeChecks = draft.runtimeChecks
            result.runtimeChecksUpdatedAt = Date()
        }
        return result
    }
}
