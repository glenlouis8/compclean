import Foundation

/// A folder or file in the disk map, with its total size.
public struct DiskNode: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let size: Int64
    public let isFolder: Bool
    public var children: [DiskNode]

    public init(path: String, name: String, size: Int64, isFolder: Bool, children: [DiskNode] = []) {
        self.path = path
        self.name = name
        self.size = size
        self.isFolder = isFolder
        self.children = children
    }
}

/// Read-only size map of a folder, built in one pass.
public struct DiskMapper: Sendable {
    public let depth: Int

    public init(depth: Int = 4) {
        self.depth = depth
    }

    /// Folder types that look like single files in Finder; they're shown as one tile.
    static let packageExtensions: Set<String> = SafetyPolicy.packageExtensions.union(
        ["bundle", "framework", "plugin", "kext", "pkg", "xcodeproj", "xcworkspace", "playground", "rtfd", "sparsebundle"])

    /// Walks `root` once. `progress` gets the running total of bytes counted.
    public func map(_ given: URL, progress: (@Sendable (Int64) -> Void)? = nil) -> DiskNode {
        // Resolve aliases like /var -> /private/var so child paths line up with the root.
        let rootPath = SafetyPolicy.realPath(given.path) ?? given.standardizedFileURL.path
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        var sizes: [String: Int64] = [:]
        var leaves: Set<String> = []
        var total: Int64 = 0
        var counter = 0

        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                                       options: [], errorHandler: { _, _ in true }) {
            while let url = walker.nextObject() as? URL {
                guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true,
                      v.isSymbolicLink != true else { continue }
                let size = Int64(v.totalFileAllocatedSize ?? 0)
                guard size > 0 else { continue }
                total += size
                let rel = url.path.dropFirst(rootPath.count + 1).split(separator: "/").map(String.init)
                var prefix = rootPath
                for (k, part) in rel.enumerated() where k < depth {
                    prefix += "/" + part
                    sizes[prefix, default: 0] += size
                    let isLast = k == rel.count - 1
                    let isPackage = Self.packageExtensions.contains((part as NSString).pathExtension.lowercased())
                    if isLast || isPackage {
                        if isLast && !isPackage { leaves.insert(prefix) }
                        break // a package is one tile; don't map inside it
                    }
                }
                counter += 1
                if counter % 5_000 == 0 { progress?(total) }
            }
        }
        progress?(total)

        var byParent: [String: [String]] = [:]
        for path in sizes.keys { byParent[(path as NSString).deletingLastPathComponent, default: []].append(path) }

        func build(_ path: String) -> [DiskNode] {
            (byParent[path] ?? []).map { p in
                DiskNode(path: p, name: (p as NSString).lastPathComponent, size: sizes[p] ?? 0,
                         isFolder: !leaves.contains(p), children: build(p))
            }
            .sorted { $0.size > $1.size }
        }
        return DiskNode(path: rootPath, name: root.lastPathComponent, size: total, isFolder: true, children: build(rootPath))
    }
}

/// Squarified treemap layout (Bruls, Huizing, van Wijk). Pure geometry, so it's easy to test.
public enum Treemap {
    public struct Rect: Sendable, Equatable {
        public var x, y, w, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    }

    /// Lays out `sizes` (any order) inside `bounds`. Returns one rect per input, in input order.
    public static func layout(_ sizes: [Double], in bounds: Rect) -> [Rect] {
        let total = sizes.reduce(0, +)
        guard total > 0, bounds.w > 0, bounds.h > 0 else { return sizes.map { _ in Rect(x: bounds.x, y: bounds.y, w: 0, h: 0) } }
        let scale = bounds.w * bounds.h / total
        let order = sizes.indices.sorted { sizes[$0] > sizes[$1] }
        var result = Array(repeating: Rect(x: 0, y: 0, w: 0, h: 0), count: sizes.count)
        var free = bounds
        var row: [Int] = []

        func worst(_ row: [Int], side: Double) -> Double {
            let areas = row.map { sizes[$0] * scale }
            let s = areas.reduce(0, +)
            guard let mx = areas.max(), let mn = areas.min(), s > 0, mn > 0 else { return .infinity }
            return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
        }

        func place(_ row: [Int]) {
            let area = row.reduce(0) { $0 + sizes[$1] * scale }
            if free.w >= free.h {
                let colW = free.h > 0 ? area / free.h : 0
                var y = free.y
                for i in row {
                    let h = colW > 0 ? sizes[i] * scale / colW : 0
                    result[i] = Rect(x: free.x, y: y, w: colW, h: h)
                    y += h
                }
                free = Rect(x: free.x + colW, y: free.y, w: max(0, free.w - colW), h: free.h)
            } else {
                let rowH = free.w > 0 ? area / free.w : 0
                var x = free.x
                for i in row {
                    let w = rowH > 0 ? sizes[i] * scale / rowH : 0
                    result[i] = Rect(x: x, y: free.y, w: w, h: rowH)
                    x += w
                }
                free = Rect(x: free.x, y: free.y + rowH, w: free.w, h: max(0, free.h - rowH))
            }
        }

        for i in order where sizes[i] > 0 {
            let side = min(free.w, free.h)
            if row.isEmpty || worst(row + [i], side: side) <= worst(row, side: side) {
                row.append(i)
            } else {
                place(row)
                row = [i]
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }
}
