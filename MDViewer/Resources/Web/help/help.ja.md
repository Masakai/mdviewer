# MDViewer ヘルプ

MarkdownとMermaid記法のリファレンスです。各記法をこの画面上で実際にレンダリングして示します。サイドバーから各セクションへ移動できます。

---

## 見出し

`#` から `######` まで6段階あります。

```
# 見出し1
## 見出し2
### 見出し3
#### 見出し4
##### 見出し5
###### 見出し6
```

# 見出し1
## 見出し2
### 見出し3
#### 見出し4
##### 見出し5
###### 見出し6

---

## 強調

```
*斜体* または _斜体_
**太字** または __太字__
***太字斜体***
~~取り消し線~~
```

*斜体* または _斜体_
**太字** または __太字__
***太字斜体***
~~取り消し線~~

---

## リスト

### 番号なしリスト

```
- 項目1
- 項目2
  - 入れ子の項目
- 項目3
```

- 項目1
- 項目2
  - 入れ子の項目
- 項目3

### 番号付きリスト

```
1. 手順1
2. 手順2
   1. 手順2の子項目
3. 手順3
```

1. 手順1
2. 手順2
   1. 手順2の子項目
3. 手順3

### タスクリスト

```
- [x] 完了した項目
- [ ] 未完了の項目
```

- [x] 完了した項目
- [ ] 未完了の項目

---

## リンクと画像

```
[MDViewer on GitHub](https://github.com)
![代替テキスト](image.png)
```

[MDViewer on GitHub](https://github.com)

---

## 引用

```
> 一行の引用。
>
> 複数行にまたがる
> 引用も書けます。
```

> 一行の引用。
>
> 複数行にまたがる
> 引用も書けます。

---

## コード

インラインコード: `` `let x = 1` `` は `let x = 1` のように表示されます。

言語タグ付きのコードブロックはシンタックスハイライトされます。

````
```swift
func greet(name: String) -> String {
    "Hello, \(name)!"
}
```
````

```swift
func greet(name: String) -> String {
    "Hello, \(name)!"
}
```

---

## テーブル

```
| 機能         | 対応 |
| ------------ | ---- |
| テーブル     | ○   |
| 脚注         | ○   |
| Mermaid      | ○   |
```

| 機能         | 対応 |
| ------------ | ---- |
| テーブル     | ○   |
| 脚注         | ○   |
| Mermaid      | ○   |

---

## 脚注

```
本文に脚注を付けられます。[^1]

[^1]: これが脚注の内容です。
```

本文に脚注を付けられます。[^1]

[^1]: これが脚注の内容です。

---

## 水平線

```
---
```

---

## 数式（KaTeX）

インライン数式: `$E = mc^2$` は $E = mc^2$ のように表示されます。

ブロック数式:

```
$$
\int_0^\infty e^{-x^2} \, dx = \frac{\sqrt{\pi}}{2}
$$
```

$$
\int_0^\infty e^{-x^2} \, dx = \frac{\sqrt{\pi}}{2}
$$

---

## Mermaid図

MDViewerは`mermaid`タグを付けたコードブロック内の[Mermaid](https://mermaid.js.org)記法を図として描画します。以下の例では、この記法自体を*説明する*ため外側のフェンスを4つのバッククォートにして内側の3バッククォートの例をそのまま表示していますが、実際のファイルでは通常の3バッククォートで`mermaid`ブロックを囲むだけで構いません。

### フローチャート

````
```mermaid
flowchart LR
    A[開始] --> B{判定}
    B -- はい --> C[処理を実行]
    B -- いいえ --> D[スキップ]
    C --> E[終了]
    D --> E
```
````

```mermaid
flowchart LR
    A[開始] --> B{判定}
    B -- はい --> C[処理を実行]
    B -- いいえ --> D[スキップ]
    C --> E[終了]
    D --> E
```

### シーケンス図

````
```mermaid
sequenceDiagram
    participant U as ユーザー
    participant A as アプリ
    participant S as サーバー
    U->>A: 「保存」をクリック
    A->>S: PUT /document
    S-->>A: 200 OK
    A-->>U: 保存済み表示
```
````

```mermaid
sequenceDiagram
    participant U as ユーザー
    participant A as アプリ
    participant S as サーバー
    U->>A: 「保存」をクリック
    A->>S: PUT /document
    S-->>A: 200 OK
    A-->>U: 保存済み表示
```

### クラス図

````
```mermaid
classDiagram
    class DocumentViewModel {
        +String text
        +URL? fileURL
        +Bool isDirty
        +save()
        +newDocument()
    }
    class FileWatcher {
        +start(url)
        +stop()
    }
    DocumentViewModel --> FileWatcher
```
````

```mermaid
classDiagram
    class DocumentViewModel {
        +String text
        +URL? fileURL
        +Bool isDirty
        +save()
        +newDocument()
    }
    class FileWatcher {
        +start(url)
        +stop()
    }
    DocumentViewModel --> FileWatcher
```

### 状態遷移図

````
```mermaid
stateDiagram-v2
    [*] --> Clean
    Clean --> Dirty: 編集
    Dirty --> Clean: 保存
    Dirty --> [*]: 破棄
    Clean --> [*]: 閉じる
```
````

```mermaid
stateDiagram-v2
    [*] --> Clean
    Clean --> Dirty: 編集
    Dirty --> Clean: 保存
    Dirty --> [*]: 破棄
    Clean --> [*]: 閉じる
```

### ER図

````
```mermaid
erDiagram
    DOCUMENT ||--o{ HEADING : contains
    DOCUMENT {
        string fileURL
        bool isDirty
    }
    HEADING {
        int level
        string title
        string anchor
    }
```
````

```mermaid
erDiagram
    DOCUMENT ||--o{ HEADING : contains
    DOCUMENT {
        string fileURL
        bool isDirty
    }
    HEADING {
        int level
        string title
        string anchor
    }
```

### ガントチャート

````
```mermaid
gantt
    title リリース計画
    dateFormat  YYYY-MM-DD
    section 設計
    仕様レビュー        :done,    des1, 2026-07-01, 3d
    section 実装
    実装作業            :active,  dev1, 2026-07-04, 5d
    コードレビュー      :         rev1, after dev1, 2d
    section リリース
    公証・リリース      :         rel1, after rev1, 1d
```
````

```mermaid
gantt
    title リリース計画
    dateFormat  YYYY-MM-DD
    section 設計
    仕様レビュー        :done,    des1, 2026-07-01, 3d
    section 実装
    実装作業            :active,  dev1, 2026-07-04, 5d
    コードレビュー      :         rev1, after dev1, 2d
    section リリース
    公証・リリース      :         rel1, after rev1, 1d
```

### 円グラフ

````
```mermaid
pie title エディタ利用状況
    "ビューアのみ" : 40
    "エディタモード" : 45
    "新規作成" : 15
```
````

```mermaid
pie title エディタ利用状況
    "ビューアのみ" : 40
    "エディタモード" : 45
    "新規作成" : 15
```

### ユーザージャーニー

````
```mermaid
journey
    title ファイルを開いて編集する
    section 開く
      MDViewerを起動: 5: ユーザー
      ファイルを開く: 4: ユーザー
    section 編集
      エディタモードに切替: 4: ユーザー
      内容を編集: 3: ユーザー
    section 保存
      Cmd+Sで保存: 5: ユーザー
```
````

```mermaid
journey
    title ファイルを開いて編集する
    section 開く
      MDViewerを起動: 5: ユーザー
      ファイルを開く: 4: ユーザー
    section 編集
      エディタモードに切替: 4: ユーザー
      内容を編集: 3: ユーザー
    section 保存
      Cmd+Sで保存: 5: ユーザー
```

### マインドマップ

````
```mermaid
mindmap
  root((MDViewer))
    ビューア
      シンタックスハイライト
      数式（KaTeX）
      Mermaid図
    エディタ
      分割ビュー
      新規作成
      保存 / 名前を付けて保存
    エクスポート
      PDF
      HTML
```
````

```mermaid
mindmap
  root((MDViewer))
    ビューア
      シンタックスハイライト
      数式（KaTeX）
      Mermaid図
    エディタ
      分割ビュー
      新規作成
      保存 / 名前を付けて保存
    エクスポート
      PDF
      HTML
```

### タイムライン

````
```mermaid
timeline
    title MDViewer バージョン履歴
    2026-05-05 : v1.0.3
    2026-05-22 : v1.1.0 : エディタモード追加
    2026-06-12 : v1.1.1 : ローカル画像修正
    2026-07-19 : v1.2.0 : 新規作成機能追加
```
````

```mermaid
timeline
    title MDViewer バージョン履歴
    2026-05-05 : v1.0.3
    2026-05-22 : v1.1.0 : エディタモード追加
    2026-06-12 : v1.1.1 : ローカル画像修正
    2026-07-19 : v1.2.0 : 新規作成機能追加
```

---

## このアプリでの使い方

- **ライブプレビュー**: エディタモード（⌘E）では、入力に合わせてプレビューが即座に更新されます。
- **目次**: サイドバー（⌘⇧S）に現在のドキュメントの見出し一覧が表示されます。このヘルプ自体も同じ仕組みです。
- **テーマ**: ツールバーのパレットアイコンからシンタックスハイライトのテーマ（ライト/ダーク）を選べます。
- **エクスポート**: 「書き出し」メニューからこの文書を含めPDFやHTMLに変換できます。
