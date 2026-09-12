import SwiftUI
import UIKit

struct MagnifierLoupeView: View {
    let image: UIImage
    let targetPoint: CGPoint
    let fitRect: CGRect
    var zoom: CGFloat = 2.5
    var loupeDiameter: CGFloat = 120

    var body: some View {
        ZStack {
            // Magnified Image clipped to circle
            Circle()
                .fill(Color.black)
                .frame(width: loupeDiameter, height: loupeDiameter)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fitRect.width * zoom, height: fitRect.height * zoom)
                        .position(
                            x: (loupeDiameter / 2) - (targetPoint.x - fitRect.midX) * zoom,
                            y: (loupeDiameter / 2) - (targetPoint.y - fitRect.midY) * zoom
                        )
                }
                .clipShape(Circle())

            // Precision Crosshairs
            ZStack {
                // Horizontal line with center gap
                Rectangle()
                    .fill(Color.cyan)
                    .frame(width: loupeDiameter * 0.45, height: 1.5)

                // Vertical line with center gap
                Rectangle()
                    .fill(Color.cyan)
                    .frame(width: 1.5, height: loupeDiameter * 0.45)

                // Tiny center dot
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
            }

            // Bezel styling: white ring with subtle border and drop shadow
            Circle()
                .strokeBorder(Color.white, lineWidth: 3.5)
                .frame(width: loupeDiameter, height: loupeDiameter)

            Circle()
                .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                .frame(width: loupeDiameter + 2, height: loupeDiameter + 2)

            // Zoom indicator badge at bottom of loupe
            VStack {
                Spacer()
                Text(String(format: "%.1f×", zoom))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .offset(y: -6)
            }
            .frame(width: loupeDiameter, height: loupeDiameter)
        }
        .frame(width: loupeDiameter, height: loupeDiameter)
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
        .allowsHitTesting(false)
    }
}
