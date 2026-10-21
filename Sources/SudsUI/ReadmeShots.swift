#if DEBUG
import SwiftUI

// Screens rendered through Xcode previews for the README screenshots (docs/images).
// The preview name becomes the window title in the image.

#Preview("Suds") {
    CleanerView().previewEnvironment(width: 820, height: 1100)
}

#Preview("Uninstaller") {
    UninstallerView().previewEnvironment(PreviewData.uninstallModel(), width: 980, height: 640)
}

#Preview("Leftovers") {
    let m = PreviewData.leftoversModel()
    return FinderScreen(store: m.leftoversStore, title: "Leftovers",
                        subtitle: "Files that apps you already deleted left in your Library.",
                        symbol: "shippingbox", color: .blue)
        .previewEnvironment(m, width: 900, height: 640)
}

#Preview("Disk map") {
    let m = PreviewData.diskMapModel()
    return DiskMapView(store: m.diskMap).previewEnvironment(m, width: 900, height: 640)
}

#Preview("Welcome") {
    WelcomeView()
}
#endif
