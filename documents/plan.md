# MDViewer macOS App — 設計計画書

**作成日**: 2026-05-04
**対象プラットフォーム**: macOS 13.0 (Ventura) 以降
**言語**: Swift 5.9 / SwiftUI
**アーキテクチャパターン**: MVVM

---

## 1. 設計概要

macOS ネイティブの Markdown ビューアアプリ。左パネルで目次（TOC）またはページサムネイルを切り替え表示し、右メインエリアで Markdown をレンダリングする。GFM 準拠のレンダリングに加え、シンタックスハイライト・数式（KaTeX）・Mermaid 図・テーブルをサポートする。

### 設計上の核心的な判断

| 課題 | 決定事項 | 理由 |
|------|----------|------|
| Markdown レンダリングエンジン | WKWebView + marked.js + highlight.js + KaTeX + Mermaid.js | 数式・Mermaid・シンタックスハイライトはすべて JavaScript を必要とするため、ネイティブ AttributedString では実現不可能 |
| ページサムネイル生成 | PDFKit `PDFPage.thumbnail(of:for:)` | WKWebView コンテンツを PDF 化 → 各ページを NSImage にラスタライズする方式 |
| 左パネルの目次 | swift-markdown (swiftlang) でヘッダ抽出 | HTML パース不要でヘッダ階層を構造的に取得できる |
| コード署名 | 開発中: ad-hoc / 配布: Developer ID | ad-hoc はローカルマシン限定。他者配布時は Developer ID + Notarization が必須 |

---

## 2. 技術スタック

### 2.1 Swift パッケージ依存関係

| パッケージ | 用途 | URL |
|-----------|------|-----|
| `swift-markdown` (swiftlang) | TOC 抽出用 AST パーサ | https://github.com/swiftlang/swift-markdown |

上記1件のみ SPM で管理。それ以外の JS ライブラリはバンドルリソースとして同梱する。

### 2.2 バンドル同梱リソース（JS/CSS）

| ライブラリ | バージョン目安 | 用途 |
|-----------|-------------|------|
| marked.js | v12 以降 | GFM Markdown → HTML 変換 |
| highlight.js | v11 以降 | コードブロックシンタックスハイライト |
| KaTeX | v0.16 以降 | LaTeX 数式レンダリング |
| Mermaid.js | v10 以降 | フローチャート・シーケンス図 |
| GitHub Markdown CSS | 最新版 | ライト/ダークテーマ CSS ベース |

これらは `Resources/Web/` ディレクトリに配置し、WKWebView はバンドル内ローカルファイルを読み込む。ネットワーク不要でオフライン動作する。

### 2.3 フレームワーク（macOS 標準）

- **SwiftUI** — メイン UI
- **WebKit (WKWebView)** — Markdown レンダリングエリア
- **PDFKit** — サムネイル生成
- **AppKit** — NSPasteboard、NSSavePanel、ファイル監視
- **UniformTypeIdentifiers** — ドラッグ&ドロップ MIME 判定

---

## 3. 機能仕様（フルスペック）

### 3.1 ファイル操作

| 機能 | 詳細 |
|------|------|
| ファイルを開く | NSOpenPanel で `.md`, `.markdown`, `.txt` を選択。`FileDocument` プロトコル実装 |
| ドラッグ&ドロップ | ウィンドウへの `.md`/`.markdown` ファイルドロップを受付。`dropDestination` モディファイア使用 |
| 最近使ったファイル | `NSDocumentController.shared.recentDocumentURLs` を利用（最大 10 件）。メニューバー「ファイル > 最近開いたファイル」 |
| ファイル監視 | `DispatchSourceFileSystemObject` で変更を監視し、自動リロード（遅延 0.5 秒デバウンス） |
| 複数タブ | SwiftUI `TabView` ではなく macOS ネイティブウィンドウタブ（`NSWindowTabbingMode`）を活用 |

### 3.2 レンダリング機能

| 機能 | 実装方式 |
|------|---------|
| GFM 準拠 | marked.js の `gfm: true` オプション |
| シンタックスハイライト | highlight.js auto-detect、言語バッジ付きコードブロック |
| LaTeX 数式 | KaTeX。インライン: `$...$`、ブロック: `$$...$$` |
| Mermaid 図 | Mermaid.js をバンドル内から読み込み、SVG レンダリング |
| テーブル | GFM テーブル（marked.js 標準対応） |
| タスクリスト | `- [x]` / `- [ ]` チェックボックス（読み取り専用） |
| 画像 | ローカル画像: Security-Scoped Bookmark + `WKURLSchemeHandler` でサンドボックス外アクセス対応 |
| 脚注 | marked.js `footnotes` 拡張 |
| 絵文字 | `:emoji:` 記法 → Unicode 変換（marked.js プラグイン） |

### 3.3 左パネル（サイドバー）

| モード | 実装 |
|-------|------|
| 目次（TOC）モード | swift-markdown でヘッダノードを抽出し、`OutlineView`（`List` の再帰）で H1〜H4 を階層表示。クリックで WKWebView のアンカーへスクロール（`WKWebView.evaluateJavaScript` で `scrollIntoView` 実行） |
| サムネイルモード | WKWebView でレンダリングした内容を `WKWebView.takeSnapshot` で NSImage 化 → 仮想ページ分割（長文は A4 縦比率で分割）してサムネイルグリッド表示 |
| 切り替え | サイドバー上部のセグメントコントロール（TOC / Thumbnails） |
| サイドバー幅 | ユーザーがリサイズ可能。`AppStorage` で最終幅を保存 |

> **サムネイル方式の詳細**: `WKWebView.takeSnapshot(with:completionHandler:)` を使い、ビューポート幅 800pt・仮想ページ高さ 1100pt（A4相当）ごとにオフスクリーンレンダリングしてサムネイルを生成する。PDF 出力時の副産物として `PDFPage.thumbnail(of:for:)` を再利用する方式も検討するが、初期実装は snapshot 方式とする。

### 3.4 検索機能

| 機能 | 実装 |
|------|------|
| ページ内検索 | `WKWebView` の `WKFindInteraction`（macOS 13+）を使用。Cmd+F で検索バー表示 |
| ハイライト | ブラウザネイティブの Find API がヒット箇所をハイライト |
| 件数表示 | `WKFindResult` から件数を取得し、ステータスバーに「3/12 件」表示 |

### 3.5 テーマ・外観

| 機能 | 実装 |
|------|------|
| ライト/ダーク自動追従 | `@Environment(\.colorScheme)` → WKWebView に `postMessage` でテーマ変更 |
| テーマ選択 | GitHub Light / GitHub Dark / Solarized Light / Solarized Dark / Dracula / Nord（計6テーマ）。各テーマは CSS ファイルとして `Resources/Themes/` に配置 |
| フォントサイズ調整 | スライダー or Cmd+/Cmd- で `font-size` を CSS 変数で変更（10pt〜24pt）。`AppStorage` で保存 |
| コードフォント | Menlo / SF Mono / JetBrains Mono を選択可能 |

### 3.6 エクスポート

| 形式 | 実装 |
|-----|------|
| PDF エクスポート | `WKWebView` の `createPDF(configuration:)` を使用（macOS 13+）。`NSSavePanel` でパス選択 |
| HTML エクスポート | レンダリング済み HTML（インライン CSS 付き）を文字列として取り出し保存 |
| 印刷 | `NSPrintOperation` を WKWebView に対して実行 |

### 3.7 ウィンドウ状態の保存・復元

- ウィンドウサイズ・位置: `@SceneStorage` または `AppStorage` で保存
- 最後に開いていたファイル: `AppStorage` に URL を Bookmark Data として保存（Security-Scoped Bookmark）
- サイドバーのモード（TOC/サムネイル）: `AppStorage` で保存
- アプリ再起動時に前回のファイルを自動復元（Sandbox 非使用時は URL のみで十分）

### 3.8 ショートカットキー

| ショートカット | 機能 |
|-------------|------|
| Cmd+O | ファイルを開く |
| Cmd+W | ウィンドウを閉じる |
| Cmd+F | ページ内検索 |
| Cmd+P | 印刷 |
| Cmd+Shift+E | HTML エクスポート |
| Cmd+Shift+P | PDF エクスポート |
| Cmd+R | ファイルをリロード |
| Cmd++ / Cmd+- | フォントサイズ拡大/縮小 |
| Cmd+0 | フォントサイズをリセット |
| Cmd+1 | サイドバー: TOC モード |
| Cmd+2 | サイドバー: サムネイルモード |
| Cmd+Shift+S | サイドバー表示/非表示トグル |

---

## 4. アーキテクチャ設計

### 4.1 MVVM コンポーネント構成

```
MDViewerApp (App)
├── AppDelegate (NSApplicationDelegate)
│   └── メニューバー設定、ファイル関連イベント処理
└── DocumentWindow (Scene)
    └── ContentView (View)
        ├── SidebarView (View)
        │   ├── SidebarToggleSegment (View)
        │   ├── TableOfContentsView (View)
        │   └── ThumbnailGridView (View)
        └── MarkdownRenderView (View)
            ├── WebRendererView (NSViewRepresentable → WKWebView)
            └── SearchBarView (View)

ViewModels:
├── DocumentViewModel (ObservableObject)
│   ├── 現在のファイルURL・テキスト管理
│   ├── ファイル監視 (DispatchSourceFileSystemObject)
│   └── recentFiles: [URL]
├── SidebarViewModel (ObservableObject)
│   ├── mode: SidebarMode (toc | thumbnails)
│   ├── tocItems: [TOCItem]
│   └── thumbnails: [NSImage]
├── RenderViewModel (ObservableObject)
│   ├── htmlContent: String（レンダリング用 HTML）
│   ├── theme: MarkdownTheme
│   └── fontSize: Double
└── ExportViewModel (ObservableObject)
    └── exportToPDF / exportToHTML メソッド

Models:
├── MarkdownDocument (FileDocument)
├── TOCItem (id, level, title, anchor)
├── ThumbnailItem (id, pageNumber, image: NSImage)
└── MarkdownTheme (name, cssFileName)
```

### 4.2 WKWebView ブリッジ設計

WKWebView とのやり取りは以下の2方向で行う。

**Swift → JS (evaluateJavaScript)**:
- `MDViewer.setContent(markdown: String)` — Markdown テキストの更新
- `MDViewer.setTheme(name: String)` — テーマ変更
- `MDViewer.setFontSize(size: Int)` — フォントサイズ変更
- `MDViewer.scrollToAnchor(id: String)` — TOC クリック時のスクロール

**JS → Swift (WKScriptMessageHandler)**:
- `headingsExtracted` — ページロード後にヘッダ一覧を送信
- `scrollPositionChanged` — スクロール位置変化（TOC のアクティブ項目同期用）
- `renderComplete` — レンダリング完了通知（サムネイル生成トリガー）

### 4.3 HTML テンプレート構造

`Resources/Web/renderer.html` を基点とする。

```
Resources/
├── Web/
│   ├── renderer.html          ← テンプレート（マスター HTML）
│   ├── mdviewer.js            ← Swift ブリッジ + marked.js 呼び出し
│   ├── mdviewer-base.css      ← レイアウト・共通スタイル
│   ├── vendor/
│   │   ├── marked.min.js
│   │   ├── highlight.min.js
│   │   ├── katex.min.js
│   │   ├── katex.min.css
│   │   ├── mermaid.min.js
│   │   └── highlight-default.min.css
│   └── themes/
│       ├── github-light.css
│       ├── github-dark.css
│       ├── solarized-light.css
│       ├── solarized-dark.css
│       ├── dracula.css
│       └── nord.css
```

### 4.4 ローカル画像アクセス（サンドボックス対応）

ファイルを開く際に Security-Scoped Bookmark を取得・保存する。WKWebView でローカル画像を表示するため、カスタム URL スキーム `mdviewer-local://` を実装し、`WKURLSchemeHandler` でファイルシステムへのアクセスを仲介する。

---

## 5. ファイル構成

```
MDViewer/
├── MDViewer.xcodeproj
│   └── project.pbxproj
├── MDViewer/
│   ├── App/
│   │   ├── MDViewerApp.swift           ← @main, Scene 定義
│   │   └── AppDelegate.swift           ← NSApplicationDelegate
│   ├── Models/
│   │   ├── MarkdownDocument.swift      ← FileDocument プロトコル実装
│   │   ├── TOCItem.swift
│   │   ├── ThumbnailItem.swift
│   │   └── MarkdownTheme.swift
│   ├── ViewModels/
│   │   ├── DocumentViewModel.swift
│   │   ├── SidebarViewModel.swift
│   │   ├── RenderViewModel.swift
│   │   └── ExportViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift           ← NavigationSplitView ルート
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift
│   │   │   ├── TableOfContentsView.swift
│   │   │   └── ThumbnailGridView.swift
│   │   ├── Renderer/
│   │   │   ├── MarkdownRenderView.swift
│   │   │   ├── WebRendererView.swift   ← NSViewRepresentable
│   │   │   └── LocalSchemeHandler.swift ← WKURLSchemeHandler
│   │   ├── Toolbar/
│   │   │   ├── MainToolbar.swift
│   │   │   └── SearchBarView.swift
│   │   └── Preferences/
│   │       ├── PreferencesView.swift
│   │       ├── AppearancePrefsView.swift
│   │       └── GeneralPrefsView.swift
│   ├── Utilities/
│   │   ├── FileWatcher.swift           ← DispatchSourceFileSystemObject
│   │   ├── BookmarkManager.swift       ← Security-Scoped Bookmark 管理
│   │   └── HTMLBuilder.swift          ← renderer.html + CSS 組み立て
│   ├── Resources/
│   │   └── Web/                       ← (§4.3 参照)
│   ├── Assets.xcassets
│   ├── MDViewer.entitlements
│   └── Info.plist
└── documents/
    └── plan.md                        ← 本ファイル
```

---

## 6. コード署名・配布

### 6.1 署名方式の比較

| 方式 | 要件 | 動作範囲 | 推奨用途 |
|-----|------|---------|---------|
| **ad-hoc 署名** | Apple Developer Program 不要 | 署名したマシンのみ | 開発中・個人ローカル利用 |
| **Developer ID** | Apple Developer Program ($99/年) | 全 Mac（Notarization 後） | 他者への配布・ウェブ配布 |
| **App Store** | Apple Developer Program | Mac App Store | 商用配布 |

### 6.2 ad-hoc 署名の設定手順（Apple Developer Program 不要）

Xcode の Signing & Capabilities タブで以下を設定する:

1. **Team**: なし（Automatically manage signing をオフ）
2. **Signing Certificate**: Sign to Run Locally（または `-` を指定）
3. **Entitlements ファイル** (`MDViewer.entitlements`) に必要な権限のみ記述

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Sandboxを無効にすればファイル制限なし（ad-hoc では推奨） -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <!-- ファイルシステム読み取り（サンドボックス有効時のみ必要） -->
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <!-- WKWebView 使用に必要 -->
    <key>com.apple.security.network.client</key>
    <false/>
</dict>
</plist>
```

コマンドラインで ad-hoc 署名する場合:
```bash
codesign --force --deep --sign - MDViewer.app
```

Gatekeeper の確認をスキップして起動する場合（初回のみ）:
```bash
xattr -dr com.apple.quarantine MDViewer.app
```

### 6.3 Developer ID 署名・Notarization 手順（配布用）

1. Apple Developer Program に加入し、Developer ID Application 証明書を発行
2. Xcode で Hardened Runtime を有効化 (`--options runtime`)
3. Entitlements に `com.apple.security.app-sandbox: true` を設定
4. `codesign --force --deep --options runtime --entitlements MDViewer.entitlements --sign "Developer ID Application: ..." MDViewer.app`
5. `xcrun notarytool submit MDViewer.zip --apple-id ... --password ... --team-id ...`
6. `xcrun stapler staple MDViewer.app`

### 6.4 App Store 向け Sandbox Entitlements（参考）

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

---

## 7. 実装計画（フェーズ別）

### Phase 1: コア基盤（MVP） — 目安: 2〜3日

**目標**: ファイルを開いて Markdown をレンダリングできる最小実装。

#### タスク一覧

| # | タスク | 変更対象ファイル | 詳細 |
|---|------|--------------|------|
| 1.1 | Xcode プロジェクト作成 | `MDViewer.xcodeproj` | macOS App テンプレート。Bundle ID: `com.mdviewer.app`。Deployment Target: macOS 13.0。`swift-markdown` を SPM で追加 |
| 1.2 | `MarkdownDocument` 実装 | `Models/MarkdownDocument.swift` | `FileDocument` プロトコル実装。`readableContentTypes: [.markdown, .plainText]` |
| 1.3 | `DocumentViewModel` 実装 | `ViewModels/DocumentViewModel.swift` | `@Published var text: String`、`@Published var fileURL: URL?`、NSOpenPanel ラッパーメソッド |
| 1.4 | HTML レンダラーリソース配置 | `Resources/Web/` | `renderer.html`, `mdviewer.js`, `mdviewer-base.css`, `marked.min.js`, `highlight.min.js`, `highlight-default.min.css` を配置 |
| 1.5 | `WebRendererView` 実装 | `Views/Renderer/WebRendererView.swift` | `NSViewRepresentable` で `WKWebView` をラップ。`WKWebViewConfiguration` でバンドルリソースを `loadFileURL` でロード |
| 1.6 | `HTMLBuilder` 実装 | `Utilities/HTMLBuilder.swift` | `renderer.html` を読み込み、テーマ CSS へのリンクを動的に挿入して返すユーティリティ |
| 1.7 | `ContentView` 基本実装 | `Views/ContentView.swift` | `NavigationSplitView` の骨格。sidebar は空、detail は `MarkdownRenderView` |
| 1.8 | `MDViewerApp` & `AppDelegate` | `App/MDViewerApp.swift`, `App/AppDelegate.swift` | `DocumentGroup` シーン設定、メニューバー「ファイル > 開く」接続 |
| 1.9 | ad-hoc 署名設定 | `MDViewer.entitlements`, Xcode Signing | サンドボックス無効の ad-hoc 署名。ローカル実行確認 |

**Phase 1 完了基準**: `.md` ファイルを開くと GFM レンダリング結果が WKWebView に表示される。

---

### Phase 2: 左パネル・テーマ・検索 — 目安: 3〜4日

**目標**: 目次・サムネイルサイドバー、テーマ切り替え、ページ内検索を実装する。

#### タスク一覧

| # | タスク | 変更対象ファイル | 詳細 |
|---|------|--------------|------|
| 2.1 | `TOCItem` モデル + TOC 抽出 | `Models/TOCItem.swift`, `ViewModels/SidebarViewModel.swift` | `swift-markdown` でドキュメントを解析し、`Heading` ノードを走査して `TOCItem` 配列を生成。level(1〜4), title, anchor(slugified id) |
| 2.2 | `TableOfContentsView` 実装 | `Views/Sidebar/TableOfContentsView.swift` | `List` + `DisclosureGroup` で H1-H4 階層表示。選択時に `RenderViewModel.scrollToAnchor(id:)` を呼び出す |
| 2.3 | JS ブリッジ: アンカースクロール | `Views/Renderer/WebRendererView.swift`, `Resources/Web/mdviewer.js` | `WKScriptMessageHandler` で `headingsExtracted` メッセージ受信。`evaluateJavaScript` で `document.getElementById(id).scrollIntoView()` 実行 |
| 2.4 | `ThumbnailItem` モデル + 生成 | `Models/ThumbnailItem.swift`, `ViewModels/SidebarViewModel.swift` | `renderComplete` メッセージ受信後、`WKWebView.takeSnapshot(with:)` を仮想ページ高さごとに繰り返してサムネイル配列を生成 |
| 2.5 | `ThumbnailGridView` 実装 | `Views/Sidebar/ThumbnailGridView.swift` | `LazyVGrid` で `NSImage` を表示。クリックでそのページ位置へスクロール（JS で `window.scrollTo` 呼び出し） |
| 2.6 | `SidebarView` + トグル実装 | `Views/Sidebar/SidebarView.swift` | セグメントコントロールで TOC / Thumbnails を切り替え。`SidebarViewModel.mode` を更新 |
| 2.7 | テーマ CSS 作成 | `Resources/Web/themes/*.css` | github-light / github-dark / solarized-light / solarized-dark / dracula / nord の6ファイルを作成 |
| 2.8 | `RenderViewModel` テーマ対応 | `ViewModels/RenderViewModel.swift` | `@Published var theme: MarkdownTheme`。変更時に `MDViewer.setTheme(name:)` を JS に送信 |
| 2.9 | `SearchBarView` 実装 | `Views/Toolbar/SearchBarView.swift` | Cmd+F でフォーカス。`WKFindInteraction` を `WebRendererView` に紐付け。件数をステータスバーに表示 |
| 2.10 | `AppStorage` 永続化 | `ViewModels/` 各ファイル | theme, fontSize, sidebarMode, sidebarWidth, lastOpenedURL を AppStorage に保存 |
| 2.11 | `FileWatcher` 実装 | `Utilities/FileWatcher.swift` | `DispatchSourceFileSystemObject` で監視。変更検出後 0.5s デバウンスで `DocumentViewModel.reload()` を呼び出す |

**Phase 2 完了基準**: TOC クリックでスクロール、サムネイルグリッド表示、テーマ切り替え、Cmd+F 検索が動作する。

---

### Phase 3: エクスポート・高度機能・仕上げ — 目安: 2〜3日

**目標**: PDF/HTML エクスポート、数式・Mermaid、ローカル画像対応、最終品質仕上げ。

#### タスク一覧

| # | タスク | 変更対象ファイル | 詳細 |
|---|------|--------------|------|
| 3.1 | KaTeX・Mermaid.js バンドル | `Resources/Web/vendor/` | katex.min.js, katex.min.css, mermaid.min.js を追加。`renderer.html` と `mdviewer.js` を更新して初期化処理を追加 |
| 3.2 | 絵文字プラグイン | `Resources/Web/mdviewer.js` | marked.js カスタム拡張で `:smile:` → emoji 変換テーブルを実装 |
| 3.3 | `LocalSchemeHandler` 実装 | `Views/Renderer/LocalSchemeHandler.swift` | `WKURLSchemeHandler` で `mdviewer-local://` スキームを処理。`BookmarkManager` 経由でファイルを読み込み `Data` として返す |
| 3.4 | `BookmarkManager` 実装 | `Utilities/BookmarkManager.swift` | Security-Scoped Bookmark の保存・復元・startAccessingSecurityScopedResource 管理 |
| 3.5 | `ExportViewModel` 実装 | `ViewModels/ExportViewModel.swift` | `WKWebView.createPDF(configuration:)` で PDF 生成。`NSSavePanel` でパス選択後に保存 |
| 3.6 | HTML エクスポート | `ViewModels/ExportViewModel.swift` | JS 側で `document.documentElement.outerHTML` を取得し、インライン CSS を埋め込んで保存 |
| 3.7 | `PreferencesView` 実装 | `Views/Preferences/` 各ファイル | 一般（フォント・サイズ）・外観（テーマ・コードフォント）の設定画面。`Settings {}` シーンを使用 |
| 3.8 | 最近使ったファイルメニュー | `App/AppDelegate.swift` | `NSDocumentController.shared.recentDocumentURLs` を「ファイル > 最近開いたファイル」サブメニューに反映 |
| 3.9 | ショートカットキー登録 | `Views/ContentView.swift`, メニューコマンド | `.keyboardShortcut` モディファイアで §3.8 の全ショートカットを登録 |
| 3.10 | アプリアイコン作成 | `Assets.xcassets/AppIcon.appiconset` | 16x16〜1024x1024 の全サイズを PNG で用意 |
| 3.11 | Developer ID 署名設定 (省略可) | `MDViewer.entitlements`, Xcode | Hardened Runtime + Sandbox 有効化。Notarization ワークフロー確認 |
| 3.12 | README・使用方法ドキュメント | `documents/README.md` | インストール手順・ad-hoc 署名の説明・機能一覧 |

**Phase 3 完了基準**: 全機能が動作し、ad-hoc 署名済みの `.app` バンドルがローカルで実行可能な状態。

---

## 8. 注意事項・制約

### セキュリティ

- WKWebView に読み込むコンテンツはバンドル内ローカルファイルのみ。外部 URL への `loadHTMLString` は使用しない
- `LocalSchemeHandler` でファイルパスを返す際、ディレクトリトラバーサル（`../` 等）を `URL.standardized.path` で正規化してから許可されたディレクトリ内か検証する
- ユーザー選択ファイル外のパスへのアクセスを `BookmarkManager` のスコープ内に限定する

### 後方互換性

- Deployment Target は macOS 13.0 (Ventura) とする
- `WKFindInteraction` は macOS 13.0 以降で利用可能（`@available(macOS 13.0, *)`）
- `WKWebView.createPDF` は macOS 11.0 以降で利用可能

### パフォーマンス

- サムネイル生成は `Task { await MainActor.run { ... } }` を使い、メインスレッドをブロックしない
- `takeSnapshot` は非同期 API を使用する
- ファイル監視のデバウンス（0.5 秒）でリロード頻度を抑制する

### 既知の制約

- ad-hoc 署名のアプリは**署名したマシン以外では動作しない**
- App Sandbox を有効にする場合、`LocalSchemeHandler` と `BookmarkManager` の実装がより複雑になる（Phase 3.4 参照）
- サムネイル生成は長大な Markdown ファイルで時間がかかる可能性がある（非同期処理で対応）

---

## 9. ドキュメント更新計画

本ファイルが初版のため、追加で更新が必要なドキュメントは以下の通り:

| ファイル | 内容 |
|---------|------|
| `documents/README.md` | Phase 3.12 で作成。インストール・起動手順、機能一覧、ショートカット一覧 |
| `documents/architecture.md` | 必要に応じてコンポーネント図・シーケンス図を追加（Phase 2 完了後） |

---

*本ドキュメントはアーキテクトエージェントが策定した設計計画書です。実装はdeveloperエージェントが担当します。*
