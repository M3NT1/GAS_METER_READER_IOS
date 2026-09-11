@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CaptureView: View {
    @Bindable var model: CaptureViewModel

    var body: some View {
        VStack(spacing: 20) {
            CameraPreview(session: model.session)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .bottom) {
                    Text("Irányítsd a kamerát a teljes számlálóablakra.")
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding()
                }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button(model.isCapturing ? "Feldolgozás…" : "Fénykép készítése") {
                Task { await model.capture() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isConfigured || model.isCapturing)
        }
        .padding()
        .navigationTitle("Gázóra fényképezése")
        .task { model.configureAndStart() }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
