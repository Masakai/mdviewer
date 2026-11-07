import Foundation

/// キーウィンドウに表示している文書の状態。メニューバーの項目を前面の文書に合わせて無効にするために使う。
/// メニューはどのウィンドウにも属さないので、各ウィンドウの ContentView が、キーになった・外れた・
/// 状態が変わった・閉じたときにここへ知らせる。
@MainActor
final class KeyDocumentState: ObservableObject {
    static let shared = KeyDocumentState()

    /// キーウィンドウの文書が読み取り専用か。キーウィンドウが文書でない（ヘルプ・設定）ときは false。
    @Published private(set) var isReadOnly = false

    /// 今の値を知らせてきたウィンドウの文書。ウィンドウごとに1つある DocumentViewModel を識別に使う。
    private weak var owner: AnyObject?

    /// `owner` の文書を表示しているウィンドウの状態を知らせる。キーでなくなったウィンドウの知らせは、
    /// そのウィンドウが今の値の持ち主のときだけ値を戻す（別のウィンドウが先にキーになっていれば無視する）。
    func update(owner: AnyObject, isKey: Bool, isReadOnly: Bool) {
        if isKey {
            self.owner = owner
            setReadOnly(isReadOnly)
        } else if self.owner === owner {
            self.owner = nil
            setReadOnly(false)
        }
    }

    func windowClosed(owner: AnyObject) {
        update(owner: owner, isKey: false, isReadOnly: false)
    }

    /// ウィンドウの更新のたびに呼ばれるので、値が変わったときだけ代入してメニューを作り直させない
    private func setReadOnly(_ value: Bool) {
        if isReadOnly != value {
            isReadOnly = value
        }
    }
}
