// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import SwiftUI
import UIKit

struct ScreenRecordingView: View {
    @ObservedObject var recorder: ScreenRecordingModel
    @AppStorage(ScreenRecordingSettings.preferenceKey) private var excludesMonitorAudio = true
    @Environment(\.openURL) private var openURL
    @State private var deleteCandidate: RecordedVideo?

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "recording.exclude", defaultValue: "録画からモニター音を除外"), isOn: $excludesMonitorAudio)
                    .tint(recorder.supportsRecording ? .green : .gray)
                    .disabled(!recorder.supportsRecording || recorder.state.isBusy)
                    .accessibilityIdentifier("excludeMonitorAudioToggle")
                if let applied = recorder.appliedExclusion {
                    LabeledContent(String(localized: "recording.applied", defaultValue: "今回の録画"), value: applied
                        ? String(localized: "recording.excluded", defaultValue: "モニター音を除外")
                        : String(localized: "recording.included", defaultValue: "モニター音を含む"))
                }
            } header: { Text(String(localized: "recording.audio", defaultValue: "録画する音声")) } footer: {
                Text(String(localized: "recording.exclude_help", defaultValue: "ONではイヤホンのモニター音を聞きながら、その音を動画から除外します。OFFではモニター音も録画します。録画中は変更できません。"))
            }
            Section {
                Label(recorder.status, systemImage: recorder.state == .recording ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(recorder.state == .recording ? Color.red : .primary)
                    .accessibilityIdentifier("screenRecordingStatus")
                if recorder.state == .recording {
                    Button(String(localized: "recording.stop", defaultValue: "録画を停止して保存"), role: .destructive) { recorder.stop() }
                        .accessibilityIdentifier("stopScreenRecording")
                } else {
                    Button(String(localized: "recording.start", defaultValue: "画面録画を開始"), systemImage: "record.circle") {
                        recorder.start(excludingMonitorAudio: excludesMonitorAudio)
                    }.disabled(!recorder.supportsRecording || recorder.state.isBusy)
                        .foregroundStyle(recorder.supportsRecording ? Color.accentColor : .secondary)
                        .accessibilityIdentifier("startScreenRecording")
                }
                if !recorder.supportsRecording {
                    Text(String(localized: "recording.requires_update", defaultValue: "iOS／iPadOS 27以降にアップデートすると利用できます。"))
                        .foregroundStyle(.secondary).accessibilityIdentifier("screenRecordingRequiresUpdate")
                }
                if let error = recorder.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("screenRecordingError")
                    if recorder.photoSaveFailed {
                        Button(String(localized: "recording.open_settings", defaultValue: "設定を開く")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                if recorder.savedMessage { Text(String(localized: "recording.saved", defaultValue: "動画を写真アプリに保存し、アプリ内のコピーを削除しました。")) }
            } header: { Text(String(localized: "recording.title", defaultValue: "画面録画")) } footer: {
                Text(String(localized: "recording.help", defaultValue: "この画面から開始する録画だけに適用されます。コントロールセンターの画面録画には適用されません。ゲームなどを録画する場合は、選択画面で画面全体を選んでください。録画用マイクはOFFです。"))
            }
            Section(String(localized: "recording.videos", defaultValue: "アプリ内の動画")) {
                LabeledContent(String(localized: "recording.storage", defaultValue: "アプリ内の動画の使用量"),
                    value: ByteCountFormatter.string(fromByteCount: recorder.videos.reduce(0) { $0 + $1.bytes }, countStyle: .file))
                if recorder.videos.isEmpty { Text(String(localized: "recording.empty", defaultValue: "アプリ内の動画はありません。保存が完了した動画は写真アプリで見られます。" )).foregroundStyle(.secondary) }
                if recorder.videos.filter({ $0.isPlayable && !recorder.savedToPhotos.contains($0.url.lastPathComponent) }).count > 1 {
                    Button(String(localized: "recording.photos.save_all", defaultValue: "未保存の動画をまとめて写真に保存"), systemImage: "photo.on.rectangle.angled") {
                        Task { await recorder.saveAllToPhotos() }
                    }.disabled(recorder.state.isBusy).accessibilityIdentifier("saveAllRecordingsToPhotos")
                }
                ForEach(recorder.videos) { video in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(video.date.formatted()).font(.subheadline)
                        Text(ByteCountFormatter.string(fromByteCount: video.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        if !video.isPlayable {
                            Text(String(localized: "recording.incomplete", defaultValue: "未完了の動画" )).font(.caption).foregroundStyle(.secondary)
                        }
                        if recorder.savedToPhotos.contains(video.url.lastPathComponent) {
                            Label(String(localized: "recording.photos.saved", defaultValue: "写真に保存済み"), systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(String(localized: "recording.photos.save", defaultValue: "写真に保存"), systemImage: "photo.badge.plus") {
                                Task { await recorder.saveToPhotos(video.url) }
                            }.disabled(recorder.state.isBusy || !video.isPlayable)
                        }
                        ShareLink(item: video.url) { Label(String(localized: "recording.share", defaultValue: "動画を共有・書き出す"), systemImage: "square.and.arrow.up") }
                        Button(String(localized: "recording.delete", defaultValue: "アプリ内の動画を削除"), systemImage: "trash", role: .destructive) {
                            deleteCandidate = video
                        }.disabled(recorder.state.isBusy)
                            .accessibilityIdentifier("deleteRecording-" + video.url.lastPathComponent)
                    }
                    .buttonStyle(.borderless)
                    .swipeActions {
                        Button(role: .destructive) { deleteCandidate = video } label: {
                            Label(String(localized: "recording.delete", defaultValue: "アプリ内の動画を削除"), systemImage: "trash")
                        }.disabled(recorder.state.isBusy)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "recording.title", defaultValue: "画面録画"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(String(localized: "recording.delete_confirm", defaultValue: "アプリ内の動画を削除しますか？"), isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
                Button(String(localized: "recording.delete", defaultValue: "アプリ内の動画を削除"), role: .destructive) {
                    if let video = deleteCandidate { recorder.deleteAppCopy(video) }
                    deleteCandidate = nil
                }.accessibilityIdentifier("confirmDeleteRecording")
                Button(String(localized: "common.discard", defaultValue: "取り消す"), role: .cancel) { deleteCandidate = nil }
                    .accessibilityIdentifier("cancelDeleteRecording")
            } message: {
                Text(String(localized: "recording.delete_help", defaultValue: "写真アプリの動画は削除しません。このアプリ内に保存されている動画だけを削除します。"))
            }
        .task {
            await recorder.refreshVideos()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--save-existing-recordings-to-photos") {
                await recorder.saveAllToPhotos()
            }
            #endif
        }
    }
}
