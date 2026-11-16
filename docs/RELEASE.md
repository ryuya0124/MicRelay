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

初回レコード作成済みなら、`bundle exec fastlane ios prepare` で登録確認・署名・アーカイブ・アップロードを順に行えます。App Store本体の審査提出は、下記の専用laneを明示的に実行する場合だけ行います。

## 参考

- [Apple Bundle ID](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier)
- [Fastlane API Key認証](https://docs.fastlane.tools/app-store-connect-api/)
- [アップロードのみのオプション](https://docs.fastlane.tools/actions/upload_to_testflight/)

## 外部TestFlight main（明示的に配布を依頼された場合）

```sh
bundle exec fastlane ios distribute_main
```

ユーザーから外部TestFlight公開の指示を受けたため追加した別laneです。`artifacts/release/review-contact.json`（または `BETA_REVIEW_CONTACT_JSON`）から非公開の審査連絡先を読み、`project.yml` の `CURRENT_PROJECT_VERSION` に指定した処理済みビルドを外部グループ `main` に割り当て、Beta App Reviewへ提出します。mainは公開リンクを利用します。Appleの承認までは外部インストールできません。App Store本体の審査には提出しません。連絡先・署名・診断ファイルはコミットしません。

ストアの日本語説明・サブタイトル・キーワードは `store/metadata/ja/`、実画面の画像は `store/screenshots/ja/`、自作ヘッダーは `store/header/` にあります。`scripts/store_metadata.rb metadata` は下書きメタデータのみ更新します。`screenshots` は画像をアップロード、`attach` は処理済みビルドを下書きへ選択します。いずれもApp Store Review提出は行いません。

英語（米国）は `store/metadata/en-US/` と `store/screenshots/en-US/`、英語のサポートとプライバシー文書は `docs/en/` にあります。言語コードを第2引数に指定できます。

```sh
bundle exec ruby scripts/store_metadata.rb metadata en-US
bundle exec ruby scripts/store_metadata.rb screenshots en-US
bundle exec ruby scripts/store_creative.rb header en-US
bundle exec ruby scripts/store_creative.rb search en-US
bundle exec ruby scripts/store_metadata.rb verify en-US
```

英語スクリーンショットは `MicRelayUITests/testEnglishStoreScreenshots` で撮影し、`xcresulttool export attachments` の出力から `swift scripts/export-localized-screenshots.swift en-US <iphone|ipad|duo> <出力ディレクトリ>` で書き出せます。実画面を使用し、波形・スペクトラム・遅延値を合成しません。英語ローカライズの追加は、配信地域やApp Store本体の審査・公開を変更しません。


スクリーンショットの差し替えは `bundle exec ruby scripts/sync-store-screenshots.rb <ja|en-US> <ipad|duo|iphone>` で対象セットだけを更新できます。新しい画像がすべて `COMPLETE` になった後に古い画像を外し、順序とチェックサムを読み戻します。元画像はHEADから復元できることを確認し、`artifacts/` にも控えを保存します。画像のGitコミットは差し替え後に行います。

撮影テストはダーク表示を指定し、iPadでは横向きを指定します。`UIImage.imageOrientation` を描画へ反映したPNGを保存し、書き出し側も画像の向きを反映します。各言語のテスト記録だけを含むmanifestを渡してください。`generate-store-assets.swift` はヘッダー等の自作画像だけを生成し、過去のキャプチャでスクリーンショットを上書きしません。


## App Store本体の審査（明示的に依頼された場合）

```sh
bundle exec fastlane ios submit_store_review
```

ユーザーの審査提出指示に合わせて追加したlaneです。`project.yml` のバージョンとビルド、署名済みアップロードの `VALID`、日英の説明・画像のチェックサムと登録完了、審査用の連絡先・操作案内を確認して、対応するバージョンだけをApp Reviewへ提出します。既存の同一バージョンの提出は重複させず、別の審査項目がある場合は停止します。ビルドの再アップロードは行いません。

公開方法は `store/release-policy.json` を使用します。現在はユーザーの指示で `AFTER_APPROVAL`（承認後に自動公開）。`MANUAL` への変更にも対応します。メタデータ更新でも同じ設定を読み、自動公開の指定を手動に戻しません。プライバシー回答の公開はこのlaneでは行いません。Appleの公開確認に表示される、回答の正確性・ガイドラインと法令への適合・変更時の更新に対する同意は、実行時に別途確認します。

## 次期ビルド7と審査中ビルド6（2026-11-15時点の履歴）

ビルド7は自動サンプルレート探索と、ドロップダウンで選ぶ完全手動I/O設定の次期候補。2026-11-15の追加指示により、実装が完成してもApp Store・外部TestFlightで審査中のビルド6を取り下げない。ビルド7の署名・アップロードは、既存の審査対象・mainの割り当てを変更せずに行う。`upload_only` は審査提出・外部配布を行わない。`distribute_main`・`submit_store_review` は今回実行しない。ビルド6の承認後自動公開の設定は引き続き有効。

## 1.1.0以降の更新

2026-11-16にAPIで1.0.0の`READY_FOR_SALE`と旧レビューの`COMPLETE`を確認。その後のユーザーの明示指示で、1.1.0（ビルド15）をApp Store・外部TestFlightの両方へ提出する。公開済み1.0.0の取り下げは行わない。

`fastlane/Fastfile`、メタデータ、画像、提出用スクリプトは`project.yml`の`MARKETING_VERSION`と`CURRENT_PROJECT_VERSION`を参照する。新バージョンは`bundle exec ruby scripts/store_metadata.rb create`で作成する。他の未公開バージョンがある場合は停止し、既存バージョンを勝手に改名しない。日英の`release_notes.txt`をApp Storeの「このバージョンの最新情報」とTestFlightの更新説明の両方に使う。

```sh
bundle exec ruby scripts/store_metadata.rb metadata ja
bundle exec ruby scripts/store_metadata.rb metadata en-US
bundle exec ruby scripts/store_metadata.rb review_notes
```

審査連絡先は従来の非公開JSON、操作案内は`store/review-notes.en.txt`を使う。録画・写真の権限と、Device Hubを使ったマイク検証の制約も説明する。

撮影は日英・iPhone／iPad／Duoの6組、各6画面。Debug専用の`--store-capture`時だけSwiftUIでダーク表示を指定し、書き出し時も実画像の明度を検査する。通常起動・Release版の外観は変更しない。iPadは横向きで、画像の向きメタデータを反映してPNGへ正規化する。各組でメイン・EQ・ゲイン・録画・手動設定・タップ音ゲートを撮影する。周波数グラフやレイテンシーの架空の値は作らない。

署名・アップロードは前述のlaneを使用する。処理済みのビルドを`attach`で新バージョンへ選択してから、App Store審査と`main`への外部TestFlight審査をそれぞれ行う。ヘッダー／検索結果画像はAsset Libraryにある承認済み画像も再利用できる。提出前に日英の説明・更新内容、各組6枚のチェックサムと順序、処理・登録完了を読み戻して検証する。
