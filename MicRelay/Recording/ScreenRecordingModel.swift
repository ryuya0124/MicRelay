// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import AVFoundation
import Combine
import Foundation

enum ScreenRecordingState: Equatable {
    case idle, selecting, starting, recording, stopping
    var isBusy: Bool { self != .idle }
}

struct RecordedVideo: Identifiable {
    let url: URL
    let date: Date
    let bytes: Int64
    var isPlayable = true
    var id: URL { url }
}

enum ScreenRecordingEvent {
    case starting, started, cancelled, finished(URL), failed(String)
}

@MainActor
protocol ScreenRecordingSession: AnyObject {
    func present()
    func stop()
}

@MainActor
final class ScreenRecordingModel: ObservableObject {
    typealias SessionFactory = (URL, Bool, @escaping @MainActor (ScreenRecordingEvent) -> Void) -> any ScreenRecordingSession
    @Published private(set) var state = ScreenRecordingState.idle
    @Published private(set) var videos: [RecordedVideo] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var savedMessage = false
    @Published private(set) var savedToPhotos: Set<String>
    @Published private(set) var photoSaveFailed = false
    @Published private(set) var appliedExclusion: Bool?
    private var session: (any ScreenRecordingSession)?
    private var generation = UUID()
    private var activeURL: URL?
    private let makeSession: SessionFactory?
    private let photoWriter: @MainActor (URL) async throws -> Void
    private let defaults: UserDefaults

    init(makeSession: SessionFactory? = nil, photoWriter: (@MainActor (URL) async throws -> Void)? = nil, defaults: UserDefaults = .standard) {
        self.makeSession = makeSession
        self.photoWriter = photoWriter ?? { try await RecordingPhotoLibrary.save($0) }
        self.defaults = defaults
        self.savedToPhotos = Set(defaults.stringArray(forKey: "recordingPhotosSavedFiles") ?? [])
    }

    var supportsRecording: Bool {
        #if DEBUG
        // Simulator-only availability coverage never changes real-device behavior.
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--recording-requires-update") { return false }
        #endif
        #endif
        if #available(iOS 27, *) { return true }
        return false
    }

    var status: String {
        switch state {
        case .idle: return String(localized: "recording.status.idle", defaultValue: "停止中")
        case .selecting: return String(localized: "recording.status.selecting", defaultValue: "録画する画面を選択してください")
        case .starting: return String(localized: "recording.status.starting", defaultValue: "録画を開始しています…")
        case .recording: return String(localized: "recording.status.recording", defaultValue: "録画中")
        case .stopping: return String(localized: "recording.status.stopping", defaultValue: "動画を保存しています…")
        }
    }

    func start(excludingMonitorAudio: Bool) {
        guard !state.isBusy, supportsRecording else { return }
        guard #available(iOS 27, *) else { return }
        errorMessage = nil
        savedMessage = false
        photoSaveFailed = false
        do {
            let folder = try recordingDirectory()
            let name = "MicRelay-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).mp4"
            let url = folder.appendingPathComponent(name)
            activeURL = url
            let token = UUID()
            generation = token
            appliedExclusion = excludingMonitorAudio
            state = .selecting
            let callback: @MainActor (ScreenRecordingEvent) -> Void = { [weak self] event in
                guard let self, generation == token else { return }
                receive(event)
            }
            let next: any ScreenRecordingSession
            if let makeSession { next = makeSession(url, excludingMonitorAudio, callback) }
            else {
                #if canImport(ScreenCaptureKit)
                next = ScreenCaptureSession(url: url, excludesMonitorAudio: excludingMonitorAudio, onEvent: callback)
                #else
                receive(.failed(String(localized: "recording.error.simulator", defaultValue: "画面録画は実機で利用してください。シミュレーターでは利用できません。")))
                return
                #endif
            }
            session = next
            next.present()
        } catch { receive(.failed(error.localizedDescription)) }
    }

    func stop() {
        guard state == .recording else { return }
        state = .stopping
        session?.stop()
    }

    private func receive(_ event: ScreenRecordingEvent) {
        switch event {
        case .starting: state = .starting
        case .started:
            if state == .starting { state = .recording }
        case .cancelled:
            endSession()
        case .finished(let url):
            endSession()
            state = .stopping
            Task { await writeToPhotos(url); await refreshVideos() }
        case .failed(let message):
            errorMessage = message
            endSession()
            Task { await refreshVideos() }
        }
    }

    func saveToPhotos(_ url: URL) async {
        guard state == .idle else { return }
        state = .stopping
        await writeToPhotos(url)
    }

    func saveAllToPhotos() async {
        guard state == .idle else { return }
        for video in videos where video.isPlayable && !savedToPhotos.contains(video.url.lastPathComponent) {
            await saveToPhotos(video.url)
            if photoSaveFailed { break }
        }
    }

    func deleteAppCopy(_ video: RecordedVideo) {
        guard state == .idle else { return }
        errorMessage = nil; photoSaveFailed = false; savedMessage = false
        do {
            try removeAppFile(video.url)
        } catch { errorMessage = error.localizedDescription }
    }

    private func removeAppFile(_ url: URL) throws {
        let folder = try recordingDirectory().resolvingSymlinksInPath().standardizedFileURL
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        guard file.deletingLastPathComponent() == folder,
              file.pathExtension.lowercased() == "mp4", file != activeURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: file)
        videos.removeAll { $0.url == url }
        savedToPhotos.remove(url.lastPathComponent)
        defaults.set(Array(savedToPhotos).sorted(), forKey: "recordingPhotosSavedFiles")
        // Only app storage is touched. There is no Photos deletion API in this path.
    }

    private func writeToPhotos(_ url: URL) async {
        errorMessage = nil
        savedMessage = false
        photoSaveFailed = false
        do {
            if !savedToPhotos.contains(url.lastPathComponent) { try await photoWriter(url) }
            savedToPhotos.insert(url.lastPathComponent)
            defaults.set(Array(savedToPhotos).sorted(), forKey: "recordingPhotosSavedFiles")
            do { try removeAppFile(url); savedMessage = true }
            catch {
                errorMessage = String(localized: "recording.photos.cleanup_failed", defaultValue: "写真への保存は完了しましたが、アプリ内のコピーを削除できませんでした。一覧からアプリ内の動画を削除できます。")
            }
        } catch { errorMessage = error.localizedDescription; photoSaveFailed = true }
        state = .idle
    }

    private func endSession() {
        generation = UUID()
        state = .idle; session = nil; appliedExclusion = nil; activeURL = nil
    }

    func refreshVideos() async {
        do {
            let folder = try recordingDirectory()
            let urls = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
            var result: [RecordedVideo] = []
            for url in urls where url.pathExtension.lowercased() == "mp4" && url != activeURL {
                if state == .idle, savedToPhotos.contains(url.lastPathComponent) {
                    // Also finish cleanup for videos imported by an earlier app version, or after a crash.
                    do { try removeAppFile(url); continue }
                    catch {
                        errorMessage = String(localized: "recording.photos.cleanup_failed", defaultValue: "写真への保存は完了しましたが、アプリ内のコピーを削除できませんでした。一覧からアプリ内の動画を削除できます。")
                    }
                }
                // Keep incomplete files visible for storage cleanup, but don't offer them for Photos import.
                let asset = AVURLAsset(url: url)
                let duration = try? await asset.load(.duration)
                let tracks = try? await asset.loadTracks(withMediaType: .video)
                let playable = duration?.seconds.isFinite == true && (duration?.seconds ?? 0) > 0 && tracks?.isEmpty == false
                let values = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                result.append(.init(url: url, date: values.creationDate ?? .distantPast, bytes: Int64(values.fileSize ?? 0), isPlayable: playable))
            }
            videos = result.sorted { $0.date > $1.date }
        } catch { errorMessage = error.localizedDescription }
    }

    private func recordingDirectory() throws -> URL {
        let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true).appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return folder
    }
}
