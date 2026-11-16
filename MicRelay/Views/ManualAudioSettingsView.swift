// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import SwiftUI

struct ManualAudioSettingsView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.dismiss) private var dismiss
    @State private var frames: UInt32 = 16
    @State private var sampleRate: Double = 48000
    @State private var mode: AudioModePreference = .standard
    @State private var errorMessage: String?
    @State private var applying: Task<Void, Never>?
    var body: some View {
        Form {
            Section {
                Picker(String(localized: "audio.mode.title", defaultValue: "音声モード"), selection: $mode) {
                    Text(AudioModePreference.standard.title).tag(AudioModePreference.standard)
                    Text(AudioModePreference.measurement.title).tag(AudioModePreference.measurement)
                }.accessibilityIdentifier("manualModePicker")
                Picker(String(localized: "manual.frames", defaultValue: "フレーム数"), selection: $frames) {
                    ForEach(model.manualAudio.frameOptions, id: \.self) { value in
                        Text("\(value) frames").tag(value).accessibilityIdentifier("manualFramesPreset\(value)")
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("manualFramesPicker")
                Picker(String(localized: "manual.rate", defaultValue: "サンプルレート（Hz）"), selection: $sampleRate) {
                    ForEach(model.manualAudio.sampleRateOptions, id: \.self) { value in
                        Text("\(String(format: "%.9g", locale: .current, value)) Hz").tag(value).accessibilityIdentifier("manualRatePreset\(String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value))")
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("manualRatePicker")
            } footer: {
                Text(String(localized: "manual.help", defaultValue: "自動調整は行いません。無音で動作を確認し、要求どおりに適用できた場合だけ保存します。適用できない場合は元の設定へ戻します。"))
            }.disabled(model.isApplyingManual)
            if model.isApplyingManual {
                Section { ProgressView(String(localized: "manual.checking", defaultValue: "無音で適用を確認中…")) }
            } else {
                Section { ManualAudioStatusView(model: model) }
            }
            Section {
                Button(String(localized: "manual.apply", defaultValue: "確認して適用")) {
                    let value = ManualAudioSettings(frames: frames, sampleRate: sampleRate, mode: mode)
                    applying = Task {
                        let succeeded = await model.applyManualAudio(value)
                        guard !Task.isCancelled else { return }
                        if succeeded { dismiss() }
                        else {
                            reloadSelections()
                            errorMessage = model.manualApplyError ?? String(localized: "manual.error.rollback", defaultValue: "\(model.status) 元の設定に戻しました。")
                        }
                    }
                }.disabled(model.isApplyingManual || model.isStarting).accessibilityIdentifier("applyManualAudio")
            }
        }
        .navigationTitle(String(localized: "manual.title", defaultValue: "手動I/O設定"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadSelections() }
        .onDisappear { applying?.cancel() }
        .alert(String(localized: "manual.error.title", defaultValue: "設定を適用できませんでした"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok", defaultValue: "OK")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    private func reloadSelections() {
        frames = model.manualAudio.frames
        sampleRate = model.manualAudio.sampleRate
        mode = model.manualAudio.mode
    }
}

struct ManualAudioStatusView: View {
    @ObservedObject var model: MonitorModel
    var body: some View {
        let live = model.isRunning && model.modePreference == .manual
        let observation = model.lastManualObservation.flatMap { $0.request == model.manualAudio ? $0 : nil }
        let state: ManualIOApplication.State = model.isStarting && model.usesManualIO ? .pending : live ? model.manualApplication.state : (observation?.accepted == true ? .matched : .inactive)
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(String(localized: "manual.status", defaultValue: "適用確認")) {
                Label(statusLabel(state), systemImage: state == .matched ? "checkmark.circle.fill" : state == .different ? "exclamationmark.triangle.fill" : "clock")
                    .foregroundStyle(state == .matched ? Color.green : state == .different ? .orange : .secondary)
                    .accessibilityIdentifier("manualApplicationStatus")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow { Text(""); Text(String(localized: "manual.requested", defaultValue: "要求値")); Text(String(localized: "manual.actual", defaultValue: "実際の値")) }
                GridRow {
                    Text(String(localized: "manual.frames", defaultValue: "フレーム数"))
                    Text("\(model.manualAudio.frames)")
                    Text(live ? "\(model.minimumQuantum)–\(model.maximumQuantum)" : observation.map { "\($0.minimumFrames)–\($0.maximumFrames)" } ?? "—")
                }
                GridRow {
                    Text(String(localized: "manual.rate_short", defaultValue: "サンプルレート"))
                    Text("\(String(format: "%.9g", locale: .current, model.manualAudio.sampleRate)) Hz")
                    Text((live ? model.sampleRate : observation?.sampleRate).map { "\(String(format: "%.9g", locale: .current, $0)) Hz" } ?? "—")
                }
                GridRow {
                    Text(String(localized: "latency.io_buffer", defaultValue: "I/Oバッファ"))
                    Text(ManualAudioSettings.durationLabel(model.manualAudio.bufferDuration))
                    Text((live ? model.bufferDuration : observation?.ioDuration).map(ManualAudioSettings.durationLabel) ?? "—")
                }
                GridRow {
                    Text(String(localized: "audio.mode.title", defaultValue: "音声モード"))
                    Text(model.manualAudio.mode.title)
                    Text((live ? model.actualSessionMode : observation?.mode)?.title ?? "—")
                }
            }.font(.caption).monospacedDigit()
            if !live && observation != nil {
                Text(String(localized: "manual.last_result", defaultValue: "設定時の確認結果です。モニター中は現在の実値を表示します。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func statusLabel(_ state: ManualIOApplication.State) -> String {
        switch state {
        case .inactive: return String(localized: "manual.unverified", defaultValue: "未確認")
        case .pending: return String(localized: "manual.checking", defaultValue: "無音で適用を確認中…")
        case .matched: return String(localized: "manual.matched", defaultValue: "要求どおり")
        case .different: return String(localized: "manual.different", defaultValue: "要求と異なる値")
        }
    }
}
