import SwiftUI

struct RootView: View {
    let container: AppContainer

    var body: some View {
        ContentUnavailableView(
            "Gázóra leolvasás",
            systemImage: "gauge.with.dots.needle.50percent",
            description: Text("Az alkalmazás indításra kész.")
        )
    }
}
