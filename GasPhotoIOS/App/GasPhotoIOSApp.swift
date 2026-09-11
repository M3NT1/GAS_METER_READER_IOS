import SwiftUI

@main
struct GasPhotoIOSApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
