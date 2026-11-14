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
        .sheet(isPresented: $showsGainSettings) { GainSettingsView(model: model) }
    }
    @ViewBuilder private var controls: some View {
            Section {
                Picker("音声モード", selection: Binding(get: { model.modePreference }, set: model.selectAudioMode)) {
                    ForEach(AudioModePreference.allCases) { mode in Text(mode.title).tag(mode) }
                }.disabled(model.isStarting).accessibilityIdentifier("audioModePicker")
                HStack {
                    Image(systemName: model.isRunning ? "waveform" : "pause.circle").accessibilityHidden(true)
                    Text(model.status).accessibilityIdentifier("monitorStatus")
                }.foregroundStyle(model.isRunning ? Color.teal : .primary)
                WaveformView(samples: model.waveform, running: model.isRunning)
                    .frame(height: 80)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("マイク入力波形")
                    .accessibilityValue(model.isRunning ? "入力ピーク \(db(model.maximumInputPeak)) dBFS" : "停止中")
                    .accessibilityIdentifier("inputWaveform")
                LabeledContent("入力レベル", value: "\(db(model.peak)) dBFS")
                    .monospacedDigit()
                Button {
                    if model.isRunning || model.isStarting { model.stop() } else { model.start() }
                } label: {
                    HStack {
                        Label(model.isRunning ? "モニターを停止" : model.isStarting ? "接続をキャンセル" : "モニターを開始",
                              systemImage: model.isRunning ? "stop.fill" : "play.fill")
                        Spacer()
                        if model.isStarting { ProgressView() }
                    }
                }
                .disabled(!model.isRunning && !model.isStarting && !model.canStart)
                .accessibilityIdentifier("monitorToggle")
                #if DEBUG
                if !ProcessInfo.processInfo.arguments.contains("--store-capture"), ProcessInfo.processInfo.arguments.contains("--validate-speaker") || ProcessInfo.processInfo.arguments.contains("--validate-headphones") {
                    Text("入力ピーク \(db(model.maximumInputPeak))、出力ピーク \(db(model.maximumOutputPeak))、処理フレーム \(model.frames)、背景フレーム \(model.backgroundFrames)、エラー \(model.renderError)、量子 \(model.minimumQuantum)、サンプルレート \(Int(model.sampleRate))")
                        .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("liveDiagnostics")
                }
                #endif
            } header: { Text("モニター") } footer: {
                if !model.canStart { Text("イヤホンを接続するか、本体スピーカーを有効にしてください。") }
            }
            Section("音量と音質") {
                VStack(alignment: .leading) {
                    LabeledContent("モニターゲイン", value: MonitorPreferences.percentLabel(model.gain)).monospacedDigit()
                    Slider(value: $model.gain, in: 0...model.gainLimit)
                        .accessibilityLabel("モニターゲイン").accessibilityIdentifier("gainSlider")
                }
                Button { showsGainSettings = true } label: {
                    LabeledContent("ゲイン上限の設定", value: MonitorPreferences.percentLabel(model.gainLimit))
                }.accessibilityIdentifier("gainSettings")
                Button { showsEqualizer = true } label: {
                    HStack {
                        Label("イコライザー", systemImage: "slider.vertical.3")
                        Spacer()
                        Text(model.equalizer.enabled ? "ON" : "OFF").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }.accessibilityIdentifier("openEqualizer")
                VStack(alignment: .leading) {
                    Text("システム音量")
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
                Button { model.prepare() } label: { Label("接続とマイクを更新", systemImage: "arrow.clockwise") }
                    .disabled(model.isRunning || model.isStarting).accessibilityIdentifier("refreshInputs")
                if model.permissionDenied {
                    Button("設定でマイクを許可") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: { Text("入力マイク") } footer: {
                Text("本体マイクと、接続機器のマイクから選べます。OSが利用可能として公開するマイクを表示します。")
            }
            Section {
                HStack {
                    LabeledContent("出力先", value: model.outputName.isEmpty ? "未接続" : model.outputName)
                        .accessibilityIdentifier("outputName")
                    RoutePicker().frame(width: 32, height: 30).accessibilityLabel("出力先を選択")
                }
                if !model.unconfirmedOutputs.isEmpty {
                    Button("この接続先はイヤホンです") { model.confirmExternalOutput() }
                        .accessibilityIdentifier("confirmHeadphones")
                    Text("Bluetooth・USB機器は接続先がイヤホンであることを確認してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("本体スピーカーを使う", isOn: Binding(get: { model.speakerEnabled }, set: model.setSpeakerEnabled))
                    .disabled(model.isStarting).accessibilityIdentifier("speakerToggle")
            } header: { Text("出力") } footer: {
                Text(model.speakerEnabled ? "スピーカーの音がマイクに入るとハウリングします。" : "イヤホンの切断時は自動停止します。")
            }
            Section {
                Toggle("画面を閉じても続ける", isOn: $model.backgroundEnabled).accessibilityIdentifier("backgroundToggle")
            } header: { Text("バックグラウンド") } footer: {
                Text("他のアプリと同時に再生します。他アプリがマイクを排他的に使う場合などは中断することがあります。")
            }
    }
    @ViewBuilder private var latency: some View {
            Section {
                LabeledContent("I/Oバッファ", value: milliseconds(model.bufferDuration))
                LabeledContent("入力", value: milliseconds(model.inputLatency))
                LabeledContent("出力", value: milliseconds(model.outputLatency))
                LabeledContent("サンプルレート", value: model.sampleRate > 0 ? String(format: "%.1f kHz", model.sampleRate / 1000) : "—")
                LabeledContent("動作中のモード", value: model.selectedModeLabel)
                Text(model.tuningNote).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("動作診断", isExpanded: $diagnosticsExpanded) {
                    diagnostic("処理フレーム", "\(model.frames)", "renderFrames")
                    diagnostic("入力ピーク", "\(db(model.maximumInputPeak)) dBFS", "maximumInputPeak")
                    diagnostic("出力ピーク", "\(db(model.maximumOutputPeak)) dBFS", "maximumOutputPeak")
                    diagnostic("音声エラー", "\(model.renderError)", "renderError")
                    diagnostic("欠落ブロック", "\(model.missedQuanta)", "missedQuanta")
                    diagnostic("実コールバック", "\(model.minimumQuantum)–\(model.maximumQuantum) frames", "actualQuantum")
                    diagnostic("背景処理フレーム", "\(model.backgroundFrames)", "backgroundFrames")
                    diagnostic("背景継続時間", String(format: "%.1f s", model.backgroundSeconds), "backgroundSeconds")
                }.accessibilityIdentifier("diagnosticsToggle")
            } header: { Text("レイテンシー") } footer: {
                Text("OSの報告値です。耳に届くまでの実測遅延ではありません。Bluetoothは無線伝送・コーデックの遅延が加わります。")
            }
    }
    @ViewBuilder private var licenses: some View {
            Section {
                NavigationLink("設定のバックアップと復元") { SettingsBackupView(model: model) }
                Button("ライセンスとソースコード") { showsLicense = true }.accessibilityIdentifier("licensesButton")
            } footer: { Text("音声はこの端末内で処理します。録音・送信はしません。") }    }
    private func milliseconds(_ value: Double) -> String { model.permissionGranted ? String(format: "%.2f ms", value * 1000) : "—" }
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
