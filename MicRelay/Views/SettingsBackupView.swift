// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import SwiftUI
import UniformTypeIdentifiers

struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.values }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsBackupView: View {
    @ObservedObject var model: MonitorModel
    @State private var exporting = false
    @State private var importing = false
    @State private var document = SettingsDocument(data: Data())
    @State private var candidate: SettingsBackup?
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button(String(localized: "backup.export", defaultValue: "設定を書き出す"), systemImage: "square.and.arrow.up") {
                    do { document = SettingsDocument(data: try model.settingsBackup().encoded()); exporting = true }
                    catch { message = error.localizedDescription }
                }.accessibilityIdentifier("exportSettings")
                Button(String(localized: "backup.import", defaultValue: "ファイルから読み込む"), systemImage: "square.and.arrow.down") { importing = true }
                    .accessibilityIdentifier("importSettings")
            } footer: {
                Text(String(localized: "backup.help", defaultValue: "ゲイン・ゲイン上限・EQ・風切り音低減・音声モード・バックグラウンド設定・選択マイクをJSONファイルに保存します。音声は含みません。スピーカーの許可と接続先の確認は復元しません。"))
            }
            if let candidate {
                Section(String(localized: "backup.loaded", defaultValue: "読み込んだ設定")) {
                    LabeledContent(String(localized: "gain.title", defaultValue: "ゲイン"), value: MonitorPreferences.percentLabel(candidate.gain))
                    LabeledContent(String(localized: "gain.limit", defaultValue: "ゲイン上限"), value: MonitorPreferences.percentLabel(candidate.gainLimit))
                    LabeledContent(String(localized: "eq.title", defaultValue: "イコライザー"), value: candidate.equalizer.enabled ? String(localized: "common.on", defaultValue: "ON") : String(localized: "common.off", defaultValue: "OFF"))
                    LabeledContent(String(localized: "wind.title", defaultValue: "風切り音低減"), value: candidate.windNoise?.enabled == true ? "\(Int(candidate.windNoise?.cutoff ?? 120)) Hz" : String(localized: "common.off", defaultValue: "OFF"))
                    LabeledContent(String(localized: "background.title", defaultValue: "バックグラウンド"), value: candidate.backgroundEnabled ? String(localized: "common.on", defaultValue: "ON") : String(localized: "common.off", defaultValue: "OFF"))
                    LabeledContent(String(localized: "audio.mode.title", defaultValue: "音声モード"), value: (candidate.audioMode ?? .automatic).title)
                    LabeledContent(String(localized: "backup.created_at", defaultValue: "作成日時"), value: candidate.createdAt.formatted())
                    Text(String(localized: "backup.restore_help", defaultValue: "復元時にモニターを停止します。接続されていないマイクは本体マイクへ戻します。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "backup.restore", defaultValue: "この設定を復元")) {
                        do {
                            let inputAvailable = try model.restoreSettings(candidate)
                            message = inputAvailable ? String(localized: "backup.restored", defaultValue: "設定を復元しました。") : String(localized: "backup.restored_fallback", defaultValue: "設定を復元しました。元のマイクが利用できないため本体マイクを選びました。")
                            self.candidate = nil
                        } catch { message = error.localizedDescription }
                    }.accessibilityIdentifier("restoreSettings")
                    Button(String(localized: "common.discard", defaultValue: "取り消す"), role: .cancel) { self.candidate = nil }
                }
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle(String(localized: "backup.title", defaultValue: "バックアップと復元")).navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "MicRelay-settings") { result in
            switch result {
            case .success: message = String(localized: "backup.exported", defaultValue: "設定を書き出しました。")
            case .failure(let error): message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1_048_576 else { throw BackupError.size }
                candidate = try SettingsBackup.decode(Data(contentsOf: url, options: .mappedIfSafe))
                message = nil
            } catch { message = error.localizedDescription; candidate = nil }
        }
    }
}
