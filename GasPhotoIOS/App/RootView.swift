import SwiftUI

struct RootView: View {
    let container: AppContainer
    @State private var capture: CaptureViewModel

    init(container: AppContainer) {
        self.container = container
        _capture = State(initialValue: CaptureViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let review = capture.review {
                    ReviewView(model: review.model, photoURL: review.photoURL)
                } else {
                    CaptureView(model: capture)
                }
            }
            .toolbar {
                NavigationLink {
                    HomeAssistantSettingsView(credentialStore: container.credentialStore)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Home Assistant beállítások")
            }
        }
    }
}
