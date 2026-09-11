import SwiftUI

struct WindowEditorView: View {
    @Binding var window: NormalizedRect?

    var body: some View {
        GeometryReader { proxy in
            if let window {
                let frame = frame(for: window, in: proxy.size)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.green, lineWidth: 3)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityLabel("Felismerési keret")
            }
        }
        .allowsHitTesting(false)
    }

    private func frame(for window: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(
            x: window.left * size.width,
            y: window.top * size.height,
            width: (window.right - window.left) * size.width,
            height: (window.bottom - window.top) * size.height
        )
    }
}
