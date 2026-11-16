// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class ScreenRecordingTests: XCTestCase {
    func testDefaultExclusionIsOnAndOffPersistsWithoutChangingGain() throws {
        let name = "MicRelay.RecordingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(ScreenRecordingSettings.load(in: defaults).excludesMonitorAudio)
        MonitorPreferences.saveGainLimit(6, in: defaults)
        MonitorPreferences.saveGain(6, in: defaults)
        ScreenRecordingSettings(excludesMonitorAudio: false).save(in: defaults)
        XCTAssertFalse(ScreenRecordingSettings.load(in: defaults).excludesMonitorAudio)
        XCTAssertEqual(MonitorPreferences.gain(in: defaults), 6)
        ScreenRecordingSettings().save(in: defaults)
        XCTAssertTrue(ScreenRecordingSettings.load(in: defaults).excludesMonitorAudio)
    }

    func testBackupV5PreservesBothChoicesAndLegacyDefaultsToExclusion() throws {
        for excludes in [true, false] {
            let backup = SettingsBackup(gain: 6, gainLimit: 6, equalizer: .init(), backgroundEnabled: true,
                selectedInput: "builtin", screenRecording: .init(excludesMonitorAudio: excludes))
            let decoded = try SettingsBackup.decode(backup.encoded())
            XCTAssertEqual(decoded.version, 5)
            XCTAssertEqual(decoded.screenRecording?.excludesMonitorAudio, excludes)
            for version in 1...4 {
                var json = try JSONSerialization.jsonObject(with: backup.encoded()) as! [String: Any]
                json["version"] = version
                json.removeValue(forKey: "screenRecording")
                if version < 4 { json.removeValue(forKey: "tapGate") }
                if version < 3 { json.removeValue(forKey: "manualAudio") }
                if version < 2 { json.removeValue(forKey: "windNoise") }
                let old = try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json))
                XCTAssertTrue((old.screenRecording ?? .init()).excludesMonitorAudio)
                XCTAssertEqual(old.gain, 6); XCTAssertEqual(old.gainLimit, 6)
                json["screenRecording"] = ["excludesMonitorAudio": false]
                XCTAssertThrowsError(try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json)))
            }
        }
    }

    @MainActor
    func testCancelFailureAndStaleCallbacksDoNotLeaveRecordingBusy() throws {
        guard #available(iOS 27, *) else { throw XCTSkip("Screen recording requires iOS 27") }
        var sessions: [FakeRecordingSession] = []
        var requested: [Bool] = []
        let model = ScreenRecordingModel(makeSession: { _, excluded, callback in
            let session = FakeRecordingSession(callback: callback)
            sessions.append(session); requested.append(excluded)
            return session
        })
        model.start(excludingMonitorAudio: true)
        model.start(excludingMonitorAudio: false)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(model.state, .selecting)
        sessions[0].callback(.cancelled)
        sessions[0].callback(.starting)
        XCTAssertFalse(model.state.isBusy)
        model.start(excludingMonitorAudio: false)
        XCTAssertEqual(requested, [true, false])
        sessions[0].callback(.failed("stale"))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.state, .selecting)
        sessions[1].callback(.starting); sessions[1].callback(.started)
        XCTAssertEqual(model.state, .recording); XCTAssertEqual(model.appliedExclusion, false)
        model.stop()
        XCTAssertEqual(model.state, .stopping); XCTAssertEqual(sessions[1].stopCount, 1)
        model.stop(); XCTAssertEqual(sessions[1].stopCount, 1)
        sessions[1].callback(.failed("failed"))
        XCTAssertFalse(model.state.isBusy); XCTAssertNil(model.appliedExclusion)
        XCTAssertEqual(model.errorMessage, "failed")
    }

    @MainActor
    func testPhotoSaveFailureKeepsFileAndCanRetryWithoutRestartingRecording() async throws {
        guard #available(iOS 27, *) else { throw XCTSkip("Screen recording requires iOS 27") }
        let name = "MicRelay.PhotoSaveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var callback: (@MainActor (ScreenRecordingEvent) -> Void)?
        var url: URL?
        var attempts = 0
        var fail = true
        let model = ScreenRecordingModel(makeSession: { path, _, handler in
            url = path; callback = handler
            return FakeRecordingSession(callback: handler)
        }, photoWriter: { path in
            attempts += 1
            XCTAssertEqual(path, url)
            if fail { throw RecordingPhotoLibrary.SaveError.permission }
        }, defaults: defaults)
        model.start(excludingMonitorAudio: true)
        let file = try XCTUnwrap(url)
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        callback?(.starting); callback?(.started); callback?(.finished(file))
        XCTAssertEqual(model.state, .stopping)
        for _ in 0..<100 where model.state.isBusy { await Task.yield() }
        XCTAssertEqual(attempts, 1); XCTAssertTrue(model.photoSaveFailed)
        XCTAssertFalse(model.savedToPhotos.contains(file.lastPathComponent))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        fail = false
        await model.saveToPhotos(file)
        XCTAssertEqual(attempts, 2); XCTAssertFalse(model.photoSaveFailed)
        XCTAssertFalse(model.savedToPhotos.contains(file.lastPathComponent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(model.savedMessage); XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(defaults.stringArray(forKey: "recordingPhotosSavedFiles"), [])
    }

    @MainActor
    func testDeletingAppCopyKeepsIndependentPhotoCopyAndRejectsOutsideFiles() async throws {
        let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("delete-test-\(UUID().uuidString).mp4")
        let photoCopy = FileManager.default.temporaryDirectory.appendingPathComponent("photo-copy-\(UUID().uuidString).mp4")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: file); try bytes.write(to: photoCopy)
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: photoCopy) }
        let name = "MicRelay.DeleteRecordingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var photoWrites = 0
        let model = ScreenRecordingModel(photoWriter: { _ in photoWrites += 1 }, defaults: defaults)
        await model.refreshVideos()
        let video = try XCTUnwrap(model.videos.first { $0.url.lastPathComponent == file.lastPathComponent })
        XCTAssertFalse(video.isPlayable) // Failed recordings must also be available for cleanup.
        XCTAssertEqual(video.bytes, 4)
        model.deleteAppCopy(video)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(model.videos.contains { $0.id == video.id })
        XCTAssertEqual(try Data(contentsOf: photoCopy), bytes)
        XCTAssertEqual(photoWrites, 0)
        XCTAssertFalse(model.savedToPhotos.contains(file.lastPathComponent))
        model.deleteAppCopy(.init(url: photoCopy, date: Date(), bytes: 4))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try Data(contentsOf: photoCopy), bytes)
    }

    @MainActor
    func testPreviouslyImportedVideoIsCleanedUpWithoutAnotherPhotoWrite() async throws {
        let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("previously-imported-\(UUID().uuidString).mp4")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let name = "MicRelay.PhotoCleanupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set([file.lastPathComponent], forKey: "recordingPhotosSavedFiles")
        var photoWrites = 0
        let model = ScreenRecordingModel(photoWriter: { _ in photoWrites += 1 }, defaults: defaults)
        await model.refreshVideos()
        XCTAssertEqual(photoWrites, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(model.videos.contains { $0.url == file })
        XCTAssertFalse(model.savedToPhotos.contains(file.lastPathComponent))
    }
}

@MainActor
private final class FakeRecordingSession: ScreenRecordingSession {
    let callback: @MainActor (ScreenRecordingEvent) -> Void
    var stopCount = 0
    init(callback: @escaping @MainActor (ScreenRecordingEvent) -> Void) { self.callback = callback }
    func present() {}
    func stop() { stopCount += 1 }
}
