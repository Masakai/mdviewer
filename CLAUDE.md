# MDViewer Project Instructions

## Release Process

**必須**: リリース前に必ず公証付きビルドを実行すること。

```bash
./build-notarize.sh
```

このスクリプトがビルド・署名・公証・staple・zip作成をすべて行う。
生成された `build/MDViewer.zip`（staple済み）をGitHub Releaseにアップロードしてからリリースすること。

### 手順

1. `./build-notarize.sh` を実行
2. 成功したら `build/MDViewer.zip` が生成される
3. `gh release create vX.X.X build/MDViewer.zip ...` でリリース作成
4. zipなしのリリースは不可

### アプリパスワード・公証の設定

- Keychainプロファイル名: `notarytool-password`
- Apple ID: masakai@ny.thn.ne.jp
- Team ID: CHKD9M5BF5
- パスワードを再生成した場合は `xcrun notarytool store-credentials "notarytool-password"` で再登録
