// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation
import Photos

enum RecordingPhotoLibrary {
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.permission }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            // Keep the app copy until Photos confirms success. The caller then removes it.
            options.shouldMoveFile = false
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }

    enum SaveError: LocalizedError {
        case permission
        var errorDescription: String? {
            String(localized: "recording.photos.permission", defaultValue: "写真への追加が許可されていません。動画はアプリ内に残っています。設定で写真への追加を許可してから、もう一度保存してください。")
        }
    }
}
