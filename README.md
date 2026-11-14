# MicRelay

同じiPhone / iPadのマイク音声を、接続したイヤホンやHDMI機器へリアルタイムに返すSwiftUIネイティブアプリ。iOS / iPadOS 18以降。iPhone Duoの開閉・回転時も利用可能な画面幅に追従します。

## 使い方

1. 有線・Bluetoothイヤホン、またはHDMI機器を接続します。
2. 「接続とマイクを更新」でマイクへのアクセスを許可します。
3. 本体マイク、またはiOSが利用可能として公開する外部マイクを選びます。
4. Bluetooth / USB / ライン出力の場合は、接続先がイヤホンであることを確認します。
5. 「モニターを開始」を押します。ゲインとシステム音量は別々に調整できます。

イヤホン・HDMI機器が未接続の場合は既定で開始できません。「本体スピーカーを使う」を明示的にONにした場合だけ、本体スピーカーを許可します。この設定はアプリ起動時にOFFに戻ります。モニターゲインのスライダー上限は設定画面で任意の正の数値に変更できます。初期の上限は200%で、アプリ独自の固定上限はありません。現在のゲインと上限は再起動・マイクや出力先の変更後も維持します。音声のフルスケールを超えた信号はクリップします。

「画面を閉じても続ける」は初期状態でONです。バックグラウンド音声と `mixWithOthers` を使い、ゲームや音楽と同時再生します。同じマイク・出力先のまま共有オーディオ設定が変更された場合は再構成し、OSが再開を許可した割り込み終了後も同じ接続なら再開します。イヤホンの切断や出力機器の変更では停止し、再開は手動です。他アプリがマイクを排他的に使用する場合などは、OSの制約により中断することがあります。

## 音質と設定

「イコライザー」で6バンドの周波数・増減・Qを調整できます。増減、ノッチ、ローカット、ハイカット、バンドストップ、バンドパスを選べます。バンドストップは指定範囲を減衰し、バンドパスは指定範囲だけを通します。追加した2種類は下限・上限の周波数を指定し、グラフの範囲表示を見ながら境界をドラッグできます。境界は約-3 dBの位置です。OFF時はIIRを完全にバイパスし、フィルター状態を読み進めません。ON時は同じRemoteIOコールバック内で処理し、先読みや再生バッファは追加しません。係数は約5 msで補間します。フィルター由来の位相・群遅延は周波数ごとに異なります。

「風切り音低減」は独立したON/OFFと60〜600 Hzの低域カット調整に対応します。初期値はOFF・120 Hzです。4次のハイパスで低域の風音を減らし、先読みや音声バッファを追加しません。値を上げると声の低音も減ります。広帯域の風音やマイクで既に歪んだ信号を完全に除去する機能ではありません。OSのマイクモードは変更しません。[フィルターと遅延の説明](docs/EQUALIZER.md)も参照してください。

入力と風切り音低減・EQ処理後（出力ゲイン前）の周波数スペクトラムを別キューの4096点Hann窓FFTで表示します。解析専用SPSCリングが満杯でも解析用データだけを捨て、音声出力は待ちません。画面を閉じる・バックグラウンドへ移ると解析表示を停止します。

音声モードは「自動／標準／測定」から選択できます。自動は各モードのバッファ候補を実際に動かし、入力・出力のOS報告値と実I/Oの合計が短い組み合わせを選びます。手動は選んだモード内でバッファを調整します。

「設定のバックアップと復元」からゲイン・上限・EQ・風切り音低減・音声モード・背景継続・入力マイクをJSONへ書き出し、ファイルから復元できます。形式・版・数値範囲を全て検証してから適用します。新規書き出しは形式バージョン2で、旧バージョン1のバックアップも読み込めます。スピーカー許可と接続先の確認は引き継がず、復元時はモニターを停止します。元のマイクが利用できない場合は本体マイクを選びます。

iPadなどの広い画面は標準SwiftUIのFormを2列で表示し、狭いウインドウは1列に切り替えます。外観はOSのライト／ダーク設定に従います。

日本語・英語に対応し、OSの優先言語とアプリ別言語設定に従います。画面・状態・エラー・読み上げ・マイク権限の説明をString Catalogで管理しています。[言語追加と翻訳の検証手順](docs/LOCALIZATION.md)では、翻訳用JSONの書き出し・取り込みも説明しています。

## 低遅延の構成

- RemoteIO Audio Unitの出力コールバックから直接入力を取得し、そのコールバックで出力します。
- 48 kHzを希望し、実際に採用されたサンプルレートで処理します。開始時に1・2・4・8・16・32・64・128・256・512・1024・2048フレームを小さい順に試します。要求が成功しても実バッファが変わらない場合があるため、実コールバックのサイズ・処理フレーム数・欠落も照合します。要求どおりのサイズで安定した候補が見つかると、そのモードの探索を終えます。
- 起動時の猶予後、2秒の監視窓で3ブロック以上の入力欠落、または継続的な入力取得失敗を検出すると、バッファを段階的に広げます。30秒以上安定すると下限へ向けて半減を試し、失敗した再試行は間隔を最大300秒まで延ばします。端末モデル別の固定値はありません。
- 自動調整はバックグラウンドでも実行します。バッファ変更時はAudio Unitを再構成するため短いミュートが入ります。背景では音声セッションを維持します。前面で大きなバッファが続く場合は、安定後に下限を再探索します。上限でも入力が確保できなければ停止します。
- セッションは `playAndRecord` + `mixWithOthers`。前面での開始・再探索時は、候補ごとにセッションを無効化して希望値を適用し、再び有効化して比較します。比較中は出力のみミュートし、保存ゲイン・EQ設定は変更しません。VoiceProcessingIO、録音ファイル、プレーヤー、追加のFIFOは使いません。
- リアルタイム処理は最適化したObjective-C++。コールバック内にSwift / Objective-C呼び出し、ロック、メモリ確保、ファイル書き込み、ログ出力はありません。
- 波形・メーターはロック不要のアトミック変数からUIが読み取ります。波形を描くために音声を待たせません。
- 開始直後などに入力が一時的に利用できないブロックは無音にして捨てます。古い入力を再生するための待ち行列は作りません。連続して失敗する場合は停止します。
- ルート変更・割り込みの通知を受けたスレッドで音声ゲートを閉じ、メインスレッドのUI更新より先にミュートします。OS側の切断時割り込みにもオプトインします。

表示されるI/Oバッファ時間は、マイクから耳までの総遅延を意味しません。入出力デバイス、AD/DA、OSの安全バッファ、Bluetoothの無線伝送・コーデック遅延が加わります。OS報告値も音響ループバックによる実測値ではありません。[KA13での比較記録とEQの遅延](docs/LATENCY.md)を参照してください。BluetoothマイクはHFPを使用し、入力を選ぶと出力側の通信方式・音質も変化する場合があります。高品質Bluetooth録音オプションは、遅延増加を避けるため使用しません。

Bluetooth・USB機器のイヤホン/スピーカー種別を完全には判定できないため、接続ごとの確認が必要です。HDMIは追加確認なしでモニター出力先として許可します。AirPlay、CarPlay、受話口はモニター出力先として許可しません。Bluetoothの組み合わせによっては希望する入力・出力をOSが同時に選べない場合があり、その場合は別のマイクに勝手に変更せず停止します。

## ビルド

`MicRelay.xcodeproj` をXcodeで開き、署名チームと実機を選んで実行します。外部ライブラリは不要です。

```sh
# プロジェクトの再生成が必要な場合のみ（Homebrewのxcodegen）
xcodegen generate

xcodebuild -project MicRelay.xcodeproj -scheme MicRelay \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates build
```

`project.yml` がプロジェクト設定の元です。Bundle IDは所有ドメイン `ryuya-dev.net` の逆順による `net.ryuya-dev.MicRelay` です。iOS 26以降のアイコンは `MicRelay/Resources/AppIcon.icon` の2層構成で、Liquid Glass・ダーク・Clear・Tintedに対応します。AppleのIcon Composerレンダラーによる [6種類のプレビュー](store/icon-previews/appearances.png) があります。`scripts/export-icon-previews.sh` で再生成できます。旧OS向けの不透明アイコンは `swift scripts/generate-icon.swift` で生成します。

## ソース管理・署名・App Store Connect

公開リポジトリは [ryuya0124/MicRelay](https://github.com/ryuya0124/MicRelay) です。アプリ自身のソース・アセットは [MIT](LICENSE) です。依存パッケージの著作権・ライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) に収録し、アプリ内の専用ライセンス画面でも本文を閲覧できます。実行時のApple標準フレームワークと、開発用Fastlane/Bundler等105パッケージの範囲を区別しています。

Fastlaneのセットアップと、審査提出を行わないアップロード手順は [docs/RELEASE.md](docs/RELEASE.md) を参照してください。APIキー・証明書の秘密鍵・プロビジョニングプロファイル・IPA・実機ログはリポジトリに含めません。

## 動作診断

「レイテンシー → 動作診断」に処理フレーム数、実際の入力/出力ピーク、音声エラー、一時的に欠落したブロック数、バックグラウンド中に処理したフレーム数と時間を表示します。入力波形は実マイクの信号です。小さい音を見やすくするため描画のみ固定倍率で拡大しています。

Debugビルドは停止時・バックグラウンド復帰時にアプリ内 `Documents/diagnostics.json` に数値診断を保存します。音声・波形サンプルは保存しません。検証結果と残る確認項目は [docs/VALIDATION.md](docs/VALIDATION.md) を参照してください。

## Appleの仕様

- [I/Oバッファの希望値と実値](https://developer.apple.com/documentation/avfaudio/avaudiosession/preferrediobufferduration)
- [接続変更時の取り扱い](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioHardwareRouteChanges/HandlingAudioHardwareRouteChanges.html)
- [Background Modes](https://developer.apple.com/documentation/Xcode/configuring-background-execution-modes)
- [Bluetooth HFP入力](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetoothhfp)
- [高品質Bluetooth録音の遅延に関する注意](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/bluetoothhighqualityrecording)

[サポート](docs/SUPPORT.md) / [プライバシーポリシー](docs/PRIVACY.md)

外部TestFlight： [mainへ参加](https://testflight.apple.com/join/57HvuCWz)（初回Beta App Reviewの承認後にインストール可能）。
