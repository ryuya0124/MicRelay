# 署名とApp Store Connectへのアップロード

Bundle ID: `net.ryuya-dev.MicRelay` / App名: `MicRelay` / SKU: `MICRELAY-IOS`。

`ryuya-dev.net` の逆DNS表記を使っています。App Store Connectへアップロード後にBundle IDを変更しないでください。

## 準備

1. XcodeとXcodeGen、RubyとBundlerをインストールし、`bundle install` を実行します。Fastlaneのバージョンと依存関係はGemfile.lockで固定しています。
2. `.env.example` を `.env` へコピーし、自分のApp Store ConnectチームAPIキーとチームIDを設定します。`.p8` 本体はリポジトリの外に置きます。
3. 既存のApple Distribution証明書と対応する秘密鍵をMacのキーチェーンで利用できる状態にします。

`.env` と署名ファイル、生成物はgitignore対象です。キーをソースコードやGitHub Issuesへ貼り付けないでください。

## 初回登録

```sh
bundle exec fastlane ios register_bundle
```

Apple Developer PortalへBundle IDを登録します。App Store Connectの新規Appレコード作成はAppleのAPIが許可しないため、初回だけ [App Store Connect](https://appstoreconnect.apple.com/apps) の「新規App」で以下を入力します。

- プラットフォーム: iOS
- 名前: MicRelay
- プライマリ言語: 日本語
- Bundle ID: net.ryuya-dev.MicRelay
- SKU: MICRELAY-IOS

```sh
bundle exec fastlane ios register
```

登録済みレコードを検証します。審査提出は行いません。

## 署名・アーカイブ

```sh
bundle exec fastlane ios archive
```

既存のローカルDistribution証明書とApple側の証明書のSHA-1が一致することを確認し、このアプリ専用のApp Store配布プロファイルを作成または再利用します。他アプリの証明書を失効・再発行する処理はありません。

Releaseでアーカイブし、Apple Distribution署名のIPAを `artifacts/release/MicRelay.ipa` に出力します。署名済みアーカイブも同じフォルダに保持します。

## アップロードのみ

```sh
bundle exec fastlane ios upload_only
bundle exec fastlane ios status
```

`upload_only` は `skip_submission: true`、`distribute_external: false`、`notify_external_testers: false` を明示しています。App Review、Beta App Review、外部テスター配布、App Store公開は行いません。

`status` で処理済みビルド、Appバージョンの状態、レビュー提出の有無を読み取り、`artifacts/release/appstore-status.json` に保存します。再アップロードするときは `project.yml` の `CURRENT_PROJECT_VERSION` を増やしてください。

初回レコード作成済みなら、`bundle exec fastlane ios prepare` で登録確認・署名・アーカイブ・アップロードを順に行えます。App Store本体の審査提出・公開のlaneは用意していません。

## 参考

- [Apple Bundle ID](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier)
- [Fastlane API Key認証](https://docs.fastlane.tools/app-store-connect-api/)
- [アップロードのみのオプション](https://docs.fastlane.tools/actions/upload_to_testflight/)

## 外部TestFlight main（明示的に配布を依頼された場合）

```sh
bundle exec fastlane ios distribute_main
```

ユーザーから外部TestFlight公開の指示を受けたため追加した別laneです。`artifacts/release/review-contact.json`（または `BETA_REVIEW_CONTACT_JSON`）から非公開の審査連絡先を読み、処理済みビルド2を外部グループ `main` に割り当て、Beta App Reviewへ提出します。mainは公開リンクを利用します。Appleの承認までは外部インストールできません。App Store本体の審査には提出しません。連絡先・署名・診断ファイルはコミットしません。

ストアの日本語説明・サブタイトル・キーワードは `store/metadata/ja/`、実画面の画像は `store/screenshots/ja/`、自作ヘッダーは `store/header/` にあります。`scripts/store_metadata.rb metadata` は下書きメタデータのみ更新します。`screenshots` は画像をアップロード、`attach` は処理済みビルドを下書きへ選択します。いずれもApp Store Review提出は行いません。
