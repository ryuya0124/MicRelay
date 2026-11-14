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
                Button("設定を書き出す", systemImage: "square.and.arrow.up") {
                    do { document = SettingsDocument(data: try model.settingsBackup().encoded()); exporting = true }
                    catch { message = error.localizedDescription }
                }.accessibilityIdentifier("exportSettings")
                Button("ファイルから読み込む", systemImage: "square.and.arrow.down") { importing = true }
                    .accessibilityIdentifier("importSettings")
            } footer: {
                Text("ゲイン・ゲイン上限・EQ・バックグラウンド設定・選択マイクをJSONファイルに保存します。音声は含みません。スピーカーの許可と接続先の確認は復元しません。")
            }
            if let candidate {
                Section("読み込んだ設定") {
                    LabeledContent("ゲイン", value: MonitorPreferences.percentLabel(candidate.gain))
                    LabeledContent("ゲイン上限", value: MonitorPreferences.percentLabel(candidate.gainLimit))
                    LabeledContent("イコライザー", value: candidate.equalizer.enabled ? "ON" : "OFF")
                    LabeledContent("バックグラウンド", value: candidate.backgroundEnabled ? "ON" : "OFF")
                    LabeledContent("音声モード", value: (candidate.audioMode ?? .automatic).title)
                    LabeledContent("作成日時", value: candidate.createdAt.formatted())
                    Text("復元時にモニターを停止します。接続されていないマイクは本体マイクへ戻します。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("この設定を復元") {
                        do {
                            let inputAvailable = try model.restoreSettings(candidate)
                            message = inputAvailable ? "設定を復元しました。" : "設定を復元しました。元のマイクが利用できないため本体マイクを選びました。"
                            self.candidate = nil
                        } catch { message = error.localizedDescription }
                    }.accessibilityIdentifier("restoreSettings")
                    Button("取り消す", role: .cancel) { self.candidate = nil }
                }
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("バックアップと復元").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "MicRelay-settings") { result in
            switch result {
            case .success: message = "設定を書き出しました。"
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
