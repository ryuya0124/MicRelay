// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import AVFAudio
import AudioToolbox
import Combine
import MediaPlayer
import OSLog
import SwiftUI

struct MicrophoneChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let icon: String
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var status = String(localized: "monitor.status.initial", defaultValue: "イヤホンまたはHDMI機器を接続してください")
    @Published private(set) var microphones: [MicrophoneChoice] = []
    @Published private(set) var outputs: [OutputPort] = []
    @Published private(set) var activeInput = String(localized: "microphone.unused", defaultValue: "未使用")
    @Published private(set) var selectedInput = UserDefaults.standard.string(forKey: "selectedInput") ?? "builtin" {
        didSet { UserDefaults.standard.set(selectedInput, forKey: "selectedInput") }
    }
    @Published private(set) var permissionDenied = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var peak: Float = 0
    @Published private(set) var sampleRate: Double = 0
    @Published private(set) var bufferDuration: Double = 0
    @Published private(set) var inputLatency: Double = 0
    @Published private(set) var outputLatency: Double = 0
    @Published private(set) var unitProcessingLatency: Double?
    @Published private(set) var frames: UInt64 = 0
    @Published private(set) var waveform: [Float] = Array(repeating: 0, count: 128)
    @Published private(set) var maximumInputPeak: Float = 0
    @Published private(set) var maximumOutputPeak: Float = 0
    @Published private(set) var renderError: Int32 = 0
    @Published private(set) var missedQuanta: UInt64 = 0
    @Published private(set) var backgroundFrames: UInt64 = 0
    @Published private(set) var backgroundSeconds: Double = 0
    @Published private(set) var minimumQuantum: UInt32 = 0
    @Published private(set) var maximumQuantum: UInt32 = 0
    @Published private(set) var confirmedOutputs: Set<String> = []
    @Published var gain: Double = MonitorPreferences.gain() {
        didSet { MonitorPreferences.saveGain(gain); updateGain() }
    }
    @Published private(set) var gainLimit: Double = MonitorPreferences.gainLimit()
    @Published private(set) var equalizer = EqualizerSettings.load() {
        didSet { if !diagnosticProcessingSettings { equalizer.save() }; applyEqualizer() }
    }
    @Published private(set) var windNoise = WindNoiseSettings.load() {
        didSet { if !diagnosticProcessingSettings { windNoise.save() }; applyWindNoise() }
    }
    @Published private(set) var tapGate = TapGateSettings.load() {
        didSet { if !diagnosticProcessingSettings { tapGate.save() }; applyTapGate() }
    }
    @Published private(set) var tapGateOpen = false
    @Published private(set) var tapGateDetections: UInt64 = 0
    @Published private(set) var manualAudio = ManualAudioSettings.load()
    @Published private(set) var spectrum: SpectrumFrame?
    @Published private(set) var spectrumFrameCount: UInt64 = 0
    @Published private(set) var speakerEnabled = false
    @Published var backgroundEnabled = true {
        didSet { UserDefaults.standard.set(backgroundEnabled, forKey: "backgroundEnabled") }
    }

    @Published private(set) var isApplyingManual = false
    @Published private(set) var manualApplyError: String?
    @Published private(set) var lastManualObservation: ManualIOObservation?
    private var pendingManualAudio: ManualAudioSettings?
    private var activeManualAudio: ManualAudioSettings { pendingManualAudio ?? manualAudio }
    var effectiveModePreference: AudioModePreference { pendingManualAudio != nil ? .manual : (diagnosticAutomaticAudio ? .automatic : modePreference) }
    var usesManualIO: Bool { effectiveModePreference == .manual }
    var manualApplication: ManualIOApplication {
        ManualIOApplication(request: manualAudio, running: isRunning, renderedFrames: audio.renderedFrames,
            actualRate: sampleRate, minimumFrames: audio.minimumQuantum, maximumFrames: audio.maximumQuantum,
            ioDuration: bufferDuration, actualMode: actualSessionMode)
    }
    var actualSessionMode: AudioModePreference? {
        if session.mode == .default { return .standard }
        if session.mode == .measurement { return .measurement }
        return nil
    }
    private let audio = MRRealtimeAudio()
    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "net.ryuya-dev.MicRelay", category: "Monitor")
    private var observers: [NSObjectProtocol] = []
    private var meter: Timer?
    private var transition: Task<Void, Never>?
    private var generation = 0
    private var configuring = false
    private var inBackground = false
    private var remoteStop: Any?
    private var backgroundStartFrame: UInt64 = 0
    private var backgroundStartTime: TimeInterval = 0
    private var didRunDiagnostic = false
    @Published private(set) var requestedFrames: Double = 1
    @Published private(set) var tuningNote = String(localized: "latency.tuning.initial", defaultValue: "自動 · 接続先の最小バッファを使用")
    private var tuner = BufferTuner()
    private var tuningTask: Task<Void, Never>?
    private var diagnosticFrameOverride: Double?
    private var renderedFrameOffset: UInt64 = 0
    private var missedQuantumOffset: UInt64 = 0
    private var diagnosticHeadphones = false
    private var diagnosticAccessoryMic = false
    private var runningOutputIDs: Set<String> = []
    private var runningInputID: String?
    private var interruptionResume: (outputs: Set<String>, input: String)?
    private var preferredHardwareSampleRate: Double = 48_000
    private var monitoringMode: AVAudioSession.Mode = .measurement
    private var diagnosticSampleRateOverride: Double?
    private var diagnosticModeOverride: AVAudioSession.Mode?
    private var diagnosticExclusiveAudio = false
    private var diagnosticColdSession = false
    private var diagnosticAutomaticAudio = false
    private var appliedBufferRequest: Double = 1
    private var diagnosticRunID = ""
    @Published private(set) var selectedModeLabel = String(localized: "audio.mode.automatic", defaultValue: "自動")
    @Published private(set) var modePreference = AudioModePreference.load() {
        didSet { UserDefaults.standard.set(modePreference.rawValue, forKey: "audioModePreference") }
    }
    private var modeMeasurements: [ModeLatencyMeasurement] = []
    private var modeCache: [String: [ModeLatencyMeasurement]] = [:]
    private var bufferMeasurements: [BufferPreferenceMeasurement] = []
    private var preferenceCache = IOProfileCache()
    private var probeStartedAt: TimeInterval = 0
    private var probeAttempts = 0
    private var lastProbeSeconds: TimeInterval = 0
    private var lastProbeUsedCache = false
    private var startRequestedAt: TimeInterval = 0
    private var lastStartSeconds: TimeInterval = 0
    private var detailedProbe = false
    private var verifiedPreference: BufferPreferenceMeasurement?
    private var verifiedPreferenceKey: String?
    private var needsForegroundProbe = false
    private var latencyReprobe = LatencyReprobeTrigger()
    private var minimumObservedSampleRate: Double?
    private var minimumObservedFrames: Double?
    private let spectrumAnalyzer = SpectrumAnalyzer()
    private var spectrumVisible = false
    private var diagnosticProcessingSettings = false
    private var diagnosticMutedOutput = false

    func startDiagnosticIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard !didRunDiagnostic, arguments.contains("--validate-speaker") || arguments.contains("--validate-headphones") else { return }
        didRunDiagnostic = true
        diagnosticHeadphones = arguments.contains("--validate-headphones")
        diagnosticMutedOutput = arguments.contains("--mute-output-for-validation")
        diagnosticAccessoryMic = arguments.contains("--validate-accessory-mic")
        diagnosticExclusiveAudio = arguments.contains("--exclusive-audio")
        diagnosticColdSession = arguments.contains("--cold-session")
        diagnosticAutomaticAudio = arguments.contains("--automatic-mode")
        if arguments.contains("--adopt-automatic-mode") { modePreference = .automatic }
        diagnosticRunID = arguments.first(where: { $0.hasPrefix("--diagnostic-id=") }).map { String($0.dropFirst("--diagnostic-id=".count).prefix(64)) } ?? ""
        let diagnosticSeconds = arguments.first(where: { $0.hasPrefix("--diagnostic-seconds=") })
            .flatMap { Double($0.dropFirst("--diagnostic-seconds=".count)) }.map { min(120, max(0, $0)) } ?? 45
        if let argument = arguments.first(where: { $0.hasPrefix("--sample-rate=") }),
           let rate = Double(argument.split(separator: "=").last ?? ""), [44_100, 48_000, 88_200, 96_000, 176_400, 192_000, 384_000].contains(rate) {
            preferredHardwareSampleRate = rate
            diagnosticSampleRateOverride = rate
        }
        if arguments.contains("--session-mode=default") { diagnosticModeOverride = .default; monitoringMode = .default }
        if arguments.contains("--session-mode=measurement") { diagnosticModeOverride = .measurement; monitoringMode = .measurement }
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--io-frames=") }),
           let value = Double(argument.split(separator: "=").last ?? ""), (1...512).contains(value) {
            diagnosticFrameOverride = value
        }
        speakerEnabled = !diagnosticHeadphones
        start()
        if !diagnosticRunID.isEmpty {
            Task { [weak self] in
                while true {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, isRunning || isStarting else { return }
                    if isRunning { captureCounters(); writeDiagnostics() }
                }
            }
        }
        guard diagnosticSeconds > 0 else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(diagnosticSeconds))
            self?.stop(message: String(localized: "diagnostics.completed", defaultValue: "実機音声診断が完了しました"))
        }
        #endif
    }

    var canMonitor: Bool { OutputSafety.allows(outputs, confirmed: confirmedOutputs, speakerEnabled: speakerEnabled) }
    var canStart: Bool {
        startRequirement == .ready
    }
    var startRequirement: OutputSafety.StartRequirement {
        OutputSafety.startRequirement(outputs, confirmed: confirmedOutputs, speakerEnabled: speakerEnabled)
    }
    var isSpeaker: Bool { outputs.contains { $0.type == .builtInSpeaker } }
    var unconfirmedOutputs: [OutputPort] {
        outputs.filter { OutputSafety.needsConfirmation($0) && !confirmedOutputs.contains($0.uid) }
    }
    var outputName: String { ListFormatter.localizedString(byJoining: outputs.map(\.name)) }
    var isWireless: Bool { outputs.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.type) } }
    var reportedLatency: Double { inputLatency + outputLatency + bufferDuration + (unitProcessingLatency ?? 0) }

    init() {
        #if DEBUG
        diagnosticMutedOutput = ProcessInfo.processInfo.arguments.contains("--mute-output-for-validation")
        #endif
        #if DEBUG && targetEnvironment(simulator)
        // Native I/O tests opt into a speaker route without starting audible monitoring.
        speakerEnabled = ProcessInfo.processInfo.arguments.contains("--allow-speaker-for-validation")
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--validate-eq") {
            diagnosticProcessingSettings = true
            windNoise = .init()
            var value = EqualizerSettings()
            value.enabled = true
            value.bands[0].filter = .highPass; value.bands[0].frequency = 150
            value.bands[2].frequency = 800; value.bands[2].gainDB = -18; value.bands[2].q = 0.5
            equalizer = value
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--validate-range-eq") {
            diagnosticProcessingSettings = true
            windNoise = .init()
            var value = EqualizerSettings(); value.enabled = true
            value.bands[0].filter = .bandStop; value.bands[0].lowerFrequency = 500; value.bands[0].upperFrequency = 2000
            equalizer = value
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--validate-wind") {
            diagnosticProcessingSettings = true
            equalizer = .init()
            windNoise = .init(enabled: true, cutoff: 300)
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--validate-tap-gate") {
            diagnosticProcessingSettings = true
            equalizer = .init(); windNoise = .init(); tapGate = .init()
        }
        #endif
        if UserDefaults.standard.object(forKey: "backgroundEnabled") != nil {
            backgroundEnabled = UserDefaults.standard.bool(forKey: "backgroundEnabled")
        }
        permissionGranted = AVAudioApplication.shared.recordPermission == .granted
        permissionDenied = AVAudioApplication.shared.recordPermission == .denied
        refreshRoute()
        applyEqualizer()
        applyWindNoise()
        applyTapGate()
        #if DEBUG
        if diagnosticMutedOutput { writeDiagnostics() }
        #endif
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousIDs = previous?.outputs.map(\.uid) ?? []
            Task { @MainActor [weak self] in self?.routeChanged(reason: reason, previousIDs: previousIDs) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor [weak self] in self?.interrupted(type: type, options: options) }
        })
        for name in [AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stop(message: String(localized: "monitor.status.audio_reset", defaultValue: "音声システムが再起動しました。接続を確認して開始してください。"))
                    self?.refreshRoute()
                }
            })
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = false
        commands.pauseCommand.isEnabled = true
        commands.stopCommand.isEnabled = true
        remoteStop = commands.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }; return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }; return .success
        }
    }

    func confirmExternalOutput() {
        confirmedOutputs.formUnion(unconfirmedOutputs.map(\.uid))
        status = String(localized: "monitor.status.headphones_confirmed", defaultValue: "イヤホンを確認しました。開始できます。")
    }

    func startAfterOutputApproval(speaker: Bool, expectedIDs: Set<String>) {
        guard !isStarting, !isRunning else { return }
        refreshRoute()
        guard Set(outputs.map(\.uid)) == expectedIDs,
              startRequirement == (speaker ? .speakerPermission : .externalConfirmation) else {
            status = String(localized: "monitor.status.route_changed", defaultValue: "音声の接続が変わったため停止しました。確認して開始してください。")
            return
        }
        if speaker { speakerEnabled = true }
        else { confirmedOutputs.formUnion(unconfirmedOutputs.map(\.uid)) }
        // Begin one transition. setSpeakerEnabled also prepares the session, which would block start().
        start()
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        stop(message: enabled ? String(localized: "monitor.status.speaker_allowed", defaultValue: "スピーカー出力を許可しました") : String(localized: "monitor.status.external_outputs", defaultValue: "イヤホン・HDMI出力に戻しました"))
        speakerEnabled = enabled
        if permissionGranted { configureOnly() }
    }

    private func updateGain() {
        audio.gain = gain
    }

    private func applyEqualizer() {
        audio.setEqualizerEnabled(equalizer.enabled, bands: equalizer.bands.map(\.native))
    }

    private func applyWindNoise() {
        audio.setWindNoiseEnabled(windNoise.enabled, cutoff: windNoise.cutoff)
    }
    private func applyTapGate(enabled: Bool? = nil) {
        audio.setTapGateEnabled(enabled ?? tapGate.enabled, duration: tapGate.duration, minimumDB: tapGate.minimumDB, riseDB: tapGate.riseDB,
            afterFilters: tapGate.detectionSource == .afterFilters)
        if !(enabled ?? tapGate.enabled) { tapGateOpen = false; tapGateDetections = 0 }
    }
    func updateTapGate(_ update: (inout TapGateSettings) -> Void) {
        var value = tapGate
        update(&value)
        guard value.isValid else { return }
        tapGate = value
    }
    func setWindNoiseEnabled(_ enabled: Bool) {
        var value = windNoise; value.enabled = enabled; windNoise = value
    }
    func setWindNoiseCutoff(_ cutoff: Double) {
        guard cutoff.isFinite else { return }
        var value = windNoise
        value.cutoff = min(WindNoiseSettings.cutoffRange.upperBound, max(WindNoiseSettings.cutoffRange.lowerBound, cutoff))
        windNoise = value
    }

    func setEqualizerEnabled(_ enabled: Bool) {
        var value = equalizer; value.enabled = enabled; equalizer = value
    }

    func updateEqualizerBand(_ index: Int, _ update: (inout EqualizerBand) -> Void) {
        guard equalizer.bands.indices.contains(index) else { return }
        var value = equalizer
        update(&value.bands[index])
        var band = value.bands[index]
        guard band.frequency.isFinite, band.gainDB.isFinite, band.q.isFinite,
              band.lowerFrequency.isFinite, band.upperFrequency.isFinite else { return }
        band.frequency = min(20000, max(20, band.frequency))
        band.gainDB = min(24, max(-36, band.gainDB))
        band.q = min(30, max(0.2, band.q))
        band.lowerFrequency = min(19999, max(20, band.lowerFrequency))
        band.upperFrequency = min(20000, max(21, band.upperFrequency))
        guard band.upperFrequency - band.lowerFrequency >= 1 else { return }
        value.bands[index] = band
        equalizer = value
    }

    func resetEqualizer() {
        var value = EqualizerSettings(); value.enabled = equalizer.enabled; equalizer = value
    }

    func setSpectrumVisible(_ visible: Bool) {
        spectrumVisible = visible
        if visible { startSpectrumIfNeeded() }
        else { audio.analysisEnabled = false; spectrumAnalyzer.stop() }
    }

    private func startSpectrumIfNeeded() {
        guard spectrumVisible, isRunning, !inBackground else { return }
        spectrumAnalyzer.start(audio: audio, sampleRate: sampleRate) { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self, isRunning, spectrumVisible, !inBackground,
                      abs(frame.sampleRate - sampleRate) < 0.5 else { return }
                spectrum = frame
                spectrumFrameCount &+= 1
            }
        }
    }

    @discardableResult
    func setGainLimit(percent: Double) -> Bool {
        let limit = percent / 100
        guard MonitorPreferences.saveGainLimit(limit) else { return false }
        gainLimit = limit
        if gain > limit { gain = limit }
        return true
    }

    func settingsBackup() -> SettingsBackup {
        SettingsBackup(gain: gain, gainLimit: gainLimit, equalizer: equalizer,
            backgroundEnabled: backgroundEnabled, selectedInput: selectedInput, audioMode: modePreference, windNoise: windNoise, manualAudio: manualAudio, tapGate: tapGate, screenRecording: .load())
    }

    func restoreSettings(_ backup: SettingsBackup) throws -> Bool {
        let value = try backup.validated()
        stop(message: String(localized: "monitor.status.restored", defaultValue: "設定を復元しました。モニターの再開は手動です"))
        MonitorPreferences.saveGainLimit(value.gainLimit)
        gainLimit = value.gainLimit
        gain = value.gain
        equalizer = value.equalizer
        windNoise = value.windNoise ?? .init()
        tapGate = value.tapGate ?? .init()
        (value.screenRecording ?? .init()).save()
        manualAudio = value.manualAudio ?? .init()
        manualAudio.save()
        backgroundEnabled = value.backgroundEnabled
        modePreference = value.audioMode ?? .automatic
        let available = value.selectedInput == "builtin" || microphones.contains { $0.id == value.selectedInput }
        selectedInput = available ? value.selectedInput : "builtin"
        return available
    }

    @discardableResult
    func applyManualAudio(_ value: ManualAudioSettings) async -> Bool {
        guard value.isValid, !isApplyingManual, !isStarting else { return false }
        manualApplyError = nil
        refreshRoute()
        guard canStart else { manualApplyError = ManualAudioApplyError.connection.localizedDescription; return false }
        isApplyingManual = true
        let permissionGeneration = generation
        if !permissionGranted {
            guard await requestAccess() else {
                isApplyingManual = false
                manualApplyError = ManualAudioApplyError.permission.localizedDescription; return false
            }
        }
        guard permissionGeneration == generation, !Task.isCancelled else { isApplyingManual = false; return false }
        let resume = isRunning
        let oldRate = preferredHardwareSampleRate, oldFrames = requestedFrames, oldMode = monitoringMode
        let oldObservation = lastManualObservation
        let outputIDs = Set(outputs.map(\.uid))
        stop()
        let token = generation
        pendingManualAudio = value
        isStarting = true; isApplyingManual = true; configuring = true
        do {
            try configureSession()
            try await Task.sleep(for: .milliseconds(100))
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            try validateActiveRoute()
            try audio.prepare(withSampleRate: session.sampleRate)
            audio.outputMuted = true
            audio.gain = 0
            audio.setEqualizerEnabled(false, bands: equalizer.bands.map(\.native))
            audio.setWindNoiseEnabled(false, cutoff: windNoise.cutoff)
            applyTapGate(enabled: false)
            try audio.start()
            let observation = try await observeManualIO(value, token: token, outputIDs: outputIDs)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            // Keep the verified Audio Unit when resuming: reconfiguring it after saving
            // would create an unverified second application of the same preferences.
            if resume { try openMonitorOutput(expectedOutputs: outputIDs) }
            // Only a verified candidate reaches persistent settings.
            guard ManualAudioSettings.commitVerified(observation) else { throw ManualAudioApplyError.unstable }
            manualAudio = value; modePreference = .manual
            pendingManualAudio = nil; isStarting = false; isApplyingManual = false; configuring = false
            selectedModeLabel = value.mode.title
            tuningNote = AudioModePreference.manual.title
            lastManualObservation = observation
            status = String(localized: "manual.applied", defaultValue: "手動設定を適用しました（要求どおり）")
            if resume { didStartMonitoring(resetTuning: false) }
            else { audio.stop(); try? session.setActive(false, options: .notifyOthersOnDeactivation) }
            return true
        } catch {
            guard token == generation else { return false }
            audio.stop()
            pendingManualAudio = nil; isStarting = false; isApplyingManual = false; configuring = false
            preferredHardwareSampleRate = oldRate; requestedFrames = oldFrames; monitoringMode = oldMode
            lastManualObservation = oldObservation
            if !(error is CancellationError) {
                let reason = error is ManualAudioApplyError ? error.localizedDescription : String(localized: "manual.error.unsupported", defaultValue: "この接続では指定したI/O設定を適用できません。要求: \(value.verificationSummary + " · " + value.mode.title)。\(error.localizedDescription)")
                manualApplyError = String(localized: "manual.error.rollback", defaultValue: "\(reason) 元の設定に戻しました。")
            }
            if resume { start(resetTuning: false) }
            else { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
            return false
        }
    }

    private func observeManualIO(_ request: ManualAudioSettings, token: Int, outputIDs: Set<String>) async throws -> ManualIOObservation {
        try await Task.sleep(for: .milliseconds(100))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try validateActiveRoute()
        guard Set(outputs.map(\.uid)) == outputIDs else { throw ManualAudioApplyError.connection }
        try audio.start()
        audio.resetQuantumStatistics()
        let initialFrames = audio.renderedFrames, initialMisses = audio.missedQuanta
        let began = ProcessInfo.processInfo.systemUptime
        // Reject extreme/unsupported requests promptly instead of waiting for a huge hinted period.
        try await Task.sleep(for: .seconds(min(2, max(0.2, 8 * session.ioBufferDuration))))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try validateActiveRoute()
        guard Set(outputs.map(\.uid)) == outputIDs else { throw ManualAudioApplyError.connection }
        let observation = ManualIOObservation(request: request, sampleRate: session.sampleRate,
            minimumFrames: audio.minimumQuantum, maximumFrames: audio.maximumQuantum,
            ioDuration: session.ioBufferDuration, mode: actualSessionMode,
            renderedFrames: audio.renderedFrames &- initialFrames, misses: audio.missedQuanta &- initialMisses,
            renderError: audio.renderError, duration: ProcessInfo.processInfo.systemUptime - began)
        #if DEBUG
        print("MicRelay manual verification: \(observation)")
        logger.info("manual verification: frames=\(observation.renderedFrames) misses=\(observation.misses) error=\(observation.renderError) duration=\(observation.duration) rate=\(observation.sampleRate) quantum=\(observation.minimumFrames)-\(observation.maximumFrames) io=\(observation.ioDuration)")
        #endif
        if observation.application.state == .different { throw ManualAudioApplyError.mismatch(observation) }
        guard observation.application.state == .matched, observation.isStable else { throw ManualAudioApplyError.unstable }
        return observation
    }

    func selectAudioMode(_ mode: AudioModePreference) {
        guard mode != .manual, mode != modePreference else { return }
        let resume = isRunning
        stop(message: String(localized: "monitor.status.mode_changed", defaultValue: "音声モードを変更しました"))
        modePreference = mode
        selectedModeLabel = mode.title
        if resume { start() }
    }

    func selectInput(_ id: String) {
        guard selectedInput != id else { return }
        let resume = isRunning
        stop(message: String(localized: "monitor.status.input_changed", defaultValue: "マイクを切り替えました"))
        selectedInput = id
        if resume { start() }
        else if permissionGranted { configureOnly() }
    }

    func requestAccess() async -> Bool {
        let allowed = await AVAudioApplication.requestRecordPermission()
        permissionGranted = allowed
        permissionDenied = !allowed
        if !allowed { status = String(localized: "microphone.permission_required", defaultValue: "設定アプリでマイクへのアクセスを許可してください。") }
        return allowed
    }

    func prepare() {
        guard !isStarting && !isRunning else { return }
        configureOnly()
    }

    private func configureOnly() {
        transition?.cancel()
        generation += 1
        let token = generation
        isStarting = true
        transition = Task { [weak self] in
            guard let self else { return }
            guard await requestAccess(), token == generation, !Task.isCancelled else {
                if token == generation { isStarting = false }; return
            }
            do {
                configuring = true
                try configureSession()
                try await Task.sleep(for: .milliseconds(200))
                guard token == generation else { return }
                refreshRoute()
                configuring = false
                isStarting = false
                status = canMonitor ? String(localized: "monitor.status.ready", defaultValue: "準備できました") : String(localized: "monitor.status.connection_required", defaultValue: "イヤホン・HDMI機器の接続先を確認してください")
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                if token == generation { fail(error) }
            }
        }
    }

    func start(resetTuning: Bool = true, reprobeMinimum: Bool = false, exhaustiveProbe: Bool = false) {
        guard !isStarting && !isRunning else { return }
        startRequestedAt = ProcessInfo.processInfo.systemUptime
        let previousPreference = verifiedPreferenceKey == preferenceCacheKey ? verifiedPreference : nil
        if resetTuning {
            tuner = BufferTuner()
            requestedFrames = usesManualIO ? Double(manualAudio.frames) : (diagnosticFrameOverride ?? 1)
            tuningNote = usesManualIO ? AudioModePreference.manual.title : String(localized: "latency.tuning.initial", defaultValue: "自動 · 接続先に合わせて確認")
            renderedFrameOffset = 0; missedQuantumOffset = 0
            maximumInputPeak = 0; maximumOutputPeak = 0
            backgroundFrames = 0; backgroundSeconds = 0
            bufferMeasurements = []; minimumObservedFrames = nil; minimumObservedSampleRate = nil; verifiedPreference = nil
        }
        refreshRoute()
        guard canStart || diagnosticHeadphones else { status = String(localized: "monitor.status.connection_required", defaultValue: "イヤホン・HDMI機器の接続先を確認してください"); return }
        generation += 1
        let token = generation
        isStarting = true
        status = String(localized: "monitor.status.connecting", defaultValue: "音声を接続中…")
        transition = Task { [weak self] in
            guard let self else { return }
            guard await requestAccess(), token == generation, !Task.isCancelled else {
                if token == generation { isStarting = false }; return
            }
            do {
                configuring = true
                if reprobeMinimum { modeCache.removeAll() }
                let preference = effectiveModePreference
                if (resetTuning || reprobeMinimum) && diagnosticModeOverride == nil { monitoringMode = preference.sessionMode }
                try configureSession()
                try await Task.sleep(for: .milliseconds(250))
                guard token == generation, !Task.isCancelled else { return }
                try validateActiveRoute()
                let probeBuffers = (resetTuning || reprobeMinimum) && diagnosticFrameOverride == nil && !inBackground && !usesManualIO
                if (resetTuning || reprobeMinimum) && diagnosticModeOverride == nil && preference == .automatic && !probeBuffers {
                    try await chooseLatencyMode(token: token)
                    if inBackground { needsForegroundProbe = true }
                }
                selectedModeLabel = monitoringMode == .measurement ? String(localized: "audio.mode.measurement", defaultValue: "測定") : String(localized: "audio.mode.standard", defaultValue: "標準")
                if probeBuffers {
                    try await chooseBufferPreference(token: token, useCache: !reprobeMinimum && !exhaustiveProbe, exhaustive: exhaustiveProbe)
                    selectedModeLabel = monitoringMode == .measurement ? String(localized: "audio.mode.measurement", defaultValue: "測定") : String(localized: "audio.mode.standard", defaultValue: "標準")
                }
                guard !inBackground || backgroundEnabled else { stop(); return }
                if !probeBuffers { try audio.prepare(withSampleRate: session.sampleRate) }
                // Read the route again after AudioUnit initialization, before opening the gate.
                refreshRoute()
                guard canMonitor else { stop(message: String(localized: "monitor.status.no_output", defaultValue: "対応する出力先が接続されていないため停止しました")); return }
                if usesManualIO {
                    lastManualObservation = nil
                    audio.outputMuted = true
                    audio.gain = 0
                    audio.setEqualizerEnabled(false, bands: equalizer.bands.map(\.native))
                    audio.setWindNoiseEnabled(false, cutoff: windNoise.cutoff)
                    applyTapGate(enabled: false)
                    try audio.start()
                    lastManualObservation = try await observeManualIO(activeManualAudio, token: token, outputIDs: Set(outputs.map(\.uid)))
                    guard token == generation, !Task.isCancelled else { throw CancellationError() }
                }
                try openMonitorOutput()
                didStartMonitoring(resetTuning: resetTuning)
            } catch {
                if token == generation {
                    if error is CancellationError, inBackground, backgroundEnabled, !usesManualIO, !diagnosticColdSession,
                       let fallback = previousPreference ?? BufferPreferenceSelector.best(bufferMeasurements) {
                        // Preserve the active background session; no inactive-session sweep here.
                        audio.stop()
                        requestedFrames = fallback.requestedFrames
                        preferredHardwareSampleRate = fallback.requestedSampleRate ?? fallback.sampleRate
                        monitoringMode = AVAudioSession.Mode(rawValue: fallback.mode)
                        verifiedPreference = fallback
                        verifiedPreferenceKey = preferenceCacheKey
                        needsForegroundProbe = true
                        isStarting = false; configuring = false
                        start(resetTuning: false)
                    } else { fail(error) }
                }
            }
        }
    }

    private func openMonitorOutput(expectedOutputs: Set<String>? = nil) throws {
        try validateActiveRoute()
        if let expectedOutputs, Set(outputs.map(\.uid)) != expectedOutputs { throw ManualAudioApplyError.connection }
        updateGain()
        applyEqualizer()
        applyWindNoise()
        applyTapGate()
        audio.outputMuted = diagnosticMutedOutput
        try audio.start()
    }

    private func didStartMonitoring(resetTuning: Bool) {
        lastStartSeconds = ProcessInfo.processInfo.systemUptime - startRequestedAt
        configuring = false
        isStarting = false
        isRunning = true
        runningOutputIDs = Set(session.currentRoute.outputs.map(\.uid))
        runningInputID = session.currentRoute.inputs.first?.uid
        if inBackground && (resetTuning || needsForegroundProbe) {
            backgroundStartFrame = renderedFrameOffset + audio.renderedFrames
            backgroundStartTime = ProcessInfo.processInfo.systemUptime
        }
        if !inBackground { startMeter() }
        startSpectrumIfNeeded()
        tuner.didStart(now: ProcessInfo.processInfo.systemUptime,
            actualFrames: BufferPreferenceSelector.effectiveFrames(quantum: audio.currentQuantum, duration: session.ioBufferDuration, sampleRate: session.sampleRate),
            minimumObservedFrames: minimumObservedSampleRate.map { abs($0 - session.sampleRate) < 0.5 } == true ? minimumObservedFrames : nil)
        latencyReprobe.didStart(now: ProcessInfo.processInfo.systemUptime,
            baseline: verifiedPreference?.latencyMeasurement ?? currentLatencyMeasurement())
        startTuning()
        status = String(localized: "monitor.status.running", defaultValue: "モニター中")
        updateNowPlaying()
        logger.info("started rate=\(self.sampleRate) buffer=\(self.bufferDuration) input=\(self.activeInput, privacy: .public) output=\(self.outputName, privacy: .public)")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, isRunning else { return }
            captureCounters()
            writeDiagnostics()
        }
    }

    private func validateActiveRoute(preferenceKey: String? = nil) throws {
        refreshRoute()
        if let preferenceKey, preferenceCacheKey != preferenceKey { throw MonitorError.routeChanged }
        if diagnosticHeadphones { confirmedOutputs.formUnion(unconfirmedOutputs.map(\.uid)) }
        guard canMonitor else { throw MonitorError.inputUnavailable }
        let actual = session.currentRoute.inputs.first
        if selectedInput == "builtin" {
            guard actual?.portType == .builtInMic else { throw MonitorError.inputUnavailable }
        } else {
            guard actual?.uid == selectedInput else { throw MonitorError.inputUnavailable }
        }
    }

    private func chooseLatencyMode(token: Int) async throws {
        let key = selectedInput + "|" + session.currentRoute.outputs.map { $0.uid + $0.portType.rawValue }.sorted().joined(separator: "|")
        if let cached = modeCache[key], let best = LatencyModeSelector.best(cached) {
            modeMeasurements = cached
            monitoringMode = AVAudioSession.Mode(rawValue: best.mode)
            if diagnosticSampleRateOverride == nil { preferredHardwareSampleRate = best.sampleRate }
            try configureSession()
            try await Task.sleep(for: .milliseconds(150))
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            try validateActiveRoute()
            return
        }
        var measurements: [ModeLatencyMeasurement] = []
        for mode in [AVAudioSession.Mode.default, .measurement] {
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            audio.stop()
            monitoringMode = mode
            do {
                try configureSession()
                try await Task.sleep(for: .milliseconds(150))
                guard token == generation, !Task.isCancelled else { throw CancellationError() }
                try validateActiveRoute()
                try audio.prepare(withSampleRate: session.sampleRate)
                audio.setEqualizerEnabled(false, bands: equalizer.bands.map(\.native))
                audio.setWindNoiseEnabled(false, cutoff: windNoise.cutoff)
                applyTapGate(enabled: false)
                // Compare active hardware paths without changing the saved/user-facing gain.
                audio.outputMuted = true
                audio.gain = 0
                try audio.start()
                try await Task.sleep(for: .milliseconds(200))
                guard token == generation, !Task.isCancelled else { throw CancellationError() }
                try validateActiveRoute()
                if audio.renderedFrames > 0, audio.renderError == 0 {
                    measurements.append(ModeLatencyMeasurement(mode: mode.rawValue,
                        inputLatency: session.inputLatency, outputLatency: session.outputLatency,
                        ioBufferDuration: session.ioBufferDuration, sampleRate: session.sampleRate,
                        quantum: audio.minimumQuantum, processingLatency: audio.processingLatency?.doubleValue))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { logger.info("Mode probe unavailable: \(mode.rawValue, privacy: .public)") }
            audio.stop()
        }
        guard let best = LatencyModeSelector.best(measurements) else { throw MonitorError.noStableMode }
        modeMeasurements = measurements
        modeCache[key] = measurements
        monitoringMode = AVAudioSession.Mode(rawValue: best.mode)
        try configureSession()
        try await Task.sleep(for: .milliseconds(150))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try validateActiveRoute()
    }

    private func configureSession() throws {
        if usesManualIO {
            preferredHardwareSampleRate = activeManualAudio.sampleRate
            requestedFrames = Double(activeManualAudio.frames)
            monitoringMode = activeManualAudio.mode.sessionMode
        }
        if diagnosticColdSession { try session.setActive(false) }
        // Keep monitoring alongside games/music; the OS negotiates the shared hardware buffer.
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        if !diagnosticExclusiveAudio { options.insert(.mixWithOthers) }
        try session.setCategory(.playAndRecord, mode: monitoringMode, options: options)
        try session.setPrefersInterruptionOnRouteDisconnect(true)
        if usesManualIO { try session.setPreferredSampleRate(preferredHardwareSampleRate) }
        else { try? session.setPreferredSampleRate(preferredHardwareSampleRate) }
        // Preferences are hints; the foreground probe checks actual callback sizes.
        try requestBuffer(sampleRate: preferredHardwareSampleRate)
        try session.setActive(true)
        let ports = session.availableInputs ?? []
        #if DEBUG
        if diagnosticAccessoryMic && selectedInput == "builtin" {
            guard let accessory = ports.first(where: { $0.portType != .builtInMic }) else { throw MonitorError.inputUnavailable }
            selectedInput = accessory.uid
        }
        #endif
        let input = selectedInput == "builtin" ? ports.first { $0.portType == .builtInMic } : ports.first { $0.uid == selectedInput }
        guard let input else { throw MonitorError.inputUnavailable }
        try session.setPreferredInput(input)
        if speakerEnabled && session.currentRoute.outputs.allSatisfy({ [.builtInReceiver, .builtInSpeaker].contains($0.portType) }) {
            try session.overrideOutputAudioPort(.speaker)
        } else {
            try session.overrideOutputAudioPort(.none)
        }
        try requestBuffer(sampleRate: session.sampleRate)
    }

    private var preferenceCacheKey: String {
        [effectiveModePreference.rawValue, selectedInput,
         session.currentRoute.outputs.map { $0.uid + $0.portType.rawValue }.sorted().joined(separator: ","),
         diagnosticModeOverride?.rawValue ?? "", diagnosticSampleRateOverride.map { String($0) } ?? "",
         String(diagnosticExclusiveAudio), ProcessInfo.processInfo.operatingSystemVersionString].joined(separator: "|")
    }

    private var modeCacheKey: String {
        selectedInput + "|" + session.currentRoute.outputs.map { $0.uid + $0.portType.rawValue }.sorted().joined(separator: "|")
    }

    private func currentLatencyMeasurement() -> ModeLatencyMeasurement {
        .init(mode: session.mode.rawValue, inputLatency: session.inputLatency, outputLatency: session.outputLatency,
              ioBufferDuration: session.ioBufferDuration, sampleRate: session.sampleRate, quantum: audio.currentQuantum,
              processingLatency: audio.processingLatency?.doubleValue)
    }

    private func measurePreference(mode: AVAudioSession.Mode, rate: Double, request: Double, token: Int, key: String) async throws -> BufferPreferenceMeasurement {
        guard token == generation, !Task.isCancelled, !inBackground else { throw CancellationError() }
        probeAttempts += 1
        let elapsed = Int(ProcessInfo.processInfo.systemUptime - probeStartedAt)
        status = detailedProbe
            ? String(localized: "latency.tuning.detailed_progress", defaultValue: "詳しく最適化中 · \(probeAttempts)件目 · \(elapsed)秒")
            : String(localized: "latency.tuning.progress", defaultValue: "音声設定を確認中 · \(probeAttempts)件目 · \(elapsed)秒")
        audio.stop()
        try session.setActive(false)
        monitoringMode = mode; preferredHardwareSampleRate = rate; requestedFrames = request
        try configureSession()
        try await Task.sleep(for: .milliseconds(100))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try validateActiveRoute(preferenceKey: key)
        try audio.prepare(withSampleRate: session.sampleRate)
        audio.setEqualizerEnabled(false, bands: equalizer.bands.map(\.native))
        audio.setWindNoiseEnabled(false, cutoff: windNoise.cutoff)
        applyTapGate(enabled: false)
        audio.outputMuted = true; audio.gain = 0
        try audio.start()
        try await Task.sleep(for: .milliseconds(100))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try validateActiveRoute(preferenceKey: key)
        try audio.start() // Reopen a late route-change gate only after validation.
        audio.resetQuantumStatistics()
        let initialMisses = audio.missedQuanta, initialFrames = audio.renderedFrames
        let began = ProcessInfo.processInfo.systemUptime
        let seconds = max(0.16, 8 * max(session.ioBufferDuration, Double(audio.currentQuantum) / session.sampleRate))
        try await Task.sleep(for: .seconds(seconds))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try validateActiveRoute(preferenceKey: key)
        return BufferPreferenceMeasurement(requestedFrames: request, actualFrames: audio.maximumQuantum,
            sampleRate: session.sampleRate, ioBufferDuration: session.ioBufferDuration,
            inputLatency: session.inputLatency, outputLatency: session.outputLatency,
            missedQuanta: audio.missedQuanta &- initialMisses, renderedFrames: audio.renderedFrames &- initialFrames,
            renderError: audio.renderError, mode: session.mode.rawValue,
            observationDuration: ProcessInfo.processInfo.systemUptime - began, requestedSampleRate: rate,
            processingLatency: audio.processingLatency?.doubleValue)
    }

    func optimizeIOThoroughly() {
        guard canStart, !isStarting, !usesManualIO else { return }
        stop()
        start(reprobeMinimum: true, exhaustiveProbe: true)
    }

    private func chooseBufferPreference(token: Int, useCache: Bool, exhaustive: Bool) async throws {
        probeStartedAt = ProcessInfo.processInfo.systemUptime; probeAttempts = 0; detailedProbe = exhaustive; lastProbeUsedCache = false
        defer { lastProbeSeconds = ProcessInfo.processInfo.systemUptime - probeStartedAt; detailedProbe = false }
        status = String(localized: "latency.tuning.probing", defaultValue: "音声設定を確認中…")
        let key = preferenceCacheKey
        bufferMeasurements = []
        if useCache, let cached = preferenceCache[key] {
            do {
                let observed = try await measurePreference(mode: AVAudioSession.Mode(rawValue: cached.measurement.mode),
                    rate: cached.measurement.requestedSampleRate ?? cached.measurement.sampleRate,
                    request: cached.measurement.requestedFrames, token: token, key: key)
                bufferMeasurements.append(observed)
                if observed.reproduces(cached.measurement) {
                    lastProbeUsedCache = true
                    finishPreference(observed, floor: cached.floor, modes: cached.modes, key: key)
                    return
                }
            } catch is CancellationError { throw CancellationError() }
            catch MonitorError.routeChanged { throw MonitorError.routeChanged }
            catch { logger.info("Cached preference needs a fresh sweep") }
            audio.stop()
        }
        preferenceCache.remove(key)
        if !exhaustive {
            try await chooseStartupPreference(token: token, key: key)
            return
        }
        let automatic = effectiveModePreference == .automatic && diagnosticModeOverride == nil
        let modes = automatic ? [AVAudioSession.Mode.default, .measurement] : [monitoringMode]
        let rates = HardwareRateProbePlanner.requests(current: session.sampleRate, preferred: preferredHardwareSampleRate, fixed: diagnosticSampleRateOverride)
        var known: [HardwareRateProbeKey: BufferPreferenceMeasurement] = [:]
        for mode in modes {
            for rate in rates {
                // Re-test a known good frame request, rather than an ignored one-frame hint.
                let first = BufferPreferenceSelector.best(Array(known.values).filter { $0.mode == mode.rawValue })?.requestedFrames
                    ?? BufferPreferenceSelector.requests[0]
                var tried: Set<Double> = []
                var reuse = false
                var noInput = false
                var requests = [first]
                var index = 0
                while index < requests.count {
                    let request = requests[index]; index += 1
                    guard tried.insert(request).inserted else { continue }
                    do {
                        let observed = try await measurePreference(mode: mode, rate: rate, request: request, token: token, key: key)
                        bufferMeasurements.append(observed)
                        if inBackground {
                            guard backgroundEnabled, observed.isStable else { throw CancellationError() }
                            finishPreference(observed, floor: max(Double(observed.actualFrames), observed.ioBufferDuration * observed.sampleRate),
                                modes: [observed.latencyMeasurement], key: key, cacheable: false)
                            return
                        }
                        if request == first, let reference = known[HardwareRateProbeKey(observed)],
                           HardwareRateProbePlanner.canReuse(observed, reference: reference) { reuse = true }
                        if observed.renderError == kAudioUnitErr_NoConnection { noInput = true }
                    } catch is CancellationError { throw CancellationError() }
                    catch MonitorError.routeChanged { throw MonitorError.routeChanged }
                    catch { logger.info("Hardware preference unavailable: rate=\(rate), frames=\(request)") }
                    audio.stop()
                    if reuse || noInput { break }
                    if index == 1 { requests.append(contentsOf: BufferPreferenceSelector.frameRequests(sampleRate: session.sampleRate)) }
                    // A stable exact match is not a stopping condition: a larger quantum can have a faster OS path.
                }
                for observed in bufferMeasurements where observed.isStable {
                    let hardware = HardwareRateProbeKey(observed)
                    known[hardware] = BufferPreferenceSelector.best([known[hardware], observed].compactMap { $0 })
                }
            }
        }
        try await confirmPreference(token: token, key: key, modes: modes)
    }

    private func chooseStartupPreference(token: Int, key: String) async throws {
        let modes = effectiveModePreference == .automatic && diagnosticModeOverride == nil
            ? [AVAudioSession.Mode.default, .measurement] : [monitoringMode]
        let rate = diagnosticSampleRateOverride ?? session.sampleRate
        func hasStable() -> Bool { BufferPreferenceSelector.best(bufferMeasurements) != nil }
        func withinBudget() -> Bool {
            StartupIOProbe.canCompare(elapsed: ProcessInfo.processInfo.systemUptime - probeStartedAt, hasStable: hasStable())
        }
        func observe(_ mode: AVAudioSession.Mode, _ rate: Double, _ frames: Double) async throws {
            do {
                let observation = try await measurePreference(mode: mode, rate: rate, request: frames, token: token, key: key)
                bufferMeasurements.append(observation)
            } catch is CancellationError { throw CancellationError() }
            catch MonitorError.routeChanged { throw MonitorError.routeChanged }
            catch { logger.info("Startup preference unavailable") }
            audio.stop()
        }
        initial: for frames in StartupIOProbe.frames {
            for mode in modes {
                guard withinBudget() else { break initial }
                try await observe(mode, rate, frames)
            }
        }
        if !hasStable() {
            recovery: for frames in StartupIOProbe.recoveryFrames {
                for mode in modes {
                    try await observe(mode, rate, frames)
                    if hasStable() { break recovery }
                }
            }
        } else {
            rates: for extraRate in StartupIOProbe.extraRates(current: rate, fixed: diagnosticSampleRateOverride) {
                for mode in modes {
                    guard withinBudget() else { break rates }
                    let frames = BufferPreferenceSelector.best(bufferMeasurements.filter { $0.mode == mode.rawValue })?.requestedFrames ?? 16
                    try await observe(mode, extraRate, frames)
                }
            }
        }
        try await confirmPreference(token: token, key: key, modes: modes, limit: 3)
    }

    private func confirmPreference(token: Int, key: String, modes: [AVAudioSession.Mode], limit: Int = .max) async throws {
        for candidate in BufferPreferenceSelector.ranked(bufferMeasurements).prefix(limit) {
            do {
                let confirmed = try await measurePreference(mode: AVAudioSession.Mode(rawValue: candidate.mode),
                    rate: candidate.requestedSampleRate ?? candidate.sampleRate,
                    request: candidate.requestedFrames, token: token, key: key)
                bufferMeasurements.append(confirmed)
                if confirmed.reproduces(candidate) {
                    let floor = BufferPreferenceSelector.observedFloor(bufferMeasurements, mode: confirmed.mode,
                        sampleRate: confirmed.sampleRate, maximumScore: confirmed.score + confirmed.comparisonTolerance)
                    let measurements = modes.compactMap { mode in
                        BufferPreferenceSelector.best(bufferMeasurements.filter { $0.mode == mode.rawValue })?.latencyMeasurement
                    }
                    finishPreference(confirmed, floor: floor, modes: measurements, key: key)
                    return // Keep this verified, muted Audio Unit; do not reconfigure it after selection.
                }
            } catch is CancellationError { throw CancellationError() }
            catch MonitorError.routeChanged { throw MonitorError.routeChanged }
            catch { logger.info("Selected preference could not be reproduced") }
            audio.stop()
        }
        throw MonitorError.noStableMode
    }

    private func finishPreference(_ observed: BufferPreferenceMeasurement, floor: Double?, modes: [ModeLatencyMeasurement], key: String, cacheable: Bool = true) {
        verifiedPreference = observed
        verifiedPreferenceKey = key
        needsForegroundProbe = !cacheable
        minimumObservedSampleRate = observed.sampleRate
        minimumObservedFrames = floor
        modeMeasurements = modes
        if cacheable { preferenceCache.put(.init(measurement: observed, floor: floor, modes: modes), for: key) }
        if effectiveModePreference == .automatic { modeCache[modeCacheKey] = modes }
        tuner.resetObservedFloor() // Replace the old floor, while preserving failed-retry backoff.
        latencyReprobe.didProbe(now: ProcessInfo.processInfo.systemUptime)
        tuningNote = String(localized: "latency.tuning.selected", defaultValue: "自動 · 実コールバックを比較して\(String(format: "%.6g", locale: .current, requestedFrames))フレームを要求")
    }

    private func requestBuffer(sampleRate: Double) throws {
        if usesManualIO {
            try session.setPreferredIOBufferDuration(Double(activeManualAudio.frames) / sampleRate)
            appliedBufferRequest = Double(activeManualAudio.frames)
            return
        }
        var lastError: Error?
        for frames in [requestedFrames, 16, 32, 64, 128, 256, 512, 1024, 2048] where frames >= requestedFrames {
            do {
                try session.setPreferredIOBufferDuration(frames / max(sampleRate, 8_000))
                appliedBufferRequest = frames
                return
            } catch { lastError = error }
        }
        if let lastError { throw lastError }
    }

    private func startTuning() {
        tuningTask?.cancel()
        tuningTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, isRunning else { return }
                let error = audio.renderError
                guard error == 0 || error == kAudioUnitErr_CannotDoInCurrentContext else {
                    stop(message: String(localized: "monitor.error.audio_stopped", defaultValue: "音声処理が停止しました（\(error)）。接続を確認してください。")); return
                }
                if usesManualIO {
                    if error != 0 {
                        stop(message: String(localized: "monitor.error.unstable_input", defaultValue: "この接続では安定した音声入力を確保できませんでした")); return
                    }
                    continue // Observe health, but never change manual frames/rate/mode.
                }
                if needsForegroundProbe, !inBackground, diagnosticFrameOverride == nil {
                    retune(to: requestedFrames, reprobeMinimum: true)
                    return
                }
                if effectiveModePreference == .automatic,
                   latencyReprobe.evaluate(now: ProcessInfo.processInfo.systemUptime, current: currentLatencyMeasurement(),
                       misses: audio.missedQuanta, allowed: !inBackground && error == 0) {
                    retune(to: 1, reprobeMinimum: true)
                    return
                }
                let actual = BufferPreferenceSelector.effectiveFrames(quantum: audio.currentQuantum, duration: session.ioBufferDuration, sampleRate: session.sampleRate)
                if let candidate = tuner.evaluate(now: ProcessInfo.processInfo.systemUptime,
                    actualFrames: actual, sampleRate: session.sampleRate,
                    misses: audio.missedQuanta, transientFailure: error != 0, allowMinimumReprobe: !inBackground) {
                    let next = BufferPreferenceSelector.recoveryRequest(candidate, sampleRate: session.sampleRate, preferred: verifiedPreference)
                    let reprobe = (next == requestedFrames || next == 1) && !inBackground && diagnosticFrameOverride == nil
                    retune(to: next, reprobeMinimum: reprobe)
                    return
                } else if error != 0 {
                    stop(message: String(localized: "monitor.error.unstable_input", defaultValue: "この接続では安定した音声入力を確保できませんでした")); return
                }
            }
        }
    }

    private func retune(to frames: Double, reprobeMinimum: Bool = false) {
        audio.closeGate()
        audio.analysisEnabled = false; spectrumAnalyzer.stop()
        captureCounters(); writeDiagnostics()
        tuningTask?.cancel()
        meter?.invalidate(); meter = nil
        renderedFrameOffset += audio.renderedFrames
        missedQuantumOffset += audio.missedQuanta
        audio.stop()
        isRunning = false
        requestedFrames = frames
        tuningNote = usesManualIO ? String(localized: "audio.mode.manual", defaultValue: "完全手動") : String(localized: "latency.tuning.adjusting", defaultValue: "自動調整 · \(String(format: "%.6g", locale: .current, frames))フレームを要求")
        // Keep the audio session active, including while in the background.
        start(resetTuning: false, reprobeMinimum: reprobeMinimum)
    }

    func stop(message: String = String(localized: "monitor.status.stopped", defaultValue: "モニターを停止しました")) {
        audio.closeGate()
        audio.analysisEnabled = false; spectrumAnalyzer.stop()
        interruptionResume = nil
        if isRunning {
            if inBackground {
                backgroundFrames = (renderedFrameOffset + audio.renderedFrames) &- backgroundStartFrame
                backgroundSeconds = ProcessInfo.processInfo.systemUptime - backgroundStartTime
            }
            captureCounters(); writeDiagnostics()
        }
        generation += 1
        pendingManualAudio = nil; isApplyingManual = false
        transition?.cancel()
        transition = nil
        configuring = false
        audio.stop()
        tuningTask?.cancel(); tuningTask = nil
        meter?.invalidate(); meter = nil
        isRunning = false
        isStarting = false
        peak = 0
        tapGateOpen = false
        status = message
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        logger.info("stopped: \(message, privacy: .public)")
    }

    private func fail(_ error: Error) {
        stop(message: String(localized: "monitor.error.start", defaultValue: "開始できませんでした：\(error.localizedDescription)"))
        writeDiagnostics()
        #if DEBUG
        print("MicRelay diagnostic failure: \(error)")
        #endif
    }

    private func routeChanged(reason: UInt, previousIDs: [String]) {
        if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
            confirmedOutputs.subtract(previousIDs)
            stop(message: String(localized: "monitor.status.disconnected", defaultValue: "接続が外れたため停止しました。再接続して開始してください。"))
            refreshRoute()
            return
        }
        refreshRoute()
        if configuring { return }
        guard isRunning else { return }
        if canMonitor, Set(outputs.map(\.uid)) == runningOutputIDs,
           session.currentRoute.inputs.first?.uid == runningInputID {
            // Another app can change the shared sample rate/buffer without changing devices.
            tuner = BufferTuner()
            retune(to: usesManualIO ? Double(manualAudio.frames) : (verifiedPreference?.requestedFrames ?? 1))
            return
        }
        stop(message: String(localized: "monitor.status.route_changed", defaultValue: "音声の接続が変わったため停止しました。確認して開始してください。"))
    }

    private func interrupted(type: UInt, options: UInt) {
        if type == AVAudioSession.InterruptionType.began.rawValue {
            let resume = isRunning ? (runningOutputIDs, selectedInput) : nil
            stop(message: String(localized: "monitor.status.interrupted", defaultValue: "他のアプリの音声により中断しました"))
            if let resume { interruptionResume = (resume.0, resume.1) }
        } else if let resume = interruptionResume {
            interruptionResume = nil
            refreshRoute()
            if options & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0,
               Set(outputs.map(\.uid)) == resume.outputs, selectedInput == resume.input, canStart {
                start()
            }
        }
    }

    func refreshRoute() {
        outputs = session.currentRoute.outputs.map { OutputPort(uid: $0.uid, type: $0.portType, name: $0.portName) }
        // Confirmation is valid only while this exact output remains connected.
        if !configuring { confirmedOutputs.formIntersection(Set(outputs.map(\.uid))) }
        activeInput = ListFormatter.localizedString(byJoining: session.currentRoute.inputs.map(\.portName))
        if activeInput.isEmpty { activeInput = String(localized: "microphone.unused", defaultValue: "未使用") }
        var choices = [MicrophoneChoice(id: "builtin", name: String(localized: "microphone.built_in", defaultValue: "本体マイク"), detail: String(localized: "microphone.built_in.detail", defaultValue: "このiPhone / iPadのマイク"), icon: "iphone")]
        for port in session.availableInputs ?? [] where port.portType != .builtInMic {
            choices.append(MicrophoneChoice(id: port.uid, name: port.portName,
                detail: port.portType == .bluetoothHFP ? String(localized: "microphone.bluetooth.detail", defaultValue: "Bluetooth通話用マイク") : String(localized: "microphone.external.detail", defaultValue: "外部マイク"), icon: "headphones"))
        }
        microphones = choices
        sampleRate = session.sampleRate
        bufferDuration = session.ioBufferDuration
        inputLatency = session.inputLatency
        outputLatency = session.outputLatency
        unitProcessingLatency = audio.processingLatency?.doubleValue
    }

    func sceneChanged(_ phase: ScenePhase) {
        if phase == .background {
            inBackground = true
            audio.analysisEnabled = false; spectrumAnalyzer.stop()
            backgroundStartFrame = renderedFrameOffset + audio.renderedFrames
            backgroundStartTime = ProcessInfo.processInfo.systemUptime
            meter?.invalidate(); meter = nil
            if !backgroundEnabled { stop(message: String(localized: "monitor.status.background_stopped", defaultValue: "バックグラウンドに移ったため停止しました")) }
            logger.info("background monitoring=\(self.isRunning)")
        } else if phase == .active {
            if inBackground && isRunning {
                backgroundFrames = (renderedFrameOffset + audio.renderedFrames) &- backgroundStartFrame
                backgroundSeconds = ProcessInfo.processInfo.systemUptime - backgroundStartTime
                captureCounters()
                writeDiagnostics()
            }
            inBackground = false
            if isRunning { startMeter() }
            startSpectrumIfNeeded()
            refreshRoute()
            if isRunning && (!canMonitor || (audio.renderError != 0 && audio.renderError != kAudioUnitErr_CannotDoInCurrentContext)) {
                stop(message: String(localized: "monitor.status.check_connection", defaultValue: "音声の接続を確認して開始してください"))
            }
        }
    }

    private func startMeter() {
        meter?.invalidate()
        meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isRunning else { return }
                peak = max(audio.peak, peak * 0.65)
                captureCounters()
                var nextWaveform = [Float](repeating: 0, count: 128)
                nextWaveform.withUnsafeMutableBufferPointer { buffer in
                    _ = self.audio.readWaveform(buffer.baseAddress!, capacity: UInt(buffer.count))
                }
                waveform = nextWaveform
            }
        }
    }

    private func captureCounters() {
        frames = renderedFrameOffset + audio.renderedFrames
        maximumInputPeak = max(maximumInputPeak, audio.maximumInputPeak)
        maximumOutputPeak = max(maximumOutputPeak, audio.maximumOutputPeak)
        renderError = audio.renderError
        missedQuanta = missedQuantumOffset + audio.missedQuanta
        minimumQuantum = audio.minimumQuantum
        maximumQuantum = audio.maximumQuantum
        sampleRate = session.sampleRate
        bufferDuration = session.ioBufferDuration
        inputLatency = session.inputLatency
        outputLatency = session.outputLatency
        unitProcessingLatency = audio.processingLatency?.doubleValue
        tapGateOpen = audio.tapGateOpen
        tapGateDetections = audio.tapGateDetections
    }

    private func writeDiagnostics() {
        #if DEBUG
        let values: [String: Any] = [
            "status": status, "isRunning": isRunning, "isStarting": isStarting,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "sampleRate": sampleRate, "ioBufferDuration": bufferDuration,
            "manualIO": usesManualIO, "manualFrames": manualAudio.frames, "manualRate": manualAudio.sampleRate,
            "requestedSampleRate": preferredHardwareSampleRate, "mode": session.mode.rawValue,
            "categoryOptions": session.categoryOptions.rawValue,
            "remoteIO": audio.ioConfiguration,
            "preferredIOBufferDuration": session.preferredIOBufferDuration,
            "appliedBufferRequest": appliedBufferRequest,
            "inputChannels": session.inputNumberOfChannels, "outputChannels": session.outputNumberOfChannels,
            "diagnosticExclusiveAudio": diagnosticExclusiveAudio, "diagnosticColdSession": diagnosticColdSession,
            "diagnosticRunID": diagnosticRunID,
            "diagnosticAutomaticAudio": diagnosticAutomaticAudio,
            "diagnosticMutedOutput": diagnosticMutedOutput,
            "probeAttempts": probeAttempts, "probeSeconds": lastProbeSeconds,
            "probeUsedCache": lastProbeUsedCache,
            "startSeconds": lastStartSeconds,
            "currentQuantum": audio.currentQuantum,
            "bufferCandidates": bufferMeasurements.map { ["requestedFrames": $0.requestedFrames,
                "requestedSampleRate": $0.requestedSampleRate ?? 0,
                "mode": $0.mode,
                "observationDuration": $0.observationDuration,
                "actualFrames": $0.actualFrames, "sampleRate": $0.sampleRate, "ioBufferDuration": $0.ioBufferDuration,
                "inputLatency": $0.inputLatency, "outputLatency": $0.outputLatency, "processingLatency": $0.processingLatency.map { $0 as Any } ?? NSNull(), "missedQuanta": $0.missedQuanta,
                "renderedFrames": $0.renderedFrames, "renderError": $0.renderError, "stable": $0.isStable] as [String: Any] },
            "gain": gain,
            "gainLimit": gainLimit,
            "windNoiseEnabled": windNoise.enabled, "windNoiseCutoff": windNoise.cutoff,
            "tapGateEnabled": tapGate.enabled, "tapGateDuration": tapGate.duration,
            "tapGateMinimumDB": tapGate.minimumDB, "tapGateRiseDB": tapGate.riseDB,
            "tapGateDetectionSource": tapGate.detectionSource.rawValue,
            "tapGateDetections": tapGateDetections, "tapGateOpen": tapGateOpen,
            "equalizerEnabled": equalizer.enabled, "spectrumFrames": spectrumFrameCount,
            "analysisDroppedFrames": audio.analysisDroppedFrames,
            "modeCandidates": modeMeasurements.map { ["mode": $0.mode, "inputLatency": $0.inputLatency,
                "outputLatency": $0.outputLatency, "processingLatency": $0.processingLatency.map { $0 as Any } ?? NSNull(), "ioBufferDuration": $0.ioBufferDuration,
                "sampleRate": $0.sampleRate, "quantum": $0.quantum, "score": $0.score] as [String: Any] },
            "inputLatency": inputLatency, "outputLatency": outputLatency,
            "input": activeInput, "output": outputName,
            "inputPortTypes": session.currentRoute.inputs.map { $0.portType.rawValue },
            "outputPortTypes": session.currentRoute.outputs.map { $0.portType.rawValue },
            "availableInputs": (session.availableInputs ?? []).map { ["name": $0.portName, "type": $0.portType.rawValue] },
            "renderedFrames": frames, "maximumInputPeak": maximumInputPeak,
            "maximumOutputPeak": maximumOutputPeak, "renderError": renderError,
            "missedQuanta": missedQuanta, "backgroundFrames": backgroundFrames,
            "backgroundSeconds": backgroundSeconds
            , "requestedFrames": requestedFrames, "minimumQuantum": minimumQuantum,
            "maximumQuantum": maximumQuantum, "callbackCount": audio.callbackCount
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]),
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: directory.appendingPathComponent("diagnostics.json"), options: .atomic)
        }
        #endif
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: String(localized: "now_playing.title", defaultValue: "マイクをモニター中"),
            MPMediaItemPropertyArtist: "MicRelay · \(activeInput)",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
    }
}

private enum MonitorError: LocalizedError {
    case inputUnavailable
    case noStableMode
    case routeChanged
    var errorDescription: String? {
        switch self {
        case .inputUnavailable: return String(localized: "monitor.error.input_unavailable", defaultValue: "選んだマイクまたは出力先が利用できません。接続を確認してください。")
        case .noStableMode: return String(localized: "monitor.error.no_stable_mode", defaultValue: "この接続で安定する音声設定を見つけられませんでした。")
        case .routeChanged: return String(localized: "monitor.status.route_changed", defaultValue: "音声の接続が変わったため停止しました。確認して開始してください。")
        }
    }
}
