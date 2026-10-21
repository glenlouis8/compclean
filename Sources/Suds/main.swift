import CleanerCore
import SudsUI
import SwiftUI

@main
struct SudsApp: App {
    init() { RenameMigration.run() }
    var body: some Scene { SudsScenes() }
}
