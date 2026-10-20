import Foundation
import Testing
@testable import CleanerCore

@Suite struct DiskMapTests {
    @Test func sizesRollUpAndPackagesStayWhole() throws {
        let h = try FakeHome()
        try h.file("Movies/a.mov", bytes: 300_000)
        try h.file("Movies/deep/b.mov", bytes: 100_000)
        try h.file("Pictures/Lib.photoslibrary/originals/x.heic", bytes: 200_000)
        try h.file("notes.txt", bytes: 5_000)

        let root = DiskMapper(depth: 4).map(h.url)
        let movies = try #require(root.children.first { $0.name == "Movies" })
        #expect(movies.size >= 400_000)
        #expect(movies.children.contains { $0.name == "deep" && $0.isFolder })
        let lib = try #require(root.children.first { $0.name == "Pictures" }?.children.first)
        #expect(lib.name == "Lib.photoslibrary")
        #expect(lib.children.isEmpty) // not mapped inside
        #expect(root.children.first { $0.name == "notes.txt" }?.isFolder == false)
        #expect(root.size == root.children.reduce(0) { $0 + $1.size })
        #expect(root.children.map(\.size) == root.children.map(\.size).sorted(by: >))
    }

    @Test func treemapFillsBoundsWithoutOverlap() {
        let sizes: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let bounds = Treemap.Rect(x: 0, y: 0, w: 600, h: 400)
        let rects = Treemap.layout(sizes, in: bounds)
        let area = rects.reduce(0) { $0 + $1.w * $1.h }
        #expect(abs(area - 600 * 400) < 1)
        for (i, s) in sizes.enumerated() {
            #expect(abs(rects[i].w * rects[i].h - s / 24 * 240_000) < 1)
            #expect(rects[i].x >= -0.001 && rects[i].y >= -0.001)
            #expect(rects[i].x + rects[i].w <= 600.001 && rects[i].y + rects[i].h <= 400.001)
        }
        for i in rects.indices { for j in rects.indices where j > i {
            let a = rects[i], b = rects[j]
            let overlap = max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x)) * max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))
            #expect(overlap < 0.01)
        } }
    }
}
