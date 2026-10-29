import XCTest
@testable import MDViewer

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private let page = URL(string: "https://github.com/Masakai/mdviewer/releases/tag/v1.11.0")!

    private func json(tag: String = "v1.11.0",
                      url: String = "https://github.com/Masakai/mdviewer/releases/tag/v1.11.0") -> Data
    {
        Data(#"{"tag_name": "\#(tag)", "html_url": "\#(url)", "draft": false, "prerelease": false}"#.utf8)
    }

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: UpdateChecker.latestReleaseAPI, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - isNewer

    /// 文字列で比べると 1.10.0 は 1.9.0 より前に並ぶ。数値として比べる
    func test_isNewer_comparesNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.10.0"))
    }

    func test_isNewer_sameVersion_isFalse() {
        XCTAssertFalse(UpdateChecker.isNewer("1.10.0", than: "1.10.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.10", than: "1.10.0"))
    }

    func test_isNewer_patchAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10.1", than: "1.10.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0.1", than: "1.10.0"))
    }

    func test_isNewer_leadingV_isIgnored() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.11.0", than: "1.10.0"))
    }

    /// 数値として読めない版番号は新しいとはみなさない（誤って更新を勧めない）
    func test_isNewer_unreadableVersion_isFalse() {
        XCTAssertFalse(UpdateChecker.isNewer("1.11.0-beta", than: "1.10.0"))
        XCTAssertFalse(UpdateChecker.isNewer("latest", than: "1.10.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1..0", than: "1.10.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.11.0", than: "dev"))
    }

    // MARK: - parseRelease

    func test_parseRelease_readsTagAndPage() {
        XCTAssertEqual(UpdateChecker.parseRelease(json()), UpdateChecker.Release(version: "1.11.0", pageURL: page))
    }

    func test_parseRelease_missingOrBrokenFields_isNil() {
        XCTAssertNil(UpdateChecker.parseRelease(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseRelease(Data(#"{"html_url": "https://example.com"}"#.utf8)))
        XCTAssertNil(UpdateChecker.parseRelease(Data(#"{"tag_name": "v1.11.0"}"#.utf8)))
        XCTAssertNil(UpdateChecker.parseRelease(json(tag: "nightly")))
    }

    // MARK: - outcome

    func test_outcome_newerRelease_isUpdateAvailable() {
        let release = UpdateChecker.Release(version: "1.11.0", pageURL: page)
        XCTAssertEqual(UpdateChecker.outcome(latest: release, currentVersion: "1.10.0"), .updateAvailable(release))
    }

    /// 開発中の版のように、使っている版のほうが新しくても最新として扱う
    func test_outcome_sameOrOlderRelease_isUpToDate() {
        let release = UpdateChecker.Release(version: "1.10.0", pageURL: page)
        XCTAssertEqual(UpdateChecker.outcome(latest: release, currentVersion: "1.10.0"), .upToDate)
        XCTAssertEqual(UpdateChecker.outcome(latest: release, currentVersion: "1.11.0"), .upToDate)
    }

    func test_outcome_noRelease_isFailed() {
        XCTAssertEqual(UpdateChecker.outcome(latest: nil, currentVersion: "1.10.0"), .failed)
    }

    // MARK: - fetchLatestRelease

    func test_fetchLatestRelease_requestsLatestReleaseAPI() async {
        // Arrange
        var requested: URLRequest?
        let sut = UpdateChecker { request in
            requested = request
            return (self.json(), self.response(200))
        }

        // Act
        let release = await sut.fetchLatestRelease()

        // Assert
        XCTAssertEqual(release?.version, "1.11.0")
        XCTAssertEqual(requested?.url, UpdateChecker.latestReleaseAPI)
        XCTAssertEqual(requested?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    /// 回数制限（403）やリリースなし（404）は、確認できなかったものとして扱う
    func test_fetchLatestRelease_non200_isNil() async {
        for status in [403, 404, 500] {
            let sut = UpdateChecker { _ in (self.json(), self.response(status)) }
            let release = await sut.fetchLatestRelease()
            XCTAssertNil(release, "status \(status)")
        }
    }

    func test_fetchLatestRelease_networkError_isNil() async {
        // Arrange
        let sut = UpdateChecker { _ in throw URLError(.notConnectedToInternet) }

        // Act
        let release = await sut.fetchLatestRelease()

        // Assert
        XCTAssertNil(release)
    }
}
