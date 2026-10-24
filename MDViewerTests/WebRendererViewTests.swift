import WebKit
import XCTest
@testable import MDViewer

final class WebRendererViewTests: XCTestCase {
    // MARK: - isSupersededNavigation

    /// WebKit reports a navigation replaced by a newer one as an NSError in
    /// NSURLErrorDomain, not as a Swift URLError. It must still be recognised.
    func test_isSupersededNavigation_cancelledNSError_returnsTrue() {
        // Arrange
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        // Act
        let result = WebRendererView.Coordinator.isSupersededNavigation(error)

        // Assert
        XCTAssertTrue(result)
    }

    /// A renderer page that genuinely fails to load has to be recovered.
    func test_isSupersededNavigation_fileDoesNotExist_returnsFalse() {
        // Arrange
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)

        // Act
        let result = WebRendererView.Coordinator.isSupersededNavigation(error)

        // Assert
        XCTAssertFalse(result)
    }

    func test_isSupersededNavigation_webKitError_returnsFalse() {
        // Arrange
        let error = NSError(
            domain: WKError.errorDomain,
            code: WKError.Code.webContentProcessTerminated.rawValue
        )

        // Act
        let result = WebRendererView.Coordinator.isSupersededNavigation(error)

        // Assert
        XCTAssertFalse(result)
    }

    // MARK: - resolveLinkURL

    private let docsDir = URL(fileURLWithPath: "/Users/me/docs/", isDirectory: true)

    private func resolve(_ href: String, _ dir: URL? = nil) -> URL? {
        WebRendererView.Coordinator.resolveLinkURL(href, relativeTo: dir ?? docsDir)
    }

    /// Relative links point at the open file's directory, not the app bundle (#22).
    func test_resolveLinkURL_subdirectory_resolvesAgainstDocumentDirectory() {
        XCTAssertEqual(resolve("dir_name/file_name.md")?.path, "/Users/me/docs/dir_name/file_name.md")
    }

    func test_resolveLinkURL_dotSlash_resolvesToSameDirectory() {
        XCTAssertEqual(resolve("./same.md")?.path, "/Users/me/docs/same.md")
    }

    func test_resolveLinkURL_parentDirectory_collapsesDotDot() {
        let url = resolve("../dir_name/file_name.md")

        XCTAssertEqual(url?.absoluteString, "file:///Users/me/dir_name/file_name.md")
    }

    func test_resolveLinkURL_absolutePath_staysAbsolute() {
        XCTAssertEqual(resolve("/path/to/file.md")?.absoluteString, "file:///path/to/file.md")
    }

    /// A base without a trailing slash would otherwise drop its last component.
    func test_resolveLinkURL_baseWithoutTrailingSlash_keepsLastComponent() throws {
        let dir = try XCTUnwrap(URL(string: "file:///Users/me/docs"))

        XCTAssertEqual(resolve("file.md", dir)?.path, "/Users/me/docs/file.md")
    }

    func test_resolveLinkURL_percentEncodedName_decodesToPath() {
        XCTAssertEqual(resolve("my%20notes/%E8%B3%87%E6%96%99.md")?.path, "/Users/me/docs/my notes/資料.md")
    }

    func test_resolveLinkURL_unencodedName_resolves() {
        XCTAssertEqual(resolve("my notes/資料.md")?.path, "/Users/me/docs/my notes/資料.md")
    }

    func test_resolveLinkURL_fragment_keepsMarkdownExtension() {
        let url = resolve("other.md#section")

        XCTAssertEqual(url?.path, "/Users/me/docs/other.md")
        XCTAssertEqual(url?.pathExtension, "md")
    }

    func test_resolveLinkURL_https_unchanged() {
        XCTAssertEqual(resolve("https://example.com/a?b=1")?.absoluteString, "https://example.com/a?b=1")
    }

    func test_resolveLinkURL_mailto_unchanged() {
        XCTAssertEqual(resolve("mailto:someone@example.com")?.absoluteString, "mailto:someone@example.com")
    }

    func test_resolveLinkURL_relativeWithoutOpenFile_returnsNil() {
        XCTAssertNil(WebRendererView.Coordinator.resolveLinkURL("file.md", relativeTo: nil))
    }

    func test_resolveLinkURL_absoluteURLWithoutOpenFile_resolves() {
        let url = WebRendererView.Coordinator.resolveLinkURL("https://example.com", relativeTo: nil)

        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    // MARK: - RendererWebView

    /// HSplitView sends a zero-height frame on every live-resize step; applying
    /// it would make the page lay out in an empty viewport (white flash).
    func test_setFrameSize_zeroHeight_keepsPreviousSize() {
        // Arrange
        let webView = RendererWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        // Act
        webView.setFrameSize(NSSize(width: 780, height: 0))

        // Assert
        XCTAssertEqual(webView.frame.size, NSSize(width: 300, height: 200))
    }

    func test_setFrameSize_zeroWidth_keepsPreviousSize() {
        // Arrange
        let webView = RendererWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        // Act
        webView.setFrameSize(NSSize(width: 0, height: 700))

        // Assert
        XCTAssertEqual(webView.frame.size, NSSize(width: 300, height: 200))
    }

    func test_setFrameSize_realSize_isApplied() {
        // Arrange
        let webView = RendererWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        // Act
        webView.setFrameSize(NSSize(width: 400, height: 300))

        // Assert
        XCTAssertEqual(webView.frame.size, NSSize(width: 400, height: 300))
    }
}

// MARK: - mdviewer.js（renderer.html を WKWebView に読み込んで描画結果を確かめる）

@MainActor
final class RendererScriptTests: XCTestCase {
    private var webView: WKWebView!

    override func setUp() async throws {
        let rendererURL = try XCTUnwrap(HTMLBuilder.rendererURL())
        let resourcesDir = try XCTUnwrap(HTMLBuilder.webResourcesDirectory())
        // 表示判定にレイアウトが要るので、大きさのある WKWebView を使う
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        webView.loadFileURL(rendererURL, allowingReadAccessTo: resourcesDir)
        try await waitUntil("typeof MDViewer !== 'undefined' && document.readyState === 'complete'")
    }

    override func tearDown() async throws {
        webView = nil
    }

    /// JS の式が true になるまで待つ。
    private func waitUntil(_ condition: String, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ok = try? await webView.evaluateJavaScript(condition) as? Bool, ok { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("timed out waiting for: \(condition)")
    }

    /// Markdown を描画して #content の HTML を返す。
    @discardableResult
    private func render(_ markdown: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            "await MDViewer.setContent(md); return document.getElementById('content').innerHTML;",
            arguments: ["md": markdown],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(result as? String)
    }

    private func evaluate(_ script: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
    }

    // MARK: Performance

    /// 描画にかかった時間（ミリ秒）。
    private func renderMilliseconds(_ markdown: String) async throws -> Double {
        let result = try await webView.callAsyncJavaScript(
            "const t = performance.now(); await MDViewer.setContent(md); return performance.now() - t;",
            arguments: ["md": markdown],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(result as? Double)
    }

    /// 見出し・段落・リストを n 組並べた文書（n=5000 で約 800KB）。脚注も絵文字も含まない。
    private func largeDocument(sections n: Int) -> String {
        (0 ..< n).map { i in
            "## Section \(i)\n\nThis is paragraph \(i) with *emphasis*, `code`, a [link](http://x.com/\(i)) "
                + "and time 12:\(i % 60):00 and note: something.\n\n- item one\n- item two: value\n\n"
        }.joined()
    }

    /// 拡張の走査が文書の長さの2乗にならないこと。変更前の約 130ms に対し、
    /// 2乗だったときは約 2.6 秒かかった（800KB）。
    func test_render_largeDocument_finishesWithinLinearTime() async throws {
        // Arrange
        let markdown = largeDocument(sections: 5000)

        // Act
        let elapsed = try await renderMilliseconds(markdown)

        // Assert
        XCTAssertLessThan(elapsed, 1000, "800KB の描画に \(Int(elapsed))ms")
    }

    /// 脚注の定義が文書末にあると、定義の start() が段落ごとに残り全体を探していた。
    func test_render_largeDocumentWithFootnotes_finishesWithinLinearTime() async throws {
        // Arrange
        let markdown = largeDocument(sections: 5000) + "Ref[^a] :smile:\n\n[^a]: note\n"

        // Act
        let elapsed = try await renderMilliseconds(markdown)

        // Assert
        XCTAssertLessThan(elapsed, 1000, "800KB の描画に \(Int(elapsed))ms")
    }

    /// `_` や `*` が多い長い1段落では、絵文字の start() が地の文を切るたびに残り全体を探していた。
    func test_render_longParagraphWithManyDelimiters_finishesWithinLinearTime() async throws {
        // Arrange
        let markdown = (0 ..< 5000).map { i in "k_\(i): v*\(i) 12:01:00 :x\(i): " }.joined()

        // Act
        let elapsed = try await renderMilliseconds(markdown)

        // Assert
        XCTAssertLessThan(elapsed, 1000, "150KB の1段落の描画に \(Int(elapsed))ms")
    }

    // MARK: Footnotes

    func test_footnote_rendersSuperscriptReferenceAndListWithBackLink() async throws {
        // Act
        let html = try await render("Text.[^1]\n\n[^1]: The note.\n")

        // Assert
        XCTAssertTrue(
            html
                .contains(
                    ##"<sup class="footnote-ref"><a href="#fn:1" id="fnref:1" data-footnote-ref="">1</a></sup>"##
                ),
            html
        )
        XCTAssertTrue(html.contains(#"<li id="fn:1">"#))
        XCTAssertTrue(html.contains("The note."))
        XCTAssertTrue(html.contains(##"href="#fnref:1""##))
        XCTAssertFalse(html.contains("[^1]"))
    }

    /// 番号は定義の順ではなく、本文で参照された順に振る。
    func test_footnote_numbersByFirstReferenceAndSharesNumberForRepeats() async throws {
        // Act
        let html = try await render("A[^b] B[^a] C[^b]\n\n[^a]: alpha\n[^b]: beta\n")

        // Assert
        let footnotes = try await evaluate("""
        return Array.from(document.querySelectorAll('.footnotes li'))
            .map(li => li.id + '=' + li.querySelector('p').firstChild.textContent.trim());
        """) as? [String]
        XCTAssertEqual(footnotes, ["fn:1=beta", "fn:2=alpha"])
        XCTAssertTrue(html.contains(#"id="fnref:1:2""#))
    }

    func test_footnote_undefinedReference_staysAsText() async throws {
        // Act
        let html = try await render("Missing[^nope] here.\n")

        // Assert
        XCTAssertTrue(html.contains("Missing[^nope] here."))
        XCTAssertFalse(html.contains("footnotes"))
    }

    /// 定義の行で段落が切れても、行の途中の「[^1]:」で段落が割れてはいけない。
    func test_footnote_referenceFollowedByColon_staysInParagraph() async throws {
        // Act
        try await render("Text[^1]: more text\n\n[^1]: def\n")

        // Assert
        let paragraphs = try await evaluate("return document.querySelectorAll('#content > p').length;") as? Int
        XCTAssertEqual(paragraphs, 1)
    }

    /// 見出しのアンカーは slugify で作るので「:」を含まず、脚注の id と衝突しない。
    func test_footnote_idsDoNotCollideWithHeadingAnchors() async throws {
        // Act
        try await render("# fn 1\n\nText[^1]\n\n[^1]: note\n")

        // Assert
        let ids =
            try await evaluate("return Array.from(document.querySelectorAll('[id]')).map(e => e.id);") as? [String]
        let all = try XCTUnwrap(ids)
        XCTAssertEqual(all.filter { $0 == "fn-1" }.count, 1)
        XCTAssertEqual(all.filter { $0 == "fn:1" }.count, 1)
        XCTAssertEqual(Set(all).count, all.count)
    }

    /// 見出しは HTML と目次用の文字列とで2回描画されるが、参照は1回と数え、
    /// 目次の項目名とアンカーに脚注の HTML を入れない。
    func test_footnote_inHeading_countsOnceAndStaysOutOfTOCTitle() async throws {
        // Arrange
        let recorder = MessageRecorder()
        webView.configuration.userContentController.add(recorder, name: "headingsExtracted")

        // Act
        let html = try await render("## Results[^1]\n\nBody[^1]\n\n[^1]: note\n")
        try await waitUntil("true")

        // Assert
        XCTAssertTrue(html.contains(#"<h2 id="results">"#), html)
        XCTAssertTrue(html.contains(#"id="fnref:1:2""#))
        XCTAssertFalse(html.contains("fnref:1:3"))
        let headings = try XCTUnwrap(recorder.messages.last as? [[String: Any]])
        XCTAssertEqual(headings.first?["title"] as? String, "Results")
        XCTAssertEqual(headings.first?["anchor"] as? String, "results")
    }

    /// 描画し直しても番号は1から振り直し、一覧は1つだけ。
    func test_footnote_rerender_restartsNumbering() async throws {
        // Act
        try await render("A[^x]\n\n[^x]: once\n")
        let html = try await render("B[^y]\n\n[^y]: twice\n")

        // Assert
        XCTAssertEqual(html.components(separatedBy: "class=\"footnotes\"").count, 2)
        XCTAssertTrue(html.contains(#"<li id="fn:1">"#))
        XCTAssertFalse(html.contains("once"))
    }

    /// 脚注へのリンクはページ内で移動し、#22 のリンク処理（Swift への linkClicked、
    /// ファイルとして開く通知）に渡らない。ナビゲーションの判定は本番の Coordinator が行う。
    func test_footnoteLink_scrollsInPageWithoutOpeningAFile() async throws {
        // Arrange
        let coordinator = WebRendererView.Coordinator(renderVM: RenderViewModel(), sidebarVM: SidebarViewModel())
        webView.navigationDelegate = coordinator
        let recorder = MessageRecorder()
        webView.configuration.userContentController.add(recorder, name: "linkClicked")
        let opened = NotificationRecorder(name: .openLocalDocument)
        let filler = String(repeating: "Filler paragraph.\n\n", count: 80)
        try await render("Top[^1]\n\n\(filler)[^1]: Bottom note\n")

        // Act
        _ = try await evaluate("document.querySelector('a[href=\"#fn:1\"]').click();")
        try await waitUntil("location.hash === '#fn:1' && window.scrollY > 0")

        // Assert
        XCTAssertTrue(recorder.messages.isEmpty)
        XCTAssertEqual(opened.count, 0)
        XCTAssertEqual(webView.url?.lastPathComponent, "renderer.html")
        withExtendedLifetime(coordinator) {}
    }

    // MARK: Emoji

    func test_emoji_shortcodes_becomeEmoji() async throws {
        // Act
        let html = try await render("Ship :rocket: :+1: :100: ok :white_check_mark: 今日は:smile:です :smile::heart:")

        // Assert
        XCTAssertEqual(html, "<p>Ship 🚀 👍 💯 ok ✅ 今日は😄です 😄❤️</p>\n")
    }

    func test_emoji_inHeadingTableAndFootnote_becomeEmoji() async throws {
        // Act
        let html = try await render("# Title :tada:\n\n| a |\n|---|\n| :smile: |\n\nNote[^1]\n\n[^1]: in :heart:\n")

        // Assert
        XCTAssertTrue(html.contains("Title 🎉</h1>"), html)
        XCTAssertTrue(html.contains("<td>😄</td>"), html)
        XCTAssertTrue(html.contains("in ❤️"), html)
    }

    /// 変換してはいけないものの回帰サンプル。
    func test_emoji_leavesCodeMathURLsTimesAndUnknownNamesAlone() async throws {
        let samples: [(String, String)] = [
            ("code span", "`:rocket:` here"),
            ("code block", "```\n:rocket:\n```"),
            ("inline math", "math $:rocket:$ here"),
            ("block math", "$$\n:rocket:\n$$"),
            ("mermaid block", "```mermaid\ngraph TD\n  A:::rocket --> B:::tada:\n```"),
            ("mermaid-like text", "A:::rocket and B:::tada: here"),
            ("bare URL", "see https://example.com/:rocket:/x end"),
            ("autolink", "<https://example.com/:rocket:>"),
            ("time", "at 12:30:45 and 10:100:20"),
            ("letters around", "foo:rocket: and :rocket:bar"),
            ("escaped", "\\:rocket: here"),
            ("raw HTML attribute", "<span title=\":rocket:\">x</span>"),
        ]
        for (name, markdown) in samples {
            // Act
            let html = try await render(markdown)

            // Assert
            XCTAssertFalse(html.contains("🚀") || html.contains("🎉") || html.contains("💯"), "\(name): \(html)")
        }
    }

    func test_emoji_bareURLWithShortcode_staysOneLink() async throws {
        // Act
        let html = try await render("see https://example.com/:rocket:/x end")

        // Assert
        XCTAssertTrue(
            html.contains(#"<a href="https://example.com/:rocket:/x">https://example.com/:rocket:/x</a>"#),
            html
        )
    }

    /// 対応表にない名前と、Object.prototype のプロパティ名は文字のまま残す。
    func test_emoji_unknownAndPrototypeNames_stayAsText() async throws {
        // Act
        let html = try await render(":foo: :constructor: :hasOwnProperty: :toString:")

        // Assert
        XCTAssertEqual(html, "<p>:foo: :constructor: :hasOwnProperty: :toString:</p>\n")
    }

    /// $ の判定規則（#20・#23）を壊していないこと。
    func test_emoji_mathDollarRulesStillHold() async throws {
        // Act
        let html = try await render("`cp $f $f.bak` and \\$5 and $7,463 and $356 :smile:")

        // Assert
        XCTAssertEqual(html, "<p><code>cp $f $f.bak</code> and $5 and $7,463 and $356 😄</p>\n")
    }

    // MARK: Search

    /// 検索の関数を呼び、返ってきた { current, total } を [current, total] で返す。
    private func search(_ call: String) async throws -> [Int] {
        let result = try await evaluate("return \(call);") as? [String: Any]
        let status = try XCTUnwrap(result)
        return [status["current"] as? Int ?? -1, status["total"] as? Int ?? -1]
    }

    private func markCount() async throws -> Int? {
        try await evaluate("return document.querySelectorAll('mark.mdviewer-search-hit').length;") as? Int
    }

    /// KaTeX の読み上げ用 MathML（見えない）は数えず、見えている数式の文字は数える。
    func test_search_ignoresKaTeXMathML() async throws {
        // Arrange
        try await render("x and $x$ and x")

        // Act
        let status = try await search("MDViewer.search('x')")

        // Assert
        XCTAssertEqual(status, [1, 3])
    }

    func test_search_ignoresHiddenElements() async throws {
        // Arrange
        try await render(#"<span style="display:none">word</span> <span style="visibility:hidden">word</span> word"#)

        // Act
        let status = try await search("MDViewer.search('word')")

        // Assert
        XCTAssertEqual(status, [1, 1])
    }

    func test_search_noMatch_reportsZero() async throws {
        // Arrange
        try await render("Hello world")

        // Act
        let status = try await search("MDViewer.search('absent')")

        // Assert
        XCTAssertEqual(status, [0, 0])
        let marks = try await markCount()
        XCTAssertEqual(marks, 0)
    }

    func test_search_nextAndPrevious_wrapAround() async throws {
        // Arrange
        try await render("Apple apple APPLE")
        let first = try await search("MDViewer.search('apple')")

        // Act
        let second = try await search("MDViewer.searchNext()")
        let third = try await search("MDViewer.searchNext()")
        let wrapped = try await search("MDViewer.searchNext()")
        let back = try await search("MDViewer.searchPrevious()")

        // Assert
        XCTAssertEqual(first, [1, 3])
        XCTAssertEqual(second, [2, 3])
        XCTAssertEqual(third, [3, 3])
        XCTAssertEqual(wrapped, [1, 3])
        XCTAssertEqual(back, [3, 3])
        let current = try await evaluate("""
        return Array.from(document.querySelectorAll('mark.mdviewer-search-current')).map(m => m.textContent);
        """) as? [String]
        XCTAssertEqual(current, ["APPLE"])
    }

    /// 太字などで分かれた語も1件として見つけ、段落をまたいでは一致させない。
    func test_search_matchesAcrossInlineElementsButNotParagraphs() async throws {
        // Arrange
        try await render("foo **bar** baz\n\nfoo\n\nbar")

        // Act
        let status = try await search("MDViewer.search('foo bar')")

        // Assert
        XCTAssertEqual(status, [1, 1])
        let marks = try await markCount()
        XCTAssertEqual(marks, 2)
    }

    /// シンタックスハイライトで細かく分かれたコードも検索でき、コピーされる文字は変わらない。
    func test_search_findsTextInHighlightedCode() async throws {
        // Arrange
        try await render("```swift\nlet value = compute(value)\n```")
        let before = try await evaluate("return document.querySelector('pre').textContent;") as? String

        // Act
        let status = try await search("MDViewer.search('value')")

        // Assert
        XCTAssertEqual(status, [1, 2])
        let after = try await evaluate("return document.querySelector('pre').textContent;") as? String
        XCTAssertEqual(after, before)
    }

    /// 検索を閉じたら、ハイライトを消して元の DOM に戻す。
    func test_clearSearch_restoresOriginalDOM() async throws {
        // Arrange
        let original = try await render("Some **some** text with some words")
        _ = try await search("MDViewer.search('some')")

        // Act
        _ = try await search("MDViewer.clearSearch()")

        // Assert
        let html = try await evaluate("return document.getElementById('content').innerHTML;") as? String
        XCTAssertEqual(html, original)
    }

    /// ファイルの自動再読み込みなどで描画し直したら、同じ語で数え直して Swift に知らせる。
    func test_search_rerender_recountsAndNotifies() async throws {
        // Arrange
        let recorder = MessageRecorder()
        webView.configuration.userContentController.add(recorder, name: "searchResultsChanged")
        try await render("one two one two one")
        _ = try await search("MDViewer.search('two')")
        _ = try await search("MDViewer.searchNext()")

        // Act
        try await render("two only")
        try await waitUntil("true")

        // Assert
        let last = try XCTUnwrap(recorder.messages.last as? [String: Any])
        XCTAssertEqual(last["current"] as? Int, 1)
        XCTAssertEqual(last["total"] as? Int, 1)
        let marks = try await markCount()
        XCTAssertEqual(marks, 1)
    }

    /// Mermaid の図は描き終えてから数え直す。図に置き換える前のソースは数えない。
    func test_search_countsMermaidLabelsAfterDiagramIsDrawn() async throws {
        // Arrange
        let recorder = MessageRecorder()
        webView.configuration.userContentController.add(recorder, name: "searchResultsChanged")
        _ = try await search("MDViewer.search('Alphanode')")

        // Act
        try await render("```mermaid\ngraph TD\n  A[Alphanode] --> B[Betanode]\n```")
        try await waitUntil("document.querySelector('.mermaid svg') !== null")
        try await waitUntil("document.querySelectorAll('mark.mdviewer-search-hit').length > 0")

        // Assert
        let last = try XCTUnwrap(recorder.messages.last as? [String: Any])
        XCTAssertEqual(last["total"] as? Int, 1)
        let insideSVG =
            try await evaluate(
                "return document.querySelector('mark.mdviewer-search-hit').closest('svg') !== null;"
            ) as? Bool
        XCTAssertEqual(insideSVG, true)
    }
}

private final class MessageRecorder: NSObject, WKScriptMessageHandler {
    private(set) var messages: [Any] = []

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        messages.append(message.body)
    }
}

private final class NotificationRecorder {
    private(set) var count = 0
    private var observer: NSObjectProtocol?

    init(name: Notification.Name) {
        observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.count += 1
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
