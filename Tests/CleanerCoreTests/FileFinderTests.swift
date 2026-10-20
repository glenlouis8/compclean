import Foundation
import Testing
@testable import CleanerCore

@Suite struct LargeFileFinderTests {
    @Test func findsOnlyPersonalBigFiles() throws {
        let h = try FakeHome()
        try h.file("Movies/trip.mov", bytes: 2_200_000)
        try h.file("Downloads/installer.dmg", bytes: 2_100_000)
        try h.file("Downloads/small.zip", bytes: 10_000)
        try h.file("Library/Caches/huge.bin", bytes: 2_500_000)
        try h.file(".hidden/secret.bin", bytes: 2_500_000)
        try h.file("Pictures/Photos Library.photoslibrary/originals/a.heic", bytes: 2_500_000)

        let items = LargeFileFinder(policy: h.policy, minMB: 1, useSpotlight: false).find()
        #expect(Set(items.map(\.url.lastPathComponent)) == ["trip.mov", "installer.dmg"])
        #expect(items.allSatisfy { !$0.preselected && $0.explanation.safety == .yourFile && $0.purpose == .userFiles })
    }
}

@Suite struct DuplicateFinderTests {
    @Test func groupsIdenticalFilesOnly() throws {
        let h = try FakeHome()
        let a = try h.file("Downloads/photo.jpg", bytes: 1_500_000)
        let b = h.url.appendingPathComponent("Documents/photo copy.jpg")
        try FileManager.default.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: a).write(to: b) // real copy, separate storage
        // Same size, different content.
        var other = Data(repeating: 1, count: 1_500_000)
        other[700_000] = 9
        try other.write(to: h.url.appendingPathComponent("Desktop/other.jpg").creatingParent())

        let items = DuplicateFinder(policy: h.policy, folders: DuplicateFinder.defaultFolders(home: h.url)).find()
        #expect(Set(items.map(\.url.lastPathComponent)) == ["photo.jpg", "photo copy.jpg"])
        #expect(items.filter(\.isKeeper).count == 1)
        #expect(items.allSatisfy { !$0.preselected })
    }

    @Test func hardLinksAreNotDuplicates() throws {
        let h = try FakeHome()
        let a = try h.file("Documents/big.bin", bytes: 1_500_000)
        let link = h.url.appendingPathComponent("Documents/big-link.bin")
        try FileManager.default.linkItem(at: a, to: link)
        let items = DuplicateFinder(policy: h.policy, folders: [h.url.appendingPathComponent("Documents")]).find()
        #expect(items.isEmpty, "hard links share storage: \(items.map(\.url.lastPathComponent))")
    }

    @Test func clonesAreNotDuplicates() throws {
        let h = try FakeHome()
        let a = try h.file("Documents/clip.mov", bytes: 1_500_000)
        let clone = h.url.appendingPathComponent("Documents/clip clone.mov")
        // copyItem makes an APFS clone when the volume supports it.
        try FileManager.default.copyItem(at: a, to: clone)
        let ids = try [a, clone].map { try $0.resourceValues(forKeys: [.fileContentIdentifierKey]).fileContentIdentifier }
        let items = DuplicateFinder(policy: h.policy, folders: [h.url.appendingPathComponent("Documents")]).find()
        if ids[0] != nil && ids[0] == ids[1] {
            #expect(items.isEmpty, "clones share storage")
        } else {
            #expect(items.count == 2) // not APFS: a real copy is a real duplicate
        }
    }
}

extension URL {
    func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
