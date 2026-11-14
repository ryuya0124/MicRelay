# MicRelay

同じiPhone / iPadのマイク音声を、接続したイヤホンへリアルタイムに返すSwiftUIネイティブアプリ。iOS / iPadOS 18以降。iPhone Duoの開閉・回転時も利用可能な画面幅に追従します。

## 使い方

1. 有線またはBluetoothイヤホンを接続します。
2. 「接続とマイクを更新」でマイクへのアクセスを許可します。
3. 本体マイク、またはiOSが利用可能として公開する外部マイクを選びます。
4. Bluetooth / USB / ライン出力の場合は、接続先がイヤホンであることを確認します。
5. 「モニターを開始」を押します。ゲインとシステム音量は別々に調整できます。

イヤホン未接続時は既定で開始できません。「本体スピーカーを使う」を明示的にONにした場合だけ、本体スピーカーを許可します。この設定はアプリ起動時にOFFに戻ります。モニターゲインのスライダー上限は設定画面で任意の正の数値に変更できます。初期の上限は200%で、アプリ独自の固定上限はありません。現在のゲインと上限は再起動・マイクや出力先の変更後も維持します。音声のフルスケールを超えた信号はクリップします。

「画面を閉じても続ける」は初期状態でONです。バックグラウンド音声と `mixWithOthers` を使い、ゲームや音楽と同時再生します。同じマイク・出力先のまま共有オーディオ設定が変更された場合は再構成し、OSが再開を許可した割り込み終了後も同じ接続なら再開します。イヤホンの切断や出力機器の変更では停止し、再開は手動です。他アプリがマイクを排他的に使用する場合などは、OSの制約により中断することがあります。

## 音質と設定

「イコライザー」で6バンドの周波数・増減・Qを調整できます。増減、ノッチ、ローカット、ハイカットを選べます。OFF時はIIRを完全にバイパスし、フィルター状態を読み進めません。ON時は同じRemoteIOコールバック内で処理し、先読みや再生バッファは追加しません。係数は約5 msで補間します。フィルター由来の位相・群遅延は周波数ごとに異なります。

入力とEQ後（出力ゲイン前）の周波数スペクトラムを別キューの4096点Hann窓FFTで表示します。解析専用SPSCリングが満杯でも解析用データだけを捨て、音声出力は待ちません。画面を閉じる・バックグラウンドへ移ると解析表示を停止します。

音声モードは「自動／標準／測定」から選択できます。自動は実測したOS報告値の合計が短い方を選び、手動は選んだモードを使います。I/Oバッファの自動調整は両方で継続します。

「設定のバックアップと復元」からゲイン・上限・EQ・音声モード・背景継続・入力マイクをJSONへ書き出し、ファイルから復元できます。形式・版・数値範囲を全て検証してから適用します。スピーカー許可と接続先の確認は引き継がず、復元時はモニターを停止します。元のマイクが利用できない場合は本体マイクを選びます。

iPadなどの広い画面は標準SwiftUIのFormを2列で表示し、狭いウインドウは1列に切り替えます。外観はOSのライト／ダーク設定に従います。

## 低遅延の構成

- RemoteIO Audio Unitの出力コールバックから直接入力を取得し、そのコールバックで出力します。
- 48 kHzを希望し、実際に採用されたサンプルレートで処理します。I/Oバッファは1サンプル相当から要求し、OS・接続機器が許す下限を実際のコールバックと照合します。希望値が拒否されるOSでは小さい候補から順に試します。
- 起動時の猶予後、2秒の監視窓で3ブロック以上の入力欠落、または継続的な入力取得失敗を検出すると、バッファを段階的に広げます。30秒以上安定すると下限へ向けて半減を試し、失敗した再試行は間隔を最大300秒まで延ばします。端末モデル別の固定値はありません。
- 自動調整はバックグラウンドでも実行します。バッファ変更時はAudio Unitを再構成するため短いミュートが入ります。音声セッションは維持します。上限でも入力が確保できなければ停止します。
- セッションは `playAndRecord` + `mixWithOthers`。開始時に `default` / `measurement` の実際の入出力報告遅延とI/Oを比較し、合計の短いモードを選びます。同じ接続先・入力の結果はアプリ起動中に再利用します。比較中は出力のみミュートし、保存ゲインは変更しません。VoiceProcessingIO、録音ファイル、プレーヤー、追加のFIFOは使いません。
- リアルタイム処理は最適化したObjective-C++。コールバック内にSwift / Objective-C呼び出し、ロック、メモリ確保、ファイル書き込み、ログ出力はありません。
- 波形・メーターはロック不要のアトミック変数からUIが読み取ります。波形を描くために音声を待たせません。
- 開始直後などに入力が一時的に利用できないブロックは無音にして捨てます。古い入力を再生するための待ち行列は作りません。連続して失敗する場合は停止します。
- ルート変更・割り込みの通知を受けたスレッドで音声ゲートを閉じ、メインスレッドのUI更新より先にミュートします。OS側の切断時割り込みにもオプトインします。

I/Oバッファの0.667 msは、マイクから耳までの総遅延を意味しません。入出力デバイス、AD/DA、OSの安全バッファ、Bluetoothの無線伝送・コーデック遅延が加わります。OS報告値も音響ループバックによる実測値ではありません。BluetoothマイクはHFPを使用し、入力を選ぶと出力側の通信方式・音質も変化する場合があります。高品質Bluetooth録音オプションは、遅延増加を避けるため使用しません。

Bluetooth・USB機器のイヤホン/スピーカー種別を完全には判定できないため、接続ごとの確認が必要です。AirPlay、HDMI、CarPlay、受話口はモニター出力先として許可しません。Bluetoothの組み合わせによっては希望する入力・出力をOSが同時に選べない場合があり、その場合は別のマイクに勝手に変更せず停止します。

## ビルド

`MicRelay.xcodeproj` をXcodeで開き、署名チームと実機を選んで実行します。外部ライブラリは不要です。

```sh
# プロジェクトの再生成が必要な場合のみ（Homebrewのxcodegen）
xcodegen generate

xcodebuild -project MicRelay.xcodeproj -scheme MicRelay \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates build
```

`project.yml` がプロジェクト設定の元です。Bundle IDは所有ドメイン `ryuya-dev.net` の逆順による `net.ryuya-dev.MicRelay` です。アプリアイコンは `swift scripts/generate-icon.swift` で再生成できます。

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
