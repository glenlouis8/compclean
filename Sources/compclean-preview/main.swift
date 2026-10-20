import AppKit
import CleanerCore
import Foundation

// Read-only: lists what CompClean would suggest removing. Nothing is moved.
// Usage: compclean-preview [--orphans | --dev | --big | --dupes]
let policy = SafetyPolicy()
let home = policy.home
let mode = CommandLine.arguments.dropFirst().first ?? "--clean"

func show(_ items: [ReviewItem]) {
    var order: [String] = []
    var groups: [String: [ReviewItem]] = [:]
    for i in items {
        if groups[i.group] == nil { order.append(i.group) }
        groups[i.group, default: []].append(i)
    }
    for g in order {
        let list = groups[g]!
        print("\n\(g): \(list.count) items, \(ByteFormat.string(list.reduce(0) { $0 + $1.size }))")
        for i in list.prefix(12) {
            let tick = i.preselected ? "[x]" : "[ ]"
            print("  \(tick) \(ByteFormat.string(i.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(i.explanation.title)  —  \(i.url.path.replacingOccurrences(of: home, with: "~"))")
        }
        if list.count > 12 { print("  … and \(list.count - 12) more") }
    }
    print("\nTotal: \(ByteFormat.string(items.reduce(0) { $0 + $1.size })) in \(items.count) items (preview only, nothing moved)")
}

func knownIDs() -> Set<String> {
    let installed = AppInspector.installedApps().map(\.bundleID)
    let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    return Set(installed + running)
}

switch mode {
case "--orphans":
    show(OrphanFinder(policy: policy, knownIDs: knownIDs()).find())
case "--dev":
    let finder = DevJunkFinder(policy: policy)
    print("Project folders: \(finder.roots.map { $0.path.replacingOccurrences(of: home, with: "~") })")
    show(finder.find())
    print("Unavailable simulators: \(DevTools.unavailableSimulatorCount())")
    print("Docker: \(DevTools.dockerReclaimable() ?? "not running / not installed")")
case "--selftest":
    // Real Trash round trip on a throwaway folder: trash it, put it back, trash it again.
    let fm = FileManager.default
    let probe = URL(fileURLWithPath: home + "/Library/Caches/com.compclean.selftest")
    try? fm.createDirectory(at: probe, withIntermediateDirectories: true)
    try? Data("hello".utf8).write(to: probe.appendingPathComponent("note.txt"))
    let ledger = TrashLedger(home: home, url: URL(fileURLWithPath: NSTemporaryDirectory() + "compclean-selftest.json"))
    let out = Trasher(policy: policy, log: ActionLog(url: URL(fileURLWithPath: NSTemporaryDirectory() + "compclean-selftest.log")))
        .trash([(probe, 5)], purpose: .clean)
    print("trashed: \(out.moves.map { $0.to?.path ?? "?" }) refused: \(out.refused.map(\.reason))")
    let session = ledger.record(feature: "selftest", moves: out.moves)!
    print("status before: \(ledger.status(of: session.entries[0]))")
    print("put back: \(ledger.putBack(session.entries[0]))")
    print("restored file readable: \((try? String(contentsOf: probe.appendingPathComponent("note.txt"), encoding: .utf8)) == "hello")")
    try? fm.trashItem(at: probe, resultingItemURL: nil)
case "--map":
    let root = DiskMapper().map(URL(fileURLWithPath: home))
    print("Home: \(ByteFormat.string(root.size))")
    for c in root.children.prefix(12) {
        print("  \(ByteFormat.string(c.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(c.name)")
        for g in c.children.prefix(3) { print("      \(ByteFormat.string(g.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(g.name)") }
    }
case "--big":
    show(LargeFileFinder(policy: policy).find())
case "--dupes":
    let finder = DuplicateFinder(policy: policy)
    print("Folders: \(finder.folders.map { $0.path.replacingOccurrences(of: home, with: "~") })")
    let items = finder.find()
    show(items)
    print("Space freed by removing extras: \(ByteFormat.string(items.filter { !$0.isKeeper }.reduce(0) { $0 + $1.size }))")
default:
    let explainer = ItemExplainer(home: home)
    show(Scanner(policy: policy).scan(Set(CleanCategory.allCases)).map { $0.reviewItem(explainer: explainer) })
}
