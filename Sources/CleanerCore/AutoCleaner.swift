import Foundation

/// The scheduled and menu-bar clean: auto-safe categories only, no preview, recorded in History.
public struct AutoCleaner: Sendable {
    public let scanner: Scanner
    public let trasher: Trasher
    public let explainer: ItemExplainer

    public init(scanner: Scanner, trasher: Trasher, explainer: ItemExplainer) {
        self.scanner = scanner
        self.trasher = trasher
        self.explainer = explainer
    }

    public static let categories = Set(CleanCategory.allCases.filter(\.autoSafe))

    /// Moves everything auto-safe to the Trash. Returns the outcome and a plain title per item for History.
    public func run() -> (outcome: TrashOutcome, titles: [URL: String]) {
        let found = scanner.scan(Self.categories)
        let titles = Dictionary(found.map { ($0.url, explainer.explain($0).title) }, uniquingKeysWith: { a, _ in a })
        return (trasher.trash(found), titles)
    }
}
