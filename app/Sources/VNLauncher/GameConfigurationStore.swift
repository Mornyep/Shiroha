import VNCore

extension LibraryStore {
    func saveConfiguration(_ draft: Game, original: Game, titleEdited: Bool, coverEdited: Bool) throws {
        guard let index = games.firstIndex(where: { $0.id == original.id }) else { throw VNError.message("作品已移除。") }
        let current = games[index]
        let edited = try GameConfiguration.applying(
            draft, original: original, to: current, titleEdited: titleEdited, coverEdited: coverEdited)
        var proposed = games
        proposed[index] = edited
        try commitPersonalLibrary(games: proposed, collections: collections)
        if !GameConfiguration.sameAnalysisInputs(edited, current) {
            reports[edited.id] = nil
        }
    }
}
