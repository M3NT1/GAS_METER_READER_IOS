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
                    ReviewView(
                        model: review.model,
                        photoURL: review.photoURL,
                        onRetake: {
                            capture.retake()
                        }
                    )
                } else {
                    CaptureView(model: capture, credentialStore: container.credentialStore)
                }
            }
        }
        .task {
            try? await container.bootstrapMeterCatalog()
        }
    }
}
