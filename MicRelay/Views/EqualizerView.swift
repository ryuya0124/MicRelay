// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import SwiftUI

@MainActor
struct EqualizerView: View {
    @ObservedObject var model: MonitorModel
    @State private var selected = 0

    private var band: EqualizerBand { model.equalizer.bands[selected] }
    private var maximumFrequency: Double { min(20000, model.sampleRate > 0 ? model.sampleRate * 0.499 : 20000) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Toggle("EQ", isOn: Binding(get: { model.equalizer.enabled }, set: model.setEqualizerEnabled))
                        .font(.headline).accessibilityIdentifier("equalizerEnabled")
                    Spacer(minLength: 30)
                    Button(model.isRunning ? String(localized: "eq.action.stop", defaultValue: "モニター停止") : String(localized: "eq.action.start", defaultValue: "モニター開始")) {
                        if model.isRunning { model.stop() } else { model.start() }
                    }.buttonStyle(.bordered).disabled(model.isStarting || (!model.isRunning && !model.canStart))
                }
                Text(model.equalizer.enabled ? String(localized: "eq.enabled", defaultValue: "EQ ON") : String(localized: "eq.bypass", defaultValue: "EQ OFF · フィルターをバイパス"))
                    .font(.caption).foregroundStyle(model.equalizer.enabled ? Color.teal : .secondary)
                SpectrumPlot(frame: model.spectrum, selectedFrequency: band.frequency,
                    maximumFrequency: maximumFrequency, isRunning: model.isRunning) { frequency in
                        model.updateEqualizerBand(selected) { $0.frequency = frequency.rounded() }
                    }
                    .frame(height: 260)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "accessibility.spectrum", defaultValue: "入力とEQ後の周波数スペクトラム"))
                    .accessibilityValue(String(localized: "accessibility.spectrum_values", defaultValue: "解析フレーム \(model.spectrumFrameCount)、ピーク \(Int(model.spectrum?.dominantFrequency ?? 0)) Hz、差分 \(spectralDifference) dB"))
                    .accessibilityIdentifier("frequencySpectrum")
                HStack(spacing: 20) {
                    Label(String(localized: "audio.input", defaultValue: "入力"), systemImage: "minus").foregroundStyle(.teal)
                    Label(String(localized: "eq.post_eq", defaultValue: "EQ後"), systemImage: "minus").foregroundStyle(.orange)
                    Spacer()
                    if let frame = model.spectrum {
                        Text(String(localized: "eq.peak_frequency", defaultValue: "ピーク \(frequencyLabel(frame.dominantFrequency))")).monospacedDigit()
                    }
                }.font(.caption)
                Text(String(localized: "eq.spectrum_help", defaultValue: "出力ゲインをかける前のスペクトラムです。グラフ上をタップ・ドラッグすると、選択中バンドの周波数を調整できます。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(model.equalizer.bands.enumerated()), id: \.element.id) { index, value in
                            Button { selected = index } label: {
                                VStack(spacing: 5) {
                                    Text("\(index + 1)").font(.caption2)
                                    Text(frequencyLabel(value.frequency)).font(.caption.weight(.semibold))
                                }.padding(.horizontal, 16).padding(.vertical, 11)
                                    .foregroundStyle(selected == index ? Color.black : Color.primary)
                                    .background(selected == index ? Color.teal : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    Toggle(String(localized: "eq.enable_band", defaultValue: "バンド \(selected + 1) を使う"), isOn: binding(\.enabled))
                    Picker(String(localized: "eq.filter.title", defaultValue: "フィルター"), selection: binding(\.filter)) {
                        ForEach(EqualizerFilter.allCases) { type in Text(type.title).tag(type) }
                    }.pickerStyle(.menu)
                    HStack {
                        Text(String(localized: "eq.frequency", defaultValue: "周波数"))
                        Spacer()
                        TextField("Hz", value: binding(\.frequency), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
                            .onSubmit { model.updateEqualizerBand(selected) { $0.frequency = min(20000, max(20, $0.frequency)) } }
                        Text("Hz").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { log10(min(maximumFrequency, max(20, band.frequency))) }, set: { value in
                        model.updateEqualizerBand(selected) { $0.frequency = pow(10, value).rounded() }
                    }), in: log10(20)...log10(maximumFrequency))
                        .accessibilityLabel(String(localized: "eq.frequency", defaultValue: "周波数"))
                    if band.filter == .peak {
                        HStack { Text(String(localized: "eq.gain", defaultValue: "増減")); Spacer(); Text(String(format: "%+.1f dB", locale: Locale.current, band.gainDB)).monospacedDigit() }
                        Slider(value: binding(\.gainDB), in: -36...24, step: 0.5).accessibilityLabel(String(localized: "eq.band_gain", defaultValue: "バンドの増減"))
                    }
                    HStack { Text(String(localized: "eq.q", defaultValue: "Q（帯域の狭さ）")); Spacer(); Text(String(format: "%.2f", locale: Locale.current, band.q)).monospacedDigit() }
                    Slider(value: Binding(get: { log10(band.q) }, set: { value in
                        model.updateEqualizerBand(selected) { $0.q = pow(10, value) }
                    }), in: log10(0.2)...log10(30)).accessibilityLabel("Q")
                    Text(band.filter == .notch ? String(localized: "eq.notch_help", defaultValue: "指定した中心周波数を強く減衰させます。Qを上げると除去する帯域が狭くなります。") : String(localized: "eq.q_help", defaultValue: "Qを上げると、中心周波数付近の狭い範囲に作用します。"))
                        .font(.caption).foregroundStyle(.secondary)
                    if band.frequency >= maximumFrequency {
                        Text(String(localized: "eq.frequency_limit", defaultValue: "現在の入力で扱える周波数は約\(frequencyLabel(maximumFrequency))までです。"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                Button(String(localized: "eq.reset", defaultValue: "フラットに戻す")) { model.resetEqualizer() }.font(.footnote)
                Text(String(localized: "eq.persistence_help", defaultValue: "OFF時はEQ処理を通りません。EQの設定はこの端末に保存されます。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(String(localized: "eq.title", defaultValue: "イコライザー"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.setSpectrumVisible(true) }
        .onDisappear { model.setSpectrumVisible(false) }
    }

    private func binding<Value>(_ path: WritableKeyPath<EqualizerBand, Value>) -> Binding<Value> {
        Binding(get: { band[keyPath: path] }, set: { value in model.updateEqualizerBand(selected) { $0[keyPath: path] = value } })
    }

    private var spectralDifference: Int {
        guard let frame = model.spectrum else { return 0 }
        return Int(zip(frame.inputDB, frame.equalizedDB).map { abs($0 - $1) }.max() ?? 0)
    }
}

private func frequencyLabel(_ value: Double) -> String {
    value >= 1000 ? String(format: "%.2g kHz", locale: Locale.current, value / 1000) : String(format: "%.0f Hz", locale: Locale.current, value)
}

private struct SpectrumPlot: View {
    let frame: SpectrumFrame?
    let selectedFrequency: Double
    let maximumFrequency: Double
    let isRunning: Bool
    let selectFrequency: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let left: CGFloat = 36, right: CGFloat = 14, top: CGFloat = 12, bottom: CGFloat = 28
                let width = max(1, size.width - left - right), height = max(1, size.height - top - bottom)
                func x(_ frequency: Double) -> CGFloat { left + CGFloat(log(max(20, frequency) / 20) / log(maximumFrequency / 20)) * width }
                func y(_ db: Float) -> CGFloat { top + CGFloat((12 - max(-96, min(12, db))) / 108) * height }
                for frequency in [20.0, 100, 1000, 10000] where frequency <= maximumFrequency {
                    var grid = Path(); grid.move(to: CGPoint(x: x(frequency), y: top)); grid.addLine(to: CGPoint(x: x(frequency), y: top + height))
                    context.stroke(grid, with: .color(.secondary.opacity(0.16)), lineWidth: 1)
                    context.draw(Text(frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))")
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.gray), at: CGPoint(x: x(frequency), y: top + height + 14))
                }
                for db: Float in [-90, -60, -30, 0] {
                    var grid = Path(); grid.move(to: CGPoint(x: left, y: y(db))); grid.addLine(to: CGPoint(x: left + width, y: y(db)))
                    context.stroke(grid, with: .color(.secondary.opacity(0.16)), lineWidth: 1)
                    context.draw(Text("\(Int(db))").font(.system(size: 9, design: .monospaced)).foregroundColor(.gray), at: CGPoint(x: left - 17, y: y(db)))
                }
                if isRunning, let frame {
                    for (values, color) in [(frame.inputDB, Color.teal), (frame.equalizedDB, Color.orange)] {
                        var path = Path()
                        for i in values.indices where i < frame.frequencies.count {
                            let point = CGPoint(x: x(frame.frequencies[i]), y: y(values[i]))
                            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        context.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    }
                }
                if selectedFrequency <= maximumFrequency {
                    var cursor = Path(); cursor.move(to: CGPoint(x: x(selectedFrequency), y: top)); cursor.addLine(to: CGPoint(x: x(selectedFrequency), y: top + height))
                    context.stroke(cursor, with: .color(.primary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                context.draw(Text("dBFS").font(.system(size: 9, design: .monospaced)).foregroundColor(.gray), at: CGPoint(x: 22, y: 5))
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = min(1, max(0, (value.location.x - 36) / max(1, geometry.size.width - 50)))
                selectFrequency(20 * pow(maximumFrequency / 20, Double(fraction)))
            })
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
