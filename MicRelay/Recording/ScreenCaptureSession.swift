// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#if canImport(ScreenCaptureKit)
import AVFoundation
import ScreenCaptureKit

/// ScreenCaptureKit owns capture/encoding. This never touches the RemoteIO callback or its session configuration.
@available(iOS 27, *)
@MainActor
final class ScreenCaptureSession: NSObject, ScreenRecordingSession, SCContentSharingPickerObserver, SCStreamDelegate, SCRecordingOutputDelegate {
    private let url: URL
    private let excludesMonitorAudio: Bool
    private let onEvent: @MainActor (ScreenRecordingEvent) -> Void
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var ended = false
    private var selecting = true
    private var watchdog: Task<Void, Never>?
    private var captureStopped = false

    init(url: URL, excludesMonitorAudio: Bool, onEvent: @escaping @MainActor (ScreenRecordingEvent) -> Void) {
        self.url = url; self.excludesMonitorAudio = excludesMonitorAudio; self.onEvent = onEvent
    }

    func present() {
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else {
            finish(.failed(String(localized: "recording.error.unavailable", defaultValue: "現在、画面録画を利用できません。別の録画や画面共有を終了して、もう一度お試しください。")))
            return
        }
        var config = SCContentSharingPickerConfiguration()
        config.showsMicrophoneControl = false
        config.showsCameraControl = false
        picker.defaultConfiguration = config
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    func stop() {
        guard let stream, !ended else { return }
        armWatchdog()
        Task {
            do { try await stream.stopCapture(); captureStopped = true }
            catch { finish(.failed(error.localizedDescription)) }
            // Success is reported only once the recording delegate confirms the MP4 is finalized.
        }
    }

    private func start(filter: SCContentFilter) {
        guard selecting, !ended else { return }
        selecting = false
        guard !filter.isMicrophoneEnabled else {
            finish(.failed(String(localized: "recording.error.microphone", defaultValue: "録画用マイクが有効なため開始できませんでした。録画用マイクをOFFにしてお試しください。")))
            return
        }
        onEvent(.starting)
        armWatchdog()
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = excludesMonitorAudio
        let next = SCStream(filter: filter, configuration: configuration, delegate: self)
        let file = SCRecordingOutputConfiguration()
        file.outputURL = url
        file.outputFileType = .mp4
        file.videoCodecType = .h264
        let recorder = SCRecordingOutput(configuration: file, delegate: self)
        stream = next; output = recorder
        Task {
            do {
                try next.addRecordingOutput(recorder)
                try await next.startCapture()
            } catch { finish(.failed(error.localizedDescription)) }
        }
    }

    private func finish(_ event: ScreenRecordingEvent) {
        guard !ended else { return }
        ended = true
        watchdog?.cancel(); watchdog = nil
        let previous = stream
        stream = nil; output = nil
        let picker = SCContentSharingPicker.shared
        picker.remove(self); picker.isActive = false
        onEvent(event)
        // Retain the session until cleanup completes, including failures during startup.
        Task { [self] in
            if !captureStopped { try? await previous?.stopCapture() }
        }
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            self?.finish(.failed(String(localized: "recording.error.timeout", defaultValue: "録画の応答がありません。録画を終了しました。もう一度お試しください。")))
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in if self.selecting { self.finish(.cancelled) } }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in self.start(filter: filter) }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.finish(.failed(error.localizedDescription)) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        // A system Stop action also finalizes the recording. Await its delegate before publishing the file.
        Task { @MainActor in
            guard !self.ended else { return }
            self.captureStopped = true
            if self.output == nil { self.finish(.failed(error.localizedDescription)) }
            else { self.armWatchdog() }
        }
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            if !self.ended { self.watchdog?.cancel(); self.watchdog = nil; self.onEvent(.started) }
        }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finish(.finished(self.url)) }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failed(error.localizedDescription)) }
    }
}
#endif
