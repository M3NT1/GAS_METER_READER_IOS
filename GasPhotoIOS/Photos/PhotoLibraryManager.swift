import Foundation
import Photos
import UIKit

public enum PhotoLibraryManager {
    @discardableResult
    public static func saveImage(data: Data) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: data, options: nil)
            }
            return true
        } catch {
            print("[PhotoLibraryManager] Failed to save photo to library: \(error)")
            return false
        }
    }
}
