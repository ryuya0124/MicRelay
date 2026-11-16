// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import SwiftUI

struct MonitorStartButton: View {
    @ObservedObject var model: MonitorModel
    var compact = false
    @State private var showsStartOutputAlert = false
    @State private var pendingStartRequirement = OutputSafety.StartRequirement.unavailable
    @State private var pendingOutputIDs: Set<String> = []

    var body: some View {
        Button {
            if model.isRunning || model.isStarting { model.stop() }
            else {
                model.refreshRoute()
                if model.canStart { model.start() }
                else {
                    pendingStartRequirement = model.startRequirement
                    pendingOutputIDs = Set(model.outputs.map(\.uid))
                    showsStartOutputAlert = true
                }
            }
        } label: {
            if compact {
                Text(model.isStarting ? String(localized: "monitor.action.cancel", defaultValue: "接続をキャンセル")
                    : model.isRunning ? String(localized: "eq.action.stop", defaultValue: "モニター停止")
                    : String(localized: "eq.action.start", defaultValue: "モニター開始"))
            } else {
                HStack {
                    Label(model.isRunning ? String(localized: "monitor.action.stop", defaultValue: "モニターを停止") : model.isStarting ? String(localized: "monitor.action.cancel", defaultValue: "接続をキャンセル") : String(localized: "monitor.action.start", defaultValue: "モニターを開始"),
                          systemImage: model.isRunning ? "stop.fill" : "play.fill")
                    Spacer()
                    if model.isStarting { ProgressView() }
                }
            }
        }
        .accessibilityIdentifier(compact ? "equalizerMonitorToggle" : "monitorToggle")
        .alert(String(localized: "monitor.start.output_title", defaultValue: "出力先を確認"), isPresented: $showsStartOutputAlert) {
            if pendingStartRequirement == .speakerPermission {
                Button(String(localized: "monitor.start.speaker", defaultValue: "本体スピーカーで開始")) {
                    model.startAfterOutputApproval(speaker: true, expectedIDs: pendingOutputIDs)
                }.accessibilityIdentifier("approveSpeakerStart")
            } else if pendingStartRequirement == .externalConfirmation {
                Button(String(localized: "monitor.start.headphones", defaultValue: "イヤホンとして開始")) {
                    model.startAfterOutputApproval(speaker: false, expectedIDs: pendingOutputIDs)
                }.accessibilityIdentifier("approveHeadphoneStart")
            }
            Button(String(localized: "microphone.refresh", defaultValue: "接続とマイクを更新")) { model.prepare() }
            Button(String(localized: "common.cancel", defaultValue: "キャンセル"), role: .cancel) {}
        } message: {
            Text(pendingStartRequirement == .speakerPermission
                ? String(localized: "monitor.start.speaker_help", defaultValue: "本体スピーカーの使用がOFFです。スピーカーで開始する場合は許可してください。スピーカーの音がマイクに入るとハウリングします。")
                : pendingStartRequirement == .externalConfirmation
                ? String(localized: "monitor.start.headphones_help", defaultValue: "この接続先がイヤホンであることを確認してから開始してください。")
                : String(localized: "monitor.start.connection_help", defaultValue: "対応する出力先を確認できません。イヤホン・HDMI機器を接続し、接続とマイクを更新してください。"))
        }
    }
}
