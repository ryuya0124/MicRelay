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

日本語・英語の156項目（アプリ155、マイク権限説明1）をString Catalogで管理。以下の初期多言語テスト時点は146項目。iPad・Duoシミュレーターの `artifacts/iPad-Localization.xcresult` / `artifacts/Duo-Localization.xcresult` で、日英それぞれのメイン・EQ・ゲイン入力エラー・ライセンス・バックアップ画面が成功。iPhone 17実機の同じ5画面は `artifacts/iPhone17-LocalizationFinal.xcresult` が成功（ゲイン入力エラーのUI操作はシミュレーターで確認）。日英の画面キャプチャも保存して目視確認した。

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

## 帯域フィルターと風切り音低減（ビルド6）

バンドストップ／バンドパスに下限・上限の数値入力、スライダー、範囲のハイライトと境界ドラッグを追加。20〜20,000 Hz、最小間隔1 Hz。1段のbiquadで両端約−3 dBとなり、低サンプルレートで表現できない上側は単一のハイ／ローカットへ変換する。既存4種類の番号・設定値は維持した。

独立した風切り音低減を追加。初期OFF・120 Hz、60〜600 Hzの4次Butterworthハイパス。先読み・追加の再生バッファ・OSの声の分離は使わない。OFFは完全バイパス。解析の「処理後」は風切り音低減とEQの両方を通したゲイン前の値となる。バックアップ形式2に追加し、従来の形式1も読み込める。

`artifacts/Duo-Wind6-Units.xcresult` の43テストが成功。帯域フィルターの−3 dB境界・補完応答・実信号の通過／減衰・1 Hzの狭い範囲・ナイキスト周辺を確認。風切り音低減は8〜192 kHzで周波数応答、30 Hz＋1 kHzの混合信号、OFF時の値と状態の完全不変、最初のサンプルで出力すること、カット周波数変更時の安定性を検証。設定保存、形式2往復、旧形式1と保存済みゲイン・EQの互換、不正値の拒否も含む。

iPadシミュレーターで日英の帯域フィルター画面と、日英の風切り音低減ON/OFF・周波数調整・再ON後の値の維持を確認。記録は `artifacts/iPad-Wind6-UI.xcresult`（帯域2件成功）、`artifacts/iPad-Wind6-UI-Final.xcresult`（風切り音2件成功）。前者の風切り音UIテストはスイッチではなく行中央をタップして失敗したため、実際のスイッチ位置をタップするテストへ修正し、後者で成功した。日英156項目と翻訳交換ツール6テストも成功。

ビルド6の実機確認はユーザーの「実機は後で」という指示に従い延期。新フィルターの実マイク音・風音・背景継続・音響総遅延は未検証。シミュレーターと決定的な信号処理テストの結果を、実機音声の確認済みという意味では使わない。

## 配布状態（ビルド6・帯域フィルターと風切り音低減）

Apple Distribution署名を検証した1.0.0（ビルド6）をFastlaneでアップロードし、Apple側の `VALID` を確認。ビルド5のBeta App Reviewを取り下げてmainから外し、ビルド6だけを外部mainへ割り当てた。状態は `WAITING_FOR_BETA_REVIEW` / `WAITING_FOR_REVIEW`。日英のBeta説明・テスト項目とストア説明・キーワードを読み戻して確認した。外部インストールはAppleのBeta承認後。

App Store本体はビルド6を選択した `PREPARE_FOR_SUBMISSION` / `MANUAL` の下書きで、App Review提出0件。IPA SHA-256：`816a6bc977a141bf9548eee3ffd7213dcd02890d94b53991d09ae0d2897d8ff8`。非公開の確認記録は `artifacts/wind-release-final.json`、画面は `artifacts/testflight-main-build6.jpg`。実装コミット `02b600b` の [Localization CI](https://github.com/ryuya0124/MicRelay/actions/runs/43635470010) も成功。


## ストア画像の向き・テーマ修正

iPad画像の文字が横倒しになり、Duo画像がライト表示のままだったことを確認。撮影したUIImageの向きを反映せずにPNGへ変換していたことと、撮影テーマを固定していなかったことが原因だった。撮影時の描画で向きを反映し、ダーク表示を指定した。書き出しでも画像の向きを考慮し、iPadの縦横比を維持する。旧アセット生成処理からは、過去の撮影画像を再利用してストア画像を上書きする経路を取り除いた。

`artifacts/iPad-StoreDark-Corrected.xcresult` と `artifacts/Duo-StoreDark-Corrected.xcresult` で日英の撮影テスト各2件が成功。iPadは2752×2064、Duoは現在の外側画面の2034×1398で、文字が正立したダーク表示を保存。モニター・EQ・ゲイン設定を各3枚、日英・2機種の計12枚を確認した。音声は停止状態の実画面で、波形等の合成はない。撮影後のシミュレーターの外観は元のライトへ戻した。実機は操作していない。

App Store Connectの対象4セットを新画像に差し替え、12枚すべての `COMPLETE`・順序・ソースチェックサムを読み戻して一致を確認。旧画像を外し、iPhoneの既存画像IDは維持した。Appleの配信用画像も取得して向きとテーマを確認した。記録は非公開の `artifacts/store-shots-after-correction.json`、`artifacts/screenshots-*-verified.json`。

## App Store本体の審査提出

ユーザーの指示で、1.0.0（ビルド6）をApp Store本体の審査へ提出。2026-11-15 12:50 JSTに `WAITING_FOR_REVIEW` をAPIとApp Review画面で確認した。承認後の公開方法も、追加指示に従って `AFTER_APPROVAL`（自動公開）に変更し、提出後に読み戻した。公開方法は `store/release-policy.json` に記録し、以後のメタデータ更新でもこの設定を使う。

事前に日英の説明、全18枚の画像の登録完了・順序・チェックサム、選択ビルド、輸出コンプライアンス、審査用連絡先・操作案内を確認した。最初の提出検証ではプライバシー回答の未公開が不足項目として返った。Appleの公開確認文を提示してユーザーの明示的な同意を受け、「データ収集なし」を公開。その後にFastlaneの `ios submit_store_review` が成功した。これは審査承認やストア公開の完了ではない。

非公開の提出記録は `artifacts/release/appstore-review-submission.json`、確認画面は `artifacts/appstore-review-submitted.jpg`、プライバシー回答の公開画面は `artifacts/app-privacy-published.jpg`。審査連絡先などはリポジトリに含めない。

## ビルド7候補：自動レート探索・完全手動I/O

自動選択をサンプルレート候補まで拡張した。希望値とは別に実レートを記録し、同じモード・実レートの安定した経路が既に探索済みの場合は重複探索を省く。入力＋出力のOS報告値と実I/O時間で比較し、最高レートを優先しない。稼働後の調整下限は実際に選択したレートの観測値に限定する。

完全手動は標準／測定・フレーム数・サンプルレートをドロップダウンで選ぶ。保存前にハードミュートしたRemoteIOで確認し、実レート・実コールバックの最小／最大・実I/O時間・実モードが一致し、入力が安定した場合だけ保存する。浮動小数の表現誤差だけを許容し、48,000.1 Hzの要求を48,000 Hzとして受け入れることはない。不一致、入力不安定、APIエラー、接続変更を通知し、前の保存設定と選択値を復元する。モニター中の成功時は検証済みのAudio Unitをそのまま使用し、失敗時は前の設定で再開する。ゲイン・上限・EQ・風切り音低減は検証のために保存し直さない。

`artifacts/iPad-Manual7-Menus.xcresult` で単体51件と日英の画面2件、`artifacts/Duo-Manual7-Menus-Final.xcresult` で日英の画面2件が成功。UIテストでは実際の設定要求と実値の不一致、要求・実値・復元通知、選択値の復元、自動モードの保持、自由入力欄がないことを確認した。iPadでは画面上のゲイン保持も確認。単体テストは拒否時の保存データ・ゲイン・上限保持、一致時だけの保存、微小な要求差の拒否、実レートに応じた選択、バックアップv3と旧v1・v2の互換を含む。日英183項目と翻訳交換ツール6テストも成功。

この環境のシミュレーターはRemoteIOの入力取得で `kAudioUnitErr_NoConnection`（-10876）を返した。値が一致しても入力の安定性を確認できなければ保存しないことを確認し、その場合に「値の不一致」と誤表示しないようにした。成功条件の保存は単体テストで確認しており、実機での手動設定の適用成功・実音・音響総遅延・ゲーム同時起動は未検証。以前の11.7〜12 msからの追加短縮は計測していない。シミュレーター用のスピーカー許可引数はDebugかつシミュレーターに限定され、入力信号の合成や音声出力処理の置き換えはない。

バックアップはv3。既存の有効な保存値がドロップダウンの標準候補に含まれなくても、その値を選択肢に追加して保持する。今回の追加指示に従い、完成後もApp Store・外部TestFlightのビルド6を取り下げない。ビルド7は別候補として扱う。

### ビルド7の署名・アップロードと実機更新

FastlaneでApple Distribution署名の1.0.0（ビルド7）を作成し、書き出したIPAの署名・Bundle ID・ビルド番号を検証した。SHA-256は `6a33e16c257f0e18de4180ce3b6f22e31300c7970cd1e4e9436c4359d599e609`。ビルド6のIPAもハッシュ不変を確認して保持している。`upload_only` でアップロードし、2026-11-15 23:40 JSTの読み戻しでビルド7の `VALID`・Beta審査提出なし、App Storeの選択ビルド6・`WAITING_FOR_REVIEW`・`AFTER_APPROVAL`、外部mainはビルド6のみであることを確認した。取り下げ・審査対象の差し替え・ビルド7の審査提出は行っていない。非公開の記録は `artifacts/release/manual7-signed.json` と `artifacts/release/manual7-connect-verified.json`。

その後、ユーザーの「実機更新も」に従い、Apple Development署名のビルド7をアプリ削除なしで上書きインストールした。iPadは6→7、iPhone 17は5→7となり、両端末のインストール情報から確認した。iPadの保存設定は更新前後で完全一致し、ゲイン400%・上限400%・保存済みEQ・自動モードを保持。iPhoneは標準設定ファイルが更新前から存在せず、Preferences内の既存43ファイルのハッシュが全て一致した。

iPhoneは通常起動に成功した。iPadは端末ロックで起動要求を拒否された。追加のiPhone実機画面テストは自動化モード初期化のタイムアウトで開始できず、画面を実機検証済みとは扱わない（`artifacts/iPhone17-Manual7-Menus.xcresult`）。ユーザーから改めて「起動・音声の確認は後で」との回答を受け、以降の実機操作・音声確認を保留した。再起動・アプリ削除・設定の初期化は行っていない。

## ビルド8候補：解析・表示転送の効率化

解析用の一時配列除去、実レートごとの周波数表と解析区間の再利用、FFT用メモリの初回使用までの確保延期、波形のFloat直接転送、解析リングの連続コピー、手動候補リストの共有を実装。詳細と補助測定の再現手順は [PERFORMANCE.md](PERFORMANCE.md)。

`artifacts/iPad-Efficiency8-Checks.xcresult` で単体57件と日英の手動I/O・帯域フィルター画面4件が成功。追加した初回解析・メモリ確保延期のテストを含む `artifacts/iPad-Efficiency8-Storage.xcresult` で、解析・ネイティブコピーの8件が成功（既存検証と合わせて単体58件）。旧FFTとの全点一致、レートの切り替え、保持フレーム、読み取り境界、ネイティブFloatのSwift受け渡しを含む。日英183項目と翻訳交換ツール6テストも成功。

M5 Max上の補助測定は旧51.31→新45.39 µs/入力・処理後のFFT1組、約11.5%短縮。生の記録は非公開の `artifacts/efficiency8/spectrum-benchmark-alternating.json`。これは音響総遅延や実機のCPU使用率の測定ではない。ビルド7のRemoteIO render関数とビルド8の関数本体はソース比較で完全一致。EQ・風切り音低減・ゲイン・I/O選択の計算は変更していない。

iOS向けReleaseビルド（署名なし）とApple Development署名の実機用ビルドが成功。前回の更新依頼に合わせ、iPadはアプリを削除せず7→8へ更新し、Preferences内64ファイルのハッシュが全て一致した。ゲイン400%・上限400%・EQ・自動モードを保持し、インストール情報からビルド8を確認。iPhone 17はCoreDeviceの接続条件を満たせず（4016）更新を保留した。端末の起動・音声確認、App Store Connectへのアップロード、審査の差し替えは行っていない。
