import Foundation

public enum LibraryOrdering {
    public static func ordered(_ games: [Game], mode: String) -> [Game] {
        let visible = games.filter { !$0.isUtility }
        if mode == "title" {
            return visible.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        if mode == "series" {
            return visible.enumerated().sorted { a, b in
                let x = a.element.series?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let y = b.element.series?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if x == y { return a.offset < b.offset }
                if x.isEmpty { return false }
                if y.isEmpty { return true }
                return x.localizedStandardCompare(y) == .orderedAscending
            }.map(\.element)
        }
        return visible
    }
}
