import Foundation

enum FileSize {
    private static let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]

    /// On-disk size of a file or directory tree. Does not follow symlinks.
    static func allocated(_ url: URL) -> Int64 {
        if let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true {
            return Int64(v.totalFileAllocatedSize ?? 0)
        }
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        while let item = walker.nextObject() as? URL {
            if let v = try? item.resourceValues(forKeys: keys), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: []
        )) ?? []
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
