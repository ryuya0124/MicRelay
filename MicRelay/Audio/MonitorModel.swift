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
    @Published private(set) var spectrum: SpectrumFrame?
    @Published private(set) var spectrumFrameCount: UInt64 = 0
    @Published private(set) var speakerEnabled = false
    @Published var backgroundEnabled = true {
        didSet { UserDefaults.standard.set(backgroundEnabled, forKey: "backgroundEnabled") }
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
    private var minimumObservedFrames: Double?
    private let spectrumAnalyzer = SpectrumAnalyzer()
    private var spectrumVisible = false
    private var diagnosticProcessingSettings = false

    func startDiagnosticIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard !didRunDiagnostic, arguments.contains("--validate-speaker") || arguments.contains("--validate-headphones") else { return }
        didRunDiagnostic = true
        diagnosticHeadphones = arguments.contains("--validate-headphones")
        diagnosticAccessoryMic = arguments.contains("--validate-accessory-mic")
        diagnosticExclusiveAudio = arguments.contains("--exclusive-audio")
        diagnosticColdSession = arguments.contains("--cold-session")
        diagnosticAutomaticAudio = arguments.contains("--automatic-mode")
        if arguments.contains("--adopt-automatic-mode") { modePreference = .automatic }
        diagnosticRunID = arguments.first(where: { $0.hasPrefix("--diagnostic-id=") }).map { String($0.dropFirst("--diagnostic-id=".count).prefix(64)) } ?? ""
        let diagnosticSeconds = arguments.first(where: { $0.hasPrefix("--diagnostic-seconds=") })
            .flatMap { Double($0.dropFirst("--diagnostic-seconds=".count)) }.map { min(120, max(0, $0)) } ?? 45
        if let argument = arguments.first(where: { $0.hasPrefix("--sample-rate=") }),
           let rate = Double(argument.split(separator: "=").last ?? ""), [44_100, 48_000, 96_000].contains(rate) {
            preferredHardwareSampleRate = rate
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
        canMonitor || (speakerEnabled && !outputs.isEmpty && outputs.allSatisfy { $0.type == .builtInReceiver })
    }
    var isSpeaker: Bool { outputs.contains { $0.type == .builtInSpeaker } }
    var unconfirmedOutputs: [OutputPort] {
        outputs.filter { OutputSafety.needsConfirmation($0) && !confirmedOutputs.contains($0.uid) }
    }
    var outputName: String { ListFormatter.localizedString(byJoining: outputs.map(\.name)) }
    var isWireless: Bool { outputs.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.type) } }
    var reportedLatency: Double { inputLatency + outputLatency + bufferDuration }

    init() {
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
        if UserDefaults.standard.object(forKey: "backgroundEnabled") != nil {
            backgroundEnabled = UserDefaults.standard.bool(forKey: "backgroundEnabled")
        }
        permissionGranted = AVAudioApplication.shared.recordPermission == .granted
        permissionDenied = AVAudioApplication.shared.recordPermission == .denied
        refreshRoute()
        applyEqualizer()
        applyWindNoise()
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
            backgroundEnabled: backgroundEnabled, selectedInput: selectedInput, audioMode: modePreference, windNoise: windNoise)
    }

    func restoreSettings(_ backup: SettingsBackup) throws -> Bool {
        let value = try backup.validated()
        stop(message: String(localized: "monitor.status.restored", defaultValue: "設定を復元しました。モニターの再開は手動です"))
        MonitorPreferences.saveGainLimit(value.gainLimit)
        gainLimit = value.gainLimit
        gain = value.gain
        equalizer = value.equalizer
        windNoise = value.windNoise ?? .init()
        backgroundEnabled = value.backgroundEnabled
        modePreference = value.audioMode ?? .automatic
        let available = value.selectedInput == "builtin" || microphones.contains { $0.id == value.selectedInput }
        selectedInput = available ? value.selectedInput : "builtin"
        return available
    }

    func selectAudioMode(_ mode: AudioModePreference) {
        guard mode != modePreference else { return }
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

    func start(resetTuning: Bool = true, reprobeMinimum: Bool = false) {
        guard !isStarting && !isRunning else { return }
        if resetTuning {
            tuner = BufferTuner()
            requestedFrames = diagnosticFrameOverride ?? 1
            tuningNote = String(localized: "latency.tuning.initial", defaultValue: "自動 · 接続先の最小バッファを使用")
            renderedFrameOffset = 0; missedQuantumOffset = 0
            maximumInputPeak = 0; maximumOutputPeak = 0
            backgroundFrames = 0; backgroundSeconds = 0
            bufferMeasurements = []; minimumObservedFrames = nil
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
                let preference: AudioModePreference = diagnosticAutomaticAudio ? .automatic : modePreference
                if (resetTuning || reprobeMinimum) && diagnosticModeOverride == nil { monitoringMode = preference.sessionMode }
                try configureSession()
                try await Task.sleep(for: .milliseconds(250))
                guard token == generation, !Task.isCancelled else { return }
                try validateActiveRoute()
                let probeBuffers = (resetTuning || reprobeMinimum) && diagnosticFrameOverride == nil && !inBackground
                if (resetTuning || reprobeMinimum) && diagnosticModeOverride == nil && preference == .automatic && !probeBuffers { try await chooseLatencyMode(token: token) }
                selectedModeLabel = monitoringMode == .measurement ? String(localized: "audio.mode.measurement", defaultValue: "測定") : String(localized: "audio.mode.standard", defaultValue: "標準")
                if probeBuffers {
                    try await chooseBufferPreference(token: token)
                    selectedModeLabel = monitoringMode == .measurement ? String(localized: "audio.mode.measurement", defaultValue: "測定") : String(localized: "audio.mode.standard", defaultValue: "標準")
                }
                guard !inBackground || backgroundEnabled else { stop(); return }
                try audio.prepare(withSampleRate: session.sampleRate)
                // Read the route again after AudioUnit initialization, before opening the gate.
                refreshRoute()
                guard canMonitor else { stop(message: String(localized: "monitor.status.no_output", defaultValue: "対応する出力先が接続されていないため停止しました")); return }
                updateGain()
                applyEqualizer()
                applyWindNoise()
                try audio.start()
                configuring = false
                isStarting = false
                isRunning = true
                runningOutputIDs = Set(session.currentRoute.outputs.map(\.uid))
                runningInputID = session.currentRoute.inputs.first?.uid
                if inBackground && resetTuning {
                    backgroundStartFrame = renderedFrameOffset + audio.renderedFrames
                    backgroundStartTime = ProcessInfo.processInfo.systemUptime
                }
                if !inBackground { startMeter() }
                startSpectrumIfNeeded()
                tuner.didStart(now: ProcessInfo.processInfo.systemUptime, actualFrames: session.ioBufferDuration * session.sampleRate,
                    minimumObservedFrames: minimumObservedFrames)
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
            } catch {
                if token == generation { fail(error) }
            }
        }
    }

    private func validateActiveRoute() throws {
        refreshRoute()
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
                // Compare active hardware paths without changing the saved/user-facing gain.
                audio.gain = 0
                try audio.start()
                try await Task.sleep(for: .milliseconds(200))
                guard token == generation, !Task.isCancelled else { throw CancellationError() }
                try validateActiveRoute()
                if audio.renderedFrames > 0, audio.renderError == 0 {
                    measurements.append(ModeLatencyMeasurement(mode: mode.rawValue,
                        inputLatency: session.inputLatency, outputLatency: session.outputLatency,
                        ioBufferDuration: session.ioBufferDuration, sampleRate: session.sampleRate,
                        quantum: audio.minimumQuantum))
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
        if diagnosticColdSession { try session.setActive(false) }
        // Keep monitoring alongside games/music; the OS negotiates the shared hardware buffer.
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        if !diagnosticExclusiveAudio { options.insert(.mixWithOthers) }
        try session.setCategory(.playAndRecord, mode: monitoringMode, options: options)
        try session.setPrefersInterruptionOnRouteDisconnect(true)
        try? session.setPreferredSampleRate(preferredHardwareSampleRate)
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

    private func chooseBufferPreference(token: Int) async throws {
        status = String(localized: "latency.tuning.probing", defaultValue: "最小I/Oを確認中…")
        let previousRequest = requestedFrames
        let previousMode = monitoringMode
        let automatic = (diagnosticAutomaticAudio || modePreference == .automatic) && diagnosticModeOverride == nil
        let modes = automatic ? [AVAudioSession.Mode.default, .measurement] : [monitoringMode]
        bufferMeasurements = []
        for mode in modes {
        monitoringMode = mode
        for request in BufferPreferenceSelector.requests {
            guard token == generation, !Task.isCancelled, !inBackground else { throw CancellationError() }
            audio.stop()
            // Set preferences while inactive so an accepted-but-ignored request is not mistaken for a floor.
            try session.setActive(false)
            requestedFrames = request
            do {
                try configureSession()
                try await Task.sleep(for: .milliseconds(100))
                guard token == generation, !Task.isCancelled else { throw CancellationError() }
                try validateActiveRoute()
                try audio.prepare(withSampleRate: session.sampleRate)
                audio.setEqualizerEnabled(false, bands: equalizer.bands.map(\.native))
                audio.setWindNoiseEnabled(false, cutoff: windNoise.cutoff)
                audio.gain = 0 // The saved gain and EQ are untouched throughout probing.
                try audio.start()
                try await Task.sleep(for: .milliseconds(100))
                guard token == generation, !Task.isCancelled else { throw CancellationError() }
                try validateActiveRoute()
                // Our session changes can post a late safety-gate notification. Reopen only after validating this exact route.
                try audio.start()
                let initialMisses = audio.missedQuanta, initialFrames = audio.renderedFrames
                let observationStart = ProcessInfo.processInfo.systemUptime
                let observationSeconds = max(0.16, 8 * max(session.ioBufferDuration, Double(audio.currentQuantum) / session.sampleRate))
                try await Task.sleep(for: .seconds(observationSeconds))
                guard token == generation, !Task.isCancelled else { throw CancellationError() }
                try validateActiveRoute()
                let measurement = BufferPreferenceMeasurement(requestedFrames: request,
                    actualFrames: audio.currentQuantum, sampleRate: session.sampleRate,
                    ioBufferDuration: session.ioBufferDuration, inputLatency: session.inputLatency,
                    outputLatency: session.outputLatency, missedQuanta: audio.missedQuanta &- initialMisses,
                    renderedFrames: audio.renderedFrames &- initialFrames, renderError: audio.renderError, mode: monitoringMode.rawValue,
                    observationDuration: ProcessInfo.processInfo.systemUptime - observationStart)
                bufferMeasurements.append(measurement)
                if measurement.isStable && measurement.matchesRequest {
                    // Smaller candidates have already been tested. Larger requests cannot beat this accepted stable quantum.
                    audio.stop()
                    break
                }
            } catch is CancellationError { throw CancellationError() }
            catch { logger.info("Buffer preference unavailable: \(request)") }
            audio.stop()
        }
        }
        let best = BufferPreferenceSelector.best(bufferMeasurements)
        requestedFrames = best?.requestedFrames ?? previousRequest
        monitoringMode = best.map { AVAudioSession.Mode(rawValue: $0.mode) } ?? previousMode
        modeMeasurements = modes.compactMap { mode in
            guard let choice = BufferPreferenceSelector.best(bufferMeasurements.filter { $0.mode == mode.rawValue }) else { return nil }
            return ModeLatencyMeasurement(mode: mode.rawValue, inputLatency: choice.inputLatency,
                outputLatency: choice.outputLatency, ioBufferDuration: choice.ioBufferDuration,
                sampleRate: choice.sampleRate, quantum: choice.actualFrames)
        }
        minimumObservedFrames = bufferMeasurements.filter { $0.mode == monitoringMode.rawValue && $0.actualFrames > 0 && $0.renderedFrames > 0 && $0.sampleRate > 0 }
            .map { max(Double($0.actualFrames), $0.ioBufferDuration * $0.sampleRate) }.min()
        try session.setActive(false)
        try configureSession()
        try await Task.sleep(for: .milliseconds(100))
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try validateActiveRoute()
        tuningNote = String(localized: "latency.tuning.selected", defaultValue: "自動 · 実コールバックを比較して\(Int(requestedFrames))フレームを要求")
    }

    private func requestBuffer(sampleRate: Double) throws {
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
                let actual = max(Double(audio.currentQuantum), session.ioBufferDuration * session.sampleRate)
                if let next = tuner.evaluate(now: ProcessInfo.processInfo.systemUptime,
                    actualFrames: actual, sampleRate: session.sampleRate,
                    misses: audio.missedQuanta, transientFailure: error != 0, allowMinimumReprobe: !inBackground) {
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
        tuningNote = String(localized: "latency.tuning.adjusting", defaultValue: "自動調整 · \(Int(frames))フレームを要求")
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
        transition?.cancel()
        transition = nil
        configuring = false
        audio.stop()
        tuningTask?.cancel(); tuningTask = nil
        meter?.invalidate(); meter = nil
        isRunning = false
        isStarting = false
        peak = 0
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
            retune(to: 1)
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
                waveform = audio.waveform().map(\.floatValue)
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
    }

    private func writeDiagnostics() {
        #if DEBUG
        let values: [String: Any] = [
            "status": status, "isRunning": isRunning, "isStarting": isStarting,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "sampleRate": sampleRate, "ioBufferDuration": bufferDuration,
            "requestedSampleRate": preferredHardwareSampleRate, "mode": session.mode.rawValue,
            "categoryOptions": session.categoryOptions.rawValue,
            "preferredIOBufferDuration": session.preferredIOBufferDuration,
            "appliedBufferRequest": appliedBufferRequest,
            "inputChannels": session.inputNumberOfChannels, "outputChannels": session.outputNumberOfChannels,
            "diagnosticExclusiveAudio": diagnosticExclusiveAudio, "diagnosticColdSession": diagnosticColdSession,
            "diagnosticRunID": diagnosticRunID,
            "diagnosticAutomaticAudio": diagnosticAutomaticAudio,
            "currentQuantum": audio.currentQuantum,
            "bufferCandidates": bufferMeasurements.map { ["requestedFrames": $0.requestedFrames,
                "mode": $0.mode,
                "observationDuration": $0.observationDuration,
                "actualFrames": $0.actualFrames, "sampleRate": $0.sampleRate, "ioBufferDuration": $0.ioBufferDuration,
                "inputLatency": $0.inputLatency, "outputLatency": $0.outputLatency, "missedQuanta": $0.missedQuanta,
                "renderedFrames": $0.renderedFrames, "renderError": $0.renderError, "stable": $0.isStable] as [String: Any] },
            "gain": gain,
            "gainLimit": gainLimit,
            "windNoiseEnabled": windNoise.enabled, "windNoiseCutoff": windNoise.cutoff,
            "equalizerEnabled": equalizer.enabled, "spectrumFrames": spectrumFrameCount,
            "analysisDroppedFrames": audio.analysisDroppedFrames,
            "modeCandidates": modeMeasurements.map { ["mode": $0.mode, "inputLatency": $0.inputLatency,
                "outputLatency": $0.outputLatency, "ioBufferDuration": $0.ioBufferDuration,
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
    var errorDescription: String? {
        switch self {
        case .inputUnavailable: return String(localized: "monitor.error.input_unavailable", defaultValue: "選んだマイクまたは出力先が利用できません。接続を確認してください。")
        case .noStableMode: return String(localized: "monitor.error.no_stable_mode", defaultValue: "この接続で安定する音声設定を見つけられませんでした。")
        }
    }
}
