import Foundation

/// The app used to be called CompClean. On first launch as Suds, carry over its History,
/// action log and settings so nothing is lost. Runs once; later launches find nothing to move.
public enum RenameMigration {
    public static let oldBundleID = "com.glenlouis.compclean"

    public static func run(home: String = SafetyPolicy().home, bundleID: String? = Bundle.main.bundleIdentifier,
                           defaults: UserDefaults = .standard, oldBundleID: String = oldBundleID) {
        let fm = FileManager.default
        for parent in ["Library/Application Support", "Library/Logs"] {
            let old = URL(fileURLWithPath: home).appendingPathComponent("\(parent)/CompClean")
            let new = URL(fileURLWithPath: home).appendingPathComponent("\(parent)/Suds")
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
            }
        }
        // Settings live under the bundle id, which changed with the name.
        if let bundleID, bundleID != oldBundleID, defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true,
           let old = defaults.persistentDomain(forName: oldBundleID), !old.isEmpty {
            defaults.setPersistentDomain(old, forName: bundleID)
        }
    }
}
