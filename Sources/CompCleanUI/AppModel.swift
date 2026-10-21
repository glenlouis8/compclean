import AppKit
import CleanerCore
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    let policy = SafetyPolicy()
    let log = ActionLog()
    let ledger = TrashLedger()
    lazy var history = HistoryStore(ledger: ledger, policy: policy, log: log)
    lazy var explainer = ItemExplainer(home: policy.home)
    let ai = AIAssistant()

    /// One or two sentences from the on-device model after a Cleaner scan, when available.
    @Published var scanSummary: String?
    @Published var isSummarizing = false

    lazy var leftoversStore = makeStore("Leftovers", prepare: { OrphanFinder.prepareForRemoval($0) }) { [policy] in
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return {
            let installed = AppInspector.installedApps(home: URL(fileURLWithPath: policy.home)).map(\.bundleID)
            return OrphanFinder(policy: policy, knownIDs: Set(installed + running)).find()
        }
    }

    // Developer junk settings: stale age and project folders (one path per line; empty = defaults).
    @AppStorage("devStaleDays") var devStaleDays = 30
    @AppStorage("devRoots") var devRootsRaw = ""

    var devRoots: [URL] {
        let custom = devRootsRaw.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        return custom.isEmpty ? DevJunkFinder.defaultRoots(home: URL(fileURLWithPath: policy.home)) : custom
    }

    var devRootsDescription: String {
        let names = devRoots.map { $0.path.replacingOccurrences(of: policy.home, with: "~") }
        return names.isEmpty ? "none found, add one in Settings" : names.joined(separator: ", ")
    }

    lazy var devStore = makeStore("Developer junk") { [unowned self] in
        let (policy, roots, days) = (policy, devRoots, devStaleDays)
        return { DevJunkFinder(policy: policy, roots: roots, staleDays: days).find() }
    }

    lazy var diskMap = DiskMapStore(home: policy.home)

    @AppStorage("bigMinMB") var bigMinMB = 500

    lazy var bigFilesStore = makeStore("Big files") { [unowned self] in
        let (policy, minMB) = (policy, bigMinMB)
        return { LargeFileFinder(policy: policy, minMB: minMB).find() }
    }

    lazy var duplicatesStore = makeStore("Duplicates") { [policy] in
        { DuplicateFinder(policy: policy).find() }
    }

    private func makeStore(_ feature: String, prepare: (@Sendable ([ReviewItem]) -> Void)? = nil,
                           finder: @escaping @MainActor () -> @Sendable () -> [ReviewItem]) -> FinderStore {
        FinderStore(feature: feature, policy: policy, log: log, history: history, prepare: prepare,
                    onFreed: { [weak self] bytes in
                        self?.totalFreed += Double(bytes)
                        self?.refreshDisk()
                    },
                    finder: finder)
    }

    @Published var pane: Pane? = LayoutProbe.startPane ?? .cleaner

    // Unused apps
    @Published var appLastUsed: [String: Date] = [:]
    @Published var usageLoaded = false
    @AppStorage("unusedMonths") var unusedMonths = 6

    func loadUsage() async {
        if apps.isEmpty { await loadApps() }
        let list = apps
        let dates = await Task.detached {
            Dictionary(list.compactMap { app in AppUsage.lastUsed(app.url).map { (app.id, $0) } },
                       uniquingKeysWith: { a, _ in a })
        }.value
        appLastUsed = dates
        usageLoaded = true
    }

    var unusedApps: [(app: AppInfo, lastUsed: Date?)] {
        AppUsage.unused(apps, months: unusedMonths) { [appLastUsed] url in appLastUsed[url.path] }
    }

    func openInUninstaller(_ app: AppInfo) {
        pane = .uninstaller
        Task { await choose(app) }
    }

    /// Plain-language explanation for each finding, keyed by path.
    @Published var explanations: [String: Explanation] = [:]

    // Cleaner
    @Published var enabledCategories: Set<CleanCategory> = Set(CleanCategory.allCases.filter(\.autoSafe))
    @Published var findings: [Finding] = []
    @Published var selected: Set<String> = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var lastMessage: String?
    @Published var hasScanned = false
    @Published var scanningCategory: CleanCategory?
    @Published var scannedCategories: Set<CleanCategory> = []
    @Published var justFreed: Int64?
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var appSizes: [String: Int64] = [:]
    @Published var quickEstimate: Int64?
    @Published var isEstimating = false
    @Published var lastQuickFreed: Int64?

    // Uninstaller
    @Published var apps: [AppInfo] = []
    @Published var isLoadingApps = false
    @Published var chosenApp: AppInfo?
    @Published var leftovers: [Leftover] = []
    @Published var leftoverSelection: Set<String> = []
    @Published var isFindingLeftovers = false
    @Published var uninstallMessage: String?
    @Published var justUninstalled: UninstallSummary?

    // Settings
    @AppStorage("schedule") var scheduleRaw = Schedule.weekly.rawValue
    @AppStorage("lastAutoRun") private var lastAutoRunStamp: Double = 0
    @AppStorage("totalFreed") var totalFreed: Double = 0
    @Published var hasFullDiskAccess = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var timer: Timer?

    var schedule: Schedule {
        get { Schedule(rawValue: scheduleRaw) ?? .weekly }
        set { scheduleRaw = newValue.rawValue; objectWillChange.send() }
    }

    var lastAutoRun: Date? { lastAutoRunStamp > 0 ? Date(timeIntervalSince1970: lastAutoRunStamp) : nil }

    init() {
        refreshPermission()
        refreshDisk()
        requestNotificationPermission()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { await refreshQuickEstimate() }
    }

    private var ticks = 0

    /// Every 30 s: run a due auto clean; every 5 min: refresh the menu bar's "ready to clean" figure.
    private func tick() {
        autoCleanIfDue()
        ticks += 1
        if ticks % 10 == 0 {
            refreshDisk()
            Task { await refreshQuickEstimate() }
        }
    }

    // MARK: - Permissions

    func refreshPermission() {
        // A folder macOS only lets apps list once Full Disk Access is granted. Read-only check.
        let probe = policy.home + "/Library/Safari"
        hasFullDiskAccess = (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastMessage = "Login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Cleaner

    var selectedFindings: [Finding] { findings.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.size } }

    func findings(in category: CleanCategory) -> [Finding] { findings.filter { $0.category == category } }

    func bytes(in category: CleanCategory) -> Int64 { findings(in: category).reduce(0) { $0 + $1.size } }
    func selectedBytes(in category: CleanCategory) -> Int64 {
        findings(in: category).filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    var foundBytes: Int64 { findings.reduce(0) { $0 + $1.size } }

    /// Scans one category at a time so the cards fill in live.
    func scan() async {
        isScanning = true
        lastMessage = nil
        justFreed = nil
        findings = []
        selected = []
        scannedCategories = []
        scanSummary = nil
        for category in CleanCategory.allCases where enabledCategories.contains(category) {
            await scanOne(category)
        }
        scanningCategory = nil
        hasScanned = true
        isScanning = false
        await summarizeScan()
    }

    /// Asks the on-device model for a plain summary of the scan. Silently skipped when unavailable.
    func summarizeScan() async {
        guard ai.isUsable, !findings.isEmpty else { return }
        isSummarizing = true
        let groups = CleanCategory.allCases.map { (name: $0.title, count: findings(in: $0).count, bytes: bytes(in: $0)) }
        let biggest = findings.sorted { $0.size > $1.size }.prefix(5)
            .map { (title: explanations[$0.id]?.title ?? $0.displayName, bytes: $0.size) }
        let facts = AIFacts.scan(groups: groups, biggest: Array(biggest), selectedBytes: selectedBytes)
        scanSummary = await ai.summarize(facts)
        isSummarizing = false
    }

    func scanOne(_ category: CleanCategory) async {
        scanningCategory = category
        enabledCategories.insert(category)
        let scanner = Scanner(policy: policy, runningBundleIDs: runningBundleIDs())
        let explainer = explainer
        let (result, explained) = await Task.detached {
            let found = scanner.scan(category)
            return (found, Dictionary(found.map { ($0.id, explainer.explain($0)) }, uniquingKeysWith: { a, _ in a }))
        }.value
        explanations.merge(explained) { _, new in new }
        findings.removeAll { $0.category == category }
        findings += result.sorted { $0.size > $1.size }
        // Old downloads are personal files, so they start unticked.
        if category.autoSafe { selected.formUnion(result.map(\.id)) }
        scannedCategories.insert(category)
        if !isScanning { scanningCategory = nil }
    }

    func setCategorySelected(_ category: CleanCategory, _ on: Bool) {
        let ids = findings(in: category).map(\.id)
        if on { selected.formUnion(ids) } else { selected.subtract(ids) }
    }

    func refreshDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func cleanSelected() async {
        let items = selectedFindings
        guard !items.isEmpty else { return }
        isCleaning = true
        let trasher = Trasher(policy: policy, log: log)
        let outcome = await Task.detached { trasher.trash(items) }.value
        history.record(feature: "Cleaner", moves: outcome.moves,
                       titles: Dictionary(items.map { ($0.url, explanations[$0.id]?.title ?? $0.displayName) },
                                          uniquingKeysWith: { a, _ in a }))
        let removed = Set(outcome.trashed.map(\.path))
        findings.removeAll { removed.contains($0.id) }
        selected.subtract(removed)
        totalFreed += Double(outcome.bytesFreed)
        lastMessage = summary(outcome)
        justFreed = outcome.bytesFreed
        refreshDisk()
        isCleaning = false
        await refreshQuickEstimate()
    }

    /// Scheduled and menu-bar cleaning: only auto-safe categories, no preview.
    func quickClean(reason: String) async {
        guard !isCleaning else { return }
        isCleaning = true
        let scanner = Scanner(policy: policy, runningBundleIDs: runningBundleIDs())
        let trasher = Trasher(policy: policy, log: log)
        let cleaner = AutoCleaner(scanner: scanner, trasher: trasher, explainer: explainer)
        let (outcome, titles) = await Task.detached { cleaner.run() }.value
        history.record(feature: reason == "auto clean" ? "Auto clean" : "Quick clean", moves: outcome.moves, titles: titles)
        totalFreed += Double(outcome.bytesFreed)
        lastAutoRunStamp = Date().timeIntervalSince1970
        lastMessage = summary(outcome)
        lastQuickFreed = outcome.bytesFreed
        quickEstimate = 0
        refreshDisk()
        isCleaning = false
        notify(title: "CompClean \(reason)", body: "Moved \(ByteFormat.string(outcome.bytesFreed)) of junk to the Trash.")
        if hasScanned { await scan() }
    }

    /// Size of what a quick clean would remove right now. Read-only.
    func refreshQuickEstimate() async {
        guard !isEstimating, !isCleaning else { return }
        isEstimating = true
        let scanner = Scanner(policy: policy, runningBundleIDs: runningBundleIDs())
        let found = await Task.detached { scanner.scan(AutoCleaner.categories) }.value
        quickEstimate = found.reduce(0) { $0 + $1.size }
        isEstimating = false
    }

    var nextAutoRun: Date? {
        guard let interval = schedule.interval else { return nil }
        return (lastAutoRun ?? Date()).addingTimeInterval(lastAutoRun == nil ? 0 : interval)
    }

    private func autoCleanIfDue() {
        guard schedule.isDue(lastRun: lastAutoRun), !isCleaning, !isScanning else { return }
        Task { await quickClean(reason: "auto clean") }
    }

    private func summary(_ o: TrashOutcome) -> String {
        var parts = ["Moved \(o.trashed.count) items (\(ByteFormat.string(o.bytesFreed))) to Trash."]
        if !o.refused.isEmpty { parts.append("\(o.refused.count) blocked by safety rules.") }
        if !o.failed.isEmpty { parts.append("\(o.failed.count) failed.") }
        return parts.joined(separator: " ")
    }

    private func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    // MARK: - Uninstaller

    func loadApps() async {
        isLoadingApps = true
        let home = URL(fileURLWithPath: policy.home)
        apps = await Task.detached { AppInspector.installedApps(home: home) }.value
        isLoadingApps = false
        for app in apps where appSizes[app.id] == nil {
            let url = app.url
            appSizes[app.id] = await Task.detached { AppInspector.size(of: url) }.value
        }
    }

    var chosenSelectedBytes: Int64 { selectedLeftovers.reduce(0) { $0 + $1.size } }

    func selectLeftovers(_ mode: LeftoverSelection) {
        switch mode {
        case .recommended: leftoverSelection = Set(leftovers.filter(\.match.preselected).map(\.id))
        case .all: leftoverSelection = Set(leftovers.map(\.id))
        case .none: leftoverSelection = []
        }
    }

    func choose(appAt url: URL) async {
        guard let info = await Task.detached(operation: { AppInspector.inspect(url) }).value else {
            uninstallMessage = "That isn't an app bundle."
            return
        }
        guard !info.isApple else {
            uninstallMessage = "\(info.name) is part of macOS. CompClean never removes Apple apps."
            return
        }
        await choose(info)
    }

    func choose(_ app: AppInfo) async {
        justUninstalled = nil
        chosenApp = app
        uninstallMessage = nil
        leftovers = []
        isFindingLeftovers = true
        let finder = LeftoverFinder(policy: policy)
        let found = await Task.detached { finder.find(for: app) }.value
        guard chosenApp == app else { return }
        leftovers = found
        leftoverSelection = Set(found.filter(\.match.preselected).map(\.id))
        isFindingLeftovers = false
    }

    var selectedLeftovers: [Leftover] { leftovers.filter { leftoverSelection.contains($0.id) } }

    func uninstallChosen() async {
        guard let app = chosenApp else { return }
        let items = selectedLeftovers
        guard !items.isEmpty else { return }
        // Grab the icon now; once the app is in the Trash its path shows a blank icon.
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        await quit(app)
        let uninstaller = Uninstaller(policy: policy, log: log)
        let report = await Task.detached { uninstaller.remove(items, of: app) }.value
        history.record(feature: "Uninstalled \(app.name)", moves: report.moves,
                       titles: Dictionary(items.map { ($0.url, $0.match == .app ? app.name : $0.url.lastPathComponent) },
                                          uniquingKeysWith: { a, _ in a }))
        totalFreed += Double(report.bytesFreed)
        var msg = "Moved \(report.trashed.count) items (\(ByteFormat.string(report.bytesFreed))) to Trash."
        if report.adminCancelled { msg += " Admin items skipped (password cancelled)." }
        if !report.failed.isEmpty { msg += " \(report.failed.count) failed." }
        uninstallMessage = msg
        let gone = Set(report.trashed.map(\.path))
        leftovers.removeAll { gone.contains($0.id) }
        leftoverSelection.subtract(gone)
        if gone.contains(app.url.path) {
            apps.removeAll { $0 == app }
            appSizes[app.id] = nil
            justUninstalled = UninstallSummary(
                name: app.name, icon: icon, bytes: report.bytesFreed, count: report.trashed.count,
                leftBehind: leftovers.count
            )
            chosenApp = nil
            leftovers = []
            leftoverSelection = []
        }
        refreshDisk()
    }

    private func quit(_ app: AppInfo) async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - Notifications

    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
