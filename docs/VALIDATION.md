# 検証記録

2026-11-15 / Xcode 27.2 (27B48)。iPhone 17 / iPad Pro 13 M4、iOS・iPadOS 27.0.1で検証。

## 実機

- iPhone 17：本体マイク → 明示的に許可した本体スピーカー。イヤホンは未接続。
- iPad：本体マイク → Apple USB-C - 3.5mmヘッドフォンジャックアダプタとイヤホン。
- 実マイクの入力波形、入力・出力の非ゼロ信号、音声エラー0、ホームへ移動して12秒後に戻るまでの背景処理を確認。
- EQ OFFの入力・EQ後スペクトラムは一致。ONの実マイク解析では差分が3 dBを超えることを確認。合成波形をUIに表示する検証ではない。
- 6バンドEQのハードバイパス（値と状態が完全不変）、中心で-18/+12 dB、ノッチ100 dB超減衰、ハイ・ローカットの通過域と阻止域を決定的信号で検証。
- FFTは既知の正弦波の周波数・-6.02 dBFSと無音を検証。
- 設定の保存、大きなゲイン上限、バックアップのJSON往復、不正値・将来版・過大ファイル・重複バンドIDの拒否を検証。
- 専用ライセンス画面と依存ライブラリの全文を実機UIで確認。

結果は非公開の `artifacts/iPhone17-Backup-Release.xcresult` と `artifacts/iPad-Backup-Release.xcresult`（各25テスト）に保持。後から追加した音声モード選択を含むビルドは `artifacts/iPhone17-Modes.xcresult` と `artifacts/iPad-Modes.xcresult` のユニット・UI確認で成功。ストア画像もこれらの実画面から取得。

## レイテンシー

以下は各試験時点のOS報告値であり、マイクから耳までの音響実測値ではない。

|経路・試験|入力|出力|I/O|実コールバック|
|---|---:|---:|---:|---:|
|iPhone 17 本体マイク→スピーカー、初期試験|0.875 ms|9.729 ms|0.667 ms|32 frames|
|iPad USB-Cアダプタ、測定モード比較|0.292 ms|17.542 ms|3.000 ms|144 frames|
|同経路、標準モード比較|1.292 ms|1.042 ms|3.000 ms|144 frames|
|iPad最終ストア画面取得時、標準|1.292 ms|1.042 ms|21.333 ms|1024 frames|

自動選択は入力だけで判断せず、入出力と実I/Oの合計が短い標準モードを選択した。44.1/96 kHzの希望値も試したが、アダプタの実値は48 kHzだった。最終試験では1フレーム要求でもOS共有音声環境が1024フレームを採用した。3 msを常時達成するという主張はしない。要求値は端末モデルで固定せず、OS・機器・同時稼働アプリに従う。

### ビルド4のバッファ探索

FIIO KA13を接続したiPadで、1〜8フレームの要求成功時も以前の実バッファが残ることを確認。要求を小さくするだけでは下限を確認できないため、実コールバックと処理量を比較する探索へ変更した。本体マイク・EQ ONのまま16フレーム / 48 kHz（I/O 0.333 ms）で動作した。入出力のOS報告値は標準で1.292 / 0.292 ms、測定で0.292 / 16.792 msだった。変更前の約47 msに対し、ビルド5の外部再測定としてユーザーから総遅延11.7〜12 msの報告を受けた。[条件・比較・EQの遅延](LATENCY.md)に記録。

`artifacts/iPad-Latency4.xcresult` と `artifacts/iPhone17-Latency4.xcresult` で、ユニットと実マイク・背景継続・EQスペクトラム・ライセンス・安全な初期状態のUIテストが成功。512・1024・2048のフォールバック候補と観測処理量の検証を追加した版は `artifacts/iPhone17-Latency4-Final.xcresult` が成功。iPad実機の後続確認はビルド5の記録を参照。

## ゲーム併用

日本語版プロセカ `com.sega.pjsekai` 7.1.0をiPadで実際に起動。`mixWithOthers` 適用後、ゲームが前面の間に648,720フレーム / 13.515秒を処理し、欠落・音声エラーとも0。試験中にユーザーが設定したゲイン1000%も維持した。すべてのゲーム状態・マイク排他利用への継続を保証するものではない。

## レイアウト・成果物

標準SwiftUIのFormを採用。広いiPadとDuo横向きでは2列、狭い幅は1列。専用iPhone DuoシミュレーターをDevice HubでClosed / Open / Partially Open / Rotate / Closedと操作し、画面幅だけの模擬試験とは別に確認。ライト・ダークに追従。ストア用には実機iPhone・iPadとネイティブDuoのキャプチャを使用。

FastlaneでApple Distribution署名のReleaseアーカイブ・IPAを作成。最終ゲイン初期値200%と旧設定の維持は `artifacts/iPad-Gain200.xcresult` の21ユニットテストが成功。

Releaseでは数値診断ファイルの保存や自動検証の起動処理を含めない。

## 残る確認

Bluetooth機器、マイク付きイヤホン、別のUSBインターフェイス、実機Duo、通話・アラーム・各種ゲームでの割り込み、長時間・高負荷運転、その他の経路・条件での総遅延は未確認。KA13での総遅延は上記のユーザーによる外部計測の報告で、測定波形や詳細な計測手順は未取得。ファイルピッカーのクラウドストレージごとの保存・復元は未確認（JSON形式の入出力・検証はテスト済み）。

## HDMI出力（ビルド5）

OSが `AVAudioSession.Port.HDMI` として報告する出力を、追加のイヤホン確認や本体スピーカー許可なしでモニター出力として許可した。出力の切断・変更では従来のゲート閉鎖と停止処理が適用される。HDMIと許可していない出力が混在する場合は開始できない。

`artifacts/iPhone17-HDMI5.xcresult` でユニットテストと日英5画面・安全な初期状態のUIテストが成功。HDMI単独、接続先UIDが異なるHDMI、イヤホンとの混在、許可していない本体スピーカー・AirPlayとの混在を判定テストで確認した。日英の案内・マイク権限文・ストア説明も更新。HDMI機器は接続できないため、HDMI実機の音声出力・切断・遅延は未検証。

iPad実機のロック解除後、`artifacts/iPad-HDMI5-Final.xcresult` で29ユニットテストと実マイク・バックグラウンド継続のUIテストが成功。FIIO KA13＋本体マイク＋保存済みEQ ONで、標準モード・48 kHz・実コールバック16フレーム / I/O 0.333 msを確認。追加の66秒間に3,135,664フレームを処理し、新たな欠落0・音声エラー0だった。保存済みゲイン・上限・EQの値を前後比較し、維持したことも確認した。これはHDMI試験や音響総遅延の測定ではない。

## 多言語表示

日本語・英語の146項目（アプリ145、マイク権限説明1）をString Catalogで管理。iPad・Duoシミュレーターの `artifacts/iPad-Localization.xcresult` / `artifacts/Duo-Localization.xcresult` で、日英それぞれのメイン・EQ・ゲイン入力エラー・ライセンス・バックアップ画面が成功。iPhone 17実機の同じ5画面は `artifacts/iPhone17-LocalizationFinal.xcresult` が成功（ゲイン入力エラーのUI操作はシミュレーターで確認）。日英の画面キャプチャも保存して目視確認した。

コンパイル済みの日本語・英語・マイク権限文、差し込み値、日米独仏の小数点・大きな上限値の往復、入力末尾の不正文字の拒否をSwiftのユニットテストで確認。翻訳交換ツールは標準Pythonの6テストで、形式指定の不一致・空欄・古い原文を拒否し、言語追加を反映することを確認した。

iPhone 17の全ユニットテストの最終記録は `artifacts/iPhone17-LocalizationUnits.xcresult`。GitHub Actionsの [Localization](https://github.com/ryuya0124/MicRelay/actions/runs/43626769294) も成功。

英語ストア画像は実機iPhone 17とiPad・Duoシミュレーターで各3枚を撮影。モニター停止状態の実画面を使用し、周波数データや音声値を描き足していない。App Store Connectへの登録状態は下記の配布状態で別途記録する。

App Store Connectの英語（米国・`en-US`）に説明・サブタイトル・キーワード・英語サポート/プライバシーURLを登録。iPhone・iPad・Duoの各3枚、計9枚はApple側の `COMPLETE` を確認した。確認時点でApp Store本体は `PREPARE_FOR_SUBMISSION`、App Review提出は0件。

英語のヘッダーと検索結果用画像も共通の自作アセットを配置し、両方の `placement_state: ACTIVE` を確認した。英語選択中のストア画面は非公開の `artifacts/appstore-English.jpg` に保存。

## 配布状態（ビルド4・更新後）

1.0.0（ビルド4）はApple Distribution署名を検証し、Fastlaneでアップロード。Apple側の `VALID` を確認した。IPAには日本語・英語の `.lproj` とローカライズ済み権限文を同梱。IPA SHA-256：`9a2e9a7ff4b14e0369c96ed3820f529f262dd58b924cec1022d7db7239a94432`。

ビルド3のBeta App Reviewを取り下げ、外部グループmainから除外。ビルド4だけをmainへ割り当て、Beta App Reviewへ提出した。確認時点は `WAITING_FOR_BETA_REVIEW` / `WAITING_FOR_REVIEW`。TestFlightの説明・テスト項目も `ja` / `en-US` の両方を読み戻して確認した。公開リンクは [main](https://testflight.apple.com/join/57HvuCWz) のままで、外部インストールは承認後に可能となる。

App Store本体の下書きにもビルド4を選択。`PREPARE_FOR_SUBMISSION` / `MANUAL`、App Review提出0件をAPIで再確認した。英語ストア情報と画像は保存済みで、App Store本体の審査提出・公開は行っていない。非公開の確認記録は `artifacts/bilingual-release-final.json`。

## 配布状態（ビルド5・HDMI対応）

Apple Distribution署名を検証した1.0.0（ビルド5）をFastlaneでアップロードし、Apple側の `VALID` を確認。ビルド4のBeta App Reviewを取り下げてmainから外し、ビルド5だけを外部mainへ割り当て、Beta App Reviewに提出した。状態は `WAITING_FOR_BETA_REVIEW` / `WAITING_FOR_REVIEW`。日英の説明とテスト項目を確認した。

App Store本体はビルド5を選択した `PREPARE_FOR_SUBMISSION` / `MANUAL` の下書きで、App Review提出0件。日英のストア説明・キーワードもHDMI対応へ更新。IPA SHA-256：`5648b599f8d769b61b37a831b53bf13c3e4f9f9012ac9623e873d967841c08a0`。非公開の確認記録は `artifacts/hdmi-release-final.json`、画面は `artifacts/testflight-main-build5.jpg`。

## 配布状態（ビルド3時点）

公開MITソース：[ryuya0124/MicRelay](https://github.com/ryuya0124/MicRelay)。App Store ConnectはアプリID `6834848400`、Bundle ID `net.ryuya-dev.MicRelay`、1.0.0（ビルド3）。Apple Distribution署名を照合済み。初回アップロードの1.0（ビルド1）は外部グループに割り当てていない。画像生成の不具合があったビルド2はmainから除外し、レイヤー付きアイコンのビルド3へ差し替えた。

外部TestFlight [main](https://testflight.apple.com/join/57HvuCWz) へビルド3を割り当て、Beta App Reviewに提出。確認時点は `WAITING_FOR_BETA_REVIEW` / `WAITING_FOR_REVIEW`。App Store本体は `PREPARE_FOR_SUBMISSION`、App Review提出なし、手動リリースのまま。

ストアのiPhone3枚・iPad3枚・Duo2枚はApple側で `COMPLETE`。日本語説明・サブタイトル・キーワード・サポート/プライバシーURL・年齢区分申告・ユーティリティ/ミュージック分類・自作アイコンとヘッダー/検索用画像を登録。IPA SHA-256：`8b42f61585d1ecc3d54e01b8acf495169ccc5cd03ead62cdc820c149150732cc`。

アイコンはApple Icon Composer形式（2つのSVGレイヤー、屈折・ハイライト・半透明）を採用。Default / Dark / ClearLight / ClearDark / TintedLight / TintedDarkをAppleのictool 27.2で描画して確認。配布アーカイブのAssets.car内にもLight / Dark / TintableのIconImageStackと各レイヤーを確認した。旧OS向けの不透明アイコンも同梱。App Storeのプライバシー回答は「データ収集なし」の下書きで、公開前の宣誓は未実行。無料・日本1地域の提供設定を保存。
