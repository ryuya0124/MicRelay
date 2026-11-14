# 翻訳の追加と更新

日本語（`ja`）と英語（`en`）に対応。アプリはiOS / iPadOSの優先言語に従う。OSのアプリ別言語設定から切り替えられる。独自の言語設定は持たない。

## 管理するファイル

- `MicRelay/Resources/Localizable.xcstrings`：画面、接続状態、エラー、読み上げ、ロック画面のテキスト。
- `MicRelay/Resources/InfoPlist.xcstrings`：マイク権限の説明。
- `project.yml`：`developmentLanguage: ja` と `knownRegions`。XcodeGenの設定元。

Apple標準のString Catalogを使う。外部の翻訳サービス・実行時ライブラリは不要。音声コールバックで翻訳参照は行わない。機器名はOSから受け取った名前、ライセンス本文と著作権表記は配布元の原文を表示する。

## 言語を追加する

例として韓国語（`ko`）を追加する場合：

```sh
python3 scripts/localization.py export --language ko --output /tmp/MicRelay-ko.json
```

JSONの各項目の `translation` に訳文を入れる。`source` とキーは変更しない。`%lld`・`%llu`・`%d`・`%@`などの差し込み値は個数と型を維持する。語順を変える場合は `%1$lld`・`%2$@` のような位置指定を使える。

```sh
python3 scripts/localization.py import --language ko --input /tmp/MicRelay-ko.json
python3 scripts/localization.py check
xcodegen generate
```

取り込みは全項目を検証してから両方のカタログへ反映し、`knownRegions` も更新する。未翻訳、古い原文、未知のキー、差し込み値の不一致は取り込まない。アプリのSwiftコードは言語追加のために変更する必要がない。

Xcodeで直接カタログに言語を追加し、翻訳することもできる。その場合は `project.yml` の `knownRegions` にも言語コードを追加し、`xcodegen generate` を実行する。コード例は `en`・`ko`・`zh-Hans`・`zh-Hant`・`pt-BR` など。翻訳が収録されていない言語は、OSの言語選択と日本語の開発言語による標準フォールバックに従う。

## 新しい画面文言を追加する

モデル内の状態、エラー、動的なラベルも含め、固定キーと日本語の既定文を使う。

```swift
Text(String(localized: "monitor.action.start", defaultValue: "モニターを開始"))
String(localized: "eq.enable_band", defaultValue: "バンド \(number) を使う")
```

キーは表示文の変更で変えない。用途や意味が変わる場合は別のキーを作る。Xcodeでは `SWIFT_EMIT_LOC_STRINGS` を有効にしており、ビルド時に `.stringsdata` を生成する。カタログへ追加・同期し、日本語と全対応言語を更新する。Xcodeのカタログ画面に加え、必要なら次のCLIも使える。

```sh
xcrun xcstringstool sync MicRelay/Resources/Localizable.xcstrings \
  --stringsdata <ビルドで生成した各Swiftファイルの.stringsdata>
python3 scripts/localization.py check
```

差し込み値の型はSwiftコンパイラの抽出結果に合わせる。ブランド名、SI単位、数値だけのグラフ目盛りは `shouldTranslate: false` とする。通常のUIテキストを翻訳対象から除外しない。将来、件数によって語形が変わる文を追加するときはString Catalogの複数形バリエーションを使い、JSON交換ツールもその形式に拡張する。現在の文言は件数を括弧で示すため複数形分岐を必要としない。

## 確認

```sh
python3 scripts/localization.py check
python3 -m unittest discover -s scripts/tests -v
```

GitHub Actionsでも上記を実行する。日本語・英語の欠落、キーの登録漏れ、差し込み値の不一致、言語一覧との食い違いを検出する。Swiftのテストではコンパイル済みの両言語・マイク権限文・差し込み値・地域別のゲイン上限入力を確認する。

UIテストは `testJapaneseLocalizationAcrossScreens` と `testEnglishLocalizationAcrossScreens`。各言語でメイン、EQ、ゲイン入力エラー、ライセンス、バックアップ画面を開き、表示を確認・撮影する。新しい言語も小さい画面とiPadで、長い文・文字サイズ拡大・読み上げを確認する。

App Storeの説明やスクリーンショットはアプリのカタログとは別で、`store/metadata/` と `store/screenshots/` で管理する。アプリの対応言語を追加しただけではストア情報は自動翻訳しない。

参考：[Apple String Catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)。
