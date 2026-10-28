import AppKit

/// 検索バーの件数と移動を、エディタとプレビューのどちらに効かせるか。
enum SearchTarget {
    case editor
    case preview
}

/// エディタの本文の検索と置換。一致の判定はプレビューの検索（mdviewer.js の findMatches）と揃える。
@MainActor
final class EditorSearchController: ObservableObject {
    /// 件数と移動の対象のときだけ設定する。対象でないときは一致を強調するだけなので nil。
    @Published private(set) var status: RenderViewModel.SearchStatus?

    /// エディタの NSTextView。MarkdownEditorView が作ったときに設定する。
    weak var textView: NSTextView? {
        didSet {
            guard textView !== oldValue else { return }
            refresh()
        }
    }

    private var query = ""
    private var selects = false
    private(set) var matches: [NSRange] = []
    private var currentIndex = -1

    /// プレビューの強調と同じ色（mdviewer-base.css の mark.mdviewer-search-hit）
    private static let hitColor = NSColor(srgbRed: 1, green: 213 / 255, blue: 0, alpha: 0.45)
    private static let currentColor = NSColor(srgbRed: 1, green: 150 / 255, blue: 50 / 255, alpha: 1)

    var isTextViewFirstResponder: Bool {
        guard let textView, let window = textView.window else { return false }
        return window.firstResponder === textView
    }

    // MARK: 一致の判定

    /// 大文字と小文字を区別しない。検索語の空白は空白の並びに一致させるが、空行はまたがない
    /// （プレビューで段落をまたがないのと揃える）。
    nonisolated static func ranges(of query: String, in text: String) -> [NSRange] {
        let words = query.split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return [] }
        // 改行を1つだけ含む空白か、改行を含まない空白の並び
        let space = #"(?:[^\S\n]*\n[^\S\n]*|[^\S\n]+)"#
        let pattern = words.joined(separator: space)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).map(\.range).filter { $0.length > 0 }
    }

    /// location 以降で最初の一致。なければ先頭に戻る。
    nonisolated static func index(atOrAfter location: Int, in matches: [NSRange]) -> Int {
        matches.firstIndex { $0.location >= location } ?? 0
    }

    // MARK: 検索

    /// - Parameter selecting: 件数と移動の対象なら true。カーソル位置以降の一致を選んで見える位置まで送る。
    func search(_ query: String, selecting: Bool) {
        self.query = query
        selects = selecting
        let location = textView?.selectedRange().location ?? 0
        update(selectingFrom: selecting ? location : nil)
    }

    func findNext() {
        move(by: 1)
    }

    func findPrevious() {
        move(by: -1)
    }

    func clear() {
        query = ""
        selects = false
        matches = []
        currentIndex = -1
        status = nil
        removeHighlights()
    }

    /// エディタの本文が変わったときに数え直す。選んでいる一致の番号は保ち、スクロールはしない。
    func refresh() {
        guard !query.isEmpty else { return }
        let keep = currentIndex
        recount()
        if selects, !matches.isEmpty {
            currentIndex = min(max(keep, 0), matches.count - 1)
        } else {
            currentIndex = -1
        }
        applyHighlights()
        publishStatus()
    }

    // MARK: 置換

    /// 選んでいる一致を置き換えて、次の一致を選ぶ。
    func replaceCurrent(with replacement: String) {
        guard let textView, matches.indices.contains(currentIndex) else { return }
        let range = matches[currentIndex]
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        update(selectingFrom: range.location + (replacement as NSString).length)
    }

    /// すべての一致を置き換える。取り消すときは1回で元に戻る。
    /// - Returns: 置き換えた数
    @discardableResult
    func replaceAll(with replacement: String) -> Int {
        guard let textView, let storage = textView.textStorage, !matches.isEmpty else { return 0 }
        let ranges = matches
        let replacements = Array(repeating: replacement, count: ranges.count)
        guard textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: replacements)
        else { return 0 }
        storage.beginEditing()
        for range in ranges.reversed() {
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()
        textView.didChangeText()
        update(selectingFrom: nil)
        return ranges.count
    }

    // MARK: 内部

    private func move(by step: Int) {
        guard selects, !matches.isEmpty else { return }
        let count = matches.count
        currentIndex = currentIndex < 0 ? 0 : ((currentIndex + step) % count + count) % count
        applyHighlights()
        reveal()
        publishStatus()
    }

    private func update(selectingFrom location: Int?) {
        recount()
        if selects, let location, !matches.isEmpty {
            currentIndex = Self.index(atOrAfter: location, in: matches)
        } else {
            currentIndex = selects && !matches.isEmpty ? 0 : -1
        }
        applyHighlights()
        if location != nil { reveal() }
        publishStatus()
    }

    private func recount() {
        guard let textView, !query.isEmpty else {
            matches = []
            return
        }
        matches = Self.ranges(of: query, in: textView.string)
    }

    private func publishStatus() {
        let newStatus = selects && !query.isEmpty
            ? RenderViewModel.SearchStatus(current: currentIndex + 1, total: matches.count)
            : nil
        if status != newStatus { status = newStatus }
    }

    /// 選んでいる一致を選択して、見える位置まで送る。
    private func reveal() {
        guard let textView, matches.indices.contains(currentIndex) else { return }
        let range = matches[currentIndex]
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        if textView.window != nil {
            textView.showFindIndicator(for: range)
        }
    }

    private func applyHighlights() {
        removeHighlights()
        guard let layoutManager = textView?.layoutManager else { return }
        for (i, range) in matches.enumerated() {
            let color = i == currentIndex ? Self.currentColor : Self.hitColor
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
    }

    private func removeHighlights() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
    }
}
