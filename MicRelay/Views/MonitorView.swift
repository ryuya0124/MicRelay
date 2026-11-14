// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import SwiftUI
import AVKit
import MediaPlayer

struct MonitorView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.openURL) private var openURL
    @State private var diagnosticsExpanded = ProcessInfo.processInfo.arguments.contains("--expand-diagnostics")
    @State private var showsLicense = ProcessInfo.processInfo.arguments.contains("--show-licenses")
    @State private var showsGainSettings = ProcessInfo.processInfo.arguments.contains("--show-gain-settings")
    @State private var showsEqualizer = ProcessInfo.processInfo.arguments.contains("--show-equalizer")
    @State private var showsBackup = false

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HStack(spacing: 0) {
                    Form { controls; latency }.frame(maxWidth: .infinity)
                    Form { connections; licenses }.frame(maxWidth: .infinity)
                }
            } else {
                Form { controls; connections; latency; licenses }
            }

        }
        .navigationTitle("MicRelay")
        .navigationDestination(isPresented: $showsLicense) { LicenseView() }
        .navigationDestination(isPresented: $showsEqualizer) { EqualizerView(model: model) }
        .navigationDestination(isPresented: $showsBackup) { SettingsBackupView(model: model) }
        .sheet(isPresented: $showsGainSettings) { GainSettingsView(model: model) }
        .task {
            #if DEBUG
            showsBackup = ProcessInfo.processInfo.arguments.contains("--show-backup")
            #endif
        }
    }
    @ViewBuilder private var controls: some View {
            Section {
                Picker(String(localized: "audio.mode.title", defaultValue: "音声モード"), selection: Binding(get: { model.modePreference }, set: model.selectAudioMode)) {
                    ForEach(AudioModePreference.allCases) { mode in Text(mode.title).tag(mode) }
                }.disabled(model.isStarting).accessibilityIdentifier("audioModePicker")
                HStack {
                    Image(systemName: model.isRunning ? "waveform" : "pause.circle").accessibilityHidden(true)
                    Text(model.status).accessibilityIdentifier("monitorStatus")
                }.foregroundStyle(model.isRunning ? Color.teal : .primary)
                WaveformView(samples: model.waveform, running: model.isRunning)
                    .frame(height: 80)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "accessibility.input_waveform", defaultValue: "マイク入力波形"))
                    .accessibilityValue(model.isRunning ? String(localized: "accessibility.input_peak", defaultValue: "入力ピーク \(db(model.maximumInputPeak)) dBFS") : String(localized: "monitor.state.stopped", defaultValue: "停止中"))
                    .accessibilityIdentifier("inputWaveform")
                LabeledContent(String(localized: "monitor.input_level", defaultValue: "入力レベル"), value: "\(db(model.peak)) dBFS")
                    .monospacedDigit()
                Button {
                    if model.isRunning || model.isStarting { model.stop() } else { model.start() }
                } label: {
                    HStack {
                        Label(model.isRunning ? String(localized: "monitor.action.stop", defaultValue: "モニターを停止") : model.isStarting ? String(localized: "monitor.action.cancel", defaultValue: "接続をキャンセル") : String(localized: "monitor.action.start", defaultValue: "モニターを開始"),
                              systemImage: model.isRunning ? "stop.fill" : "play.fill")
                        Spacer()
                        if model.isStarting { ProgressView() }
                    }
                }
                .disabled(!model.isRunning && !model.isStarting && !model.canStart)
                .accessibilityIdentifier("monitorToggle")
                #if DEBUG
                if !ProcessInfo.processInfo.arguments.contains("--store-capture"), ProcessInfo.processInfo.arguments.contains("--validate-speaker") || ProcessInfo.processInfo.arguments.contains("--validate-headphones") {
                    Text(String(localized: "diagnostics.live_summary", defaultValue: "入力ピーク \(db(model.maximumInputPeak))、出力ピーク \(db(model.maximumOutputPeak))、処理フレーム \(model.frames)、背景フレーム \(model.backgroundFrames)、エラー \(model.renderError)、量子 \(model.minimumQuantum)、サンプルレート \(Int(model.sampleRate))"))
                        .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("liveDiagnostics")
                }
                #endif
            } header: { Text(String(localized: "monitor.section", defaultValue: "モニター")) } footer: {
                if !model.canStart { Text(String(localized: "monitor.connection_help", defaultValue: "イヤホンを接続するか、本体スピーカーを有効にしてください。")) }
            }
            Section(String(localized: "monitor.volume_section", defaultValue: "音量と音質")) {
                VStack(alignment: .leading) {
                    LabeledContent(String(localized: "monitor.gain", defaultValue: "モニターゲイン"), value: MonitorPreferences.percentLabel(model.gain)).monospacedDigit()
                    Slider(value: $model.gain, in: 0...model.gainLimit)
                        .accessibilityLabel(String(localized: "monitor.gain", defaultValue: "モニターゲイン")).accessibilityIdentifier("gainSlider")
                }
                Button { showsGainSettings = true } label: {
                    LabeledContent(String(localized: "gain.settings", defaultValue: "ゲイン上限の設定"), value: MonitorPreferences.percentLabel(model.gainLimit))
                }.accessibilityIdentifier("gainSettings")
                Button { showsEqualizer = true } label: {
                    HStack {
                        Label(String(localized: "eq.title", defaultValue: "イコライザー"), systemImage: "slider.vertical.3")
                        Spacer()
                        Text(model.equalizer.enabled ? String(localized: "common.on", defaultValue: "ON") : String(localized: "common.off", defaultValue: "OFF")).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }.accessibilityIdentifier("openEqualizer")
                VStack(alignment: .leading) {
                    Text(String(localized: "monitor.system_volume", defaultValue: "システム音量"))
                    SystemVolume().frame(height: 32)
                }
            }
    }
    @ViewBuilder private var connections: some View {
            Section {
                ForEach(model.microphones) { mic in
                    Button { model.selectInput(mic.id) } label: {
                        HStack {
                            Label { VStack(alignment: .leading) {
                                Text(mic.name)
                                Text(mic.detail).font(.caption).foregroundStyle(.secondary)
                            } } icon: { Image(systemName: mic.icon) }
                            Spacer()
                            if model.selectedInput == mic.id { Image(systemName: "checkmark") }
                        }.foregroundStyle(.primary)
                    }.disabled(model.isStarting)
                }
                Button { model.prepare() } label: { Label(String(localized: "microphone.refresh", defaultValue: "接続とマイクを更新"), systemImage: "arrow.clockwise") }
                    .disabled(model.isRunning || model.isStarting).accessibilityIdentifier("refreshInputs")
                if model.permissionDenied {
                    Button(String(localized: "microphone.open_settings", defaultValue: "設定でマイクを許可")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: { Text(String(localized: "microphone.section", defaultValue: "入力マイク")) } footer: {
                Text(String(localized: "microphone.help", defaultValue: "本体マイクと、接続機器のマイクから選べます。OSが利用可能として公開するマイクを表示します。"))
            }
            Section {
                HStack {
                    LabeledContent(String(localized: "output.destination", defaultValue: "出力先"), value: model.outputName.isEmpty ? String(localized: "output.disconnected", defaultValue: "未接続") : model.outputName)
                        .accessibilityIdentifier("outputName")
                    RoutePicker().frame(width: 32, height: 30).accessibilityLabel(String(localized: "output.select", defaultValue: "出力先を選択"))
                }
                if !model.unconfirmedOutputs.isEmpty {
                    Button(String(localized: "output.confirm_headphones", defaultValue: "この接続先はイヤホンです")) { model.confirmExternalOutput() }
                        .accessibilityIdentifier("confirmHeadphones")
                    Text(String(localized: "output.confirm_help", defaultValue: "Bluetooth・USB機器は接続先がイヤホンであることを確認してください。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(String(localized: "output.allow_speaker", defaultValue: "本体スピーカーを使う"), isOn: Binding(get: { model.speakerEnabled }, set: model.setSpeakerEnabled))
                    .disabled(model.isStarting).accessibilityIdentifier("speakerToggle")
            } header: { Text(String(localized: "output.title", defaultValue: "出力")) } footer: {
                Text(model.speakerEnabled ? String(localized: "output.speaker_help", defaultValue: "スピーカーの音がマイクに入るとハウリングします。") : String(localized: "output.headphones_help", defaultValue: "イヤホンの切断時は自動停止します。"))
            }
            Section {
                Toggle(String(localized: "background.enabled", defaultValue: "画面を閉じても続ける"), isOn: $model.backgroundEnabled).accessibilityIdentifier("backgroundToggle")
            } header: { Text(String(localized: "background.title", defaultValue: "バックグラウンド")) } footer: {
                Text(String(localized: "background.help", defaultValue: "他のアプリと同時に再生します。他アプリがマイクを排他的に使う場合などは中断することがあります。"))
            }
    }
    @ViewBuilder private var latency: some View {
            Section {
                LabeledContent(String(localized: "latency.io_buffer", defaultValue: "I/Oバッファ"), value: milliseconds(model.bufferDuration))
                LabeledContent(String(localized: "audio.input", defaultValue: "入力"), value: milliseconds(model.inputLatency))
                LabeledContent(String(localized: "output.title", defaultValue: "出力"), value: milliseconds(model.outputLatency))
                LabeledContent(String(localized: "audio.sample_rate", defaultValue: "サンプルレート"), value: model.sampleRate > 0 ? String(format: "%.1f kHz", locale: Locale.current, model.sampleRate / 1000) : "—")
                LabeledContent(String(localized: "audio.active_mode", defaultValue: "動作中のモード"), value: model.selectedModeLabel)
                Text(model.tuningNote).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(String(localized: "diagnostics.title", defaultValue: "動作診断"), isExpanded: $diagnosticsExpanded) {
                    diagnostic(String(localized: "diagnostics.processed_frames", defaultValue: "処理フレーム"), "\(model.frames)", "renderFrames")
                    diagnostic(String(localized: "diagnostics.input_peak", defaultValue: "入力ピーク"), "\(db(model.maximumInputPeak)) dBFS", "maximumInputPeak")
                    diagnostic(String(localized: "diagnostics.output_peak", defaultValue: "出力ピーク"), "\(db(model.maximumOutputPeak)) dBFS", "maximumOutputPeak")
                    diagnostic(String(localized: "diagnostics.audio_error", defaultValue: "音声エラー"), "\(model.renderError)", "renderError")
                    diagnostic(String(localized: "diagnostics.missed_blocks", defaultValue: "欠落ブロック"), "\(model.missedQuanta)", "missedQuanta")
                    diagnostic(String(localized: "diagnostics.callback", defaultValue: "実コールバック"), "\(model.minimumQuantum)–\(model.maximumQuantum) frames", "actualQuantum")
                    diagnostic(String(localized: "diagnostics.background_frames", defaultValue: "背景処理フレーム"), "\(model.backgroundFrames)", "backgroundFrames")
                    diagnostic(String(localized: "diagnostics.background_duration", defaultValue: "背景継続時間"), String(format: "%.1f s", locale: Locale.current, model.backgroundSeconds), "backgroundSeconds")
                }.accessibilityIdentifier("diagnosticsToggle")
            } header: { Text(String(localized: "latency.title", defaultValue: "レイテンシー")) } footer: {
                Text(String(localized: "latency.help", defaultValue: "OSの報告値です。耳に届くまでの実測遅延ではありません。Bluetoothは無線伝送・コーデックの遅延が加わります。"))
            }
    }
    @ViewBuilder private var licenses: some View {
            Section {
                NavigationLink(String(localized: "backup.navigation", defaultValue: "設定のバックアップと復元")) { SettingsBackupView(model: model) }
                Button(String(localized: "licenses.navigation", defaultValue: "ライセンスとソースコード")) { showsLicense = true }.accessibilityIdentifier("licensesButton")
            } footer: { Text(String(localized: "privacy.local_audio", defaultValue: "音声はこの端末内で処理します。録音・送信はしません。")) }    }
    private func milliseconds(_ value: Double) -> String { model.permissionGranted ? String(format: "%.2f ms", locale: Locale.current, value * 1000) : "—" }
    private func diagnostic(_ title: String, _ value: String, _ id: String) -> some View {
        LabeledContent(title) { Text(value).monospacedDigit().accessibilityIdentifier(id) }.font(.caption)
    }
}
private func db(_ amplitude: Float) -> Int { Int(max(-96, 20 * log10(max(amplitude, 0.00001585))).rounded()) }
private struct WaveformView: View {
    let samples: [Float]
    let running: Bool
    var body: some View {
        Canvas { context, size in
            let center = size.height / 2
            var baseline = Path(); baseline.move(to: CGPoint(x: 0, y: center)); baseline.addLine(to: CGPoint(x: size.width, y: center))
            context.stroke(baseline, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            guard running, samples.count > 1 else { return }
            var wave = Path()
            for (index, sample) in samples.enumerated() {
                let point = CGPoint(x: CGFloat(index) / CGFloat(samples.count - 1) * size.width,
                    y: center - CGFloat(max(-1, min(1, sample * 12))) * size.height * 0.45)
                if index == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
            }
            context.stroke(wave, with: .color(.teal), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
private struct SystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero); view.showsRouteButton = false; return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
