@preconcurrency import AVFoundation
import Foundation

enum CameraCaptureError: Error, Equatable {
    case captureAlreadyInProgress
    case missingPhotoData
}

final class CameraCaptureService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let output: AVCapturePhotoOutput
    private let archive: any PhotoArchive
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(output: AVCapturePhotoOutput, archive: any PhotoArchive) {
        self.output = output
        self.archive = archive
    }

    func captureAndStore() async throws -> PhotoReference {
        let data = try await captureOriginalData()
        return try archive.storeOriginal(data, suggestedExtension: "jpg")
    }

    func captureOriginalData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            guard self.continuation == nil else {
                continuation.resume(throwing: CameraCaptureError.captureAlreadyInProgress)
                return
            }

            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()

        if let error {
            waiting?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            waiting?.resume(returning: data)
        } else {
            waiting?.resume(throwing: CameraCaptureError.missingPhotoData)
        }
    }
}
