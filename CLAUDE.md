# MDViewer Project Instructions

## Release Process

**機能実装の完了報告には、公証付きリリースへの導線を明示する**: リリース対象になりうる機能実装・修正が完了したら、完了報告の最後に「次は `/release-md` で公証付きリリースです」等、次のアクションとして release-md スキルを一言添える。公証を後から聞かれて初めて言及する、という抜けを防ぐため。

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
- Apple ID・Team IDは `CLAUDE.local.md`（gitignore対象）を参照
- パスワードを再生成した場合は `xcrun notarytool store-credentials "notarytool-password"` で再登録

### 公証の落とし穴：get-task-allow の自動注入

Releaseビルドでも `com.apple.security.get-task-allow` エンタイトルメントが自動注入される場合がある。これが含まれると公証が `Invalid` になる。

`xcodebuild` コマンドには必ず `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` を付けること。

```bash
# 確認方法
codesign --display --entitlements - build/MDViewer.app
```
