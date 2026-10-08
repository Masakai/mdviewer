import AppKit
import XCTest
@testable import MDViewer

final class WindowPlacementTests: XCTestCase {
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1170)
    private let size = NSSize(width: 960, height: 732)

    func test_基準ウィンドウから右下に1段ずらす() {
        let reference = NSRect(x: 480, y: 328, width: 960, height: 732)
        let point = WindowPlacement.cascadedTopLeft(from: reference, windowSize: size, visibleFrame: visibleFrame)
        XCTAssertEqual(point, NSPoint(x: 480 + WindowPlacement.cascadeOffset, y: 1060 - WindowPlacement.cascadeOffset))
    }

    func test_下にはみ出す場合は画面の左上に戻す() {
        let reference = NSRect(x: 480, y: 10, width: 960, height: 732)
        let point = WindowPlacement.cascadedTopLeft(from: reference, windowSize: size, visibleFrame: visibleFrame)
        XCTAssertEqual(point, NSPoint(x: 0, y: 1170))
    }

    func test_右にはみ出す場合は画面の左上に戻す() {
        let reference = NSRect(x: 950, y: 328, width: 960, height: 732)
        let point = WindowPlacement.cascadedTopLeft(from: reference, windowSize: size, visibleFrame: visibleFrame)
        XCTAssertEqual(point, NSPoint(x: 0, y: 1170))
    }

    func test_何段重ねても画面内に収まる() {
        var frame = NSRect(x: 480, y: 328, width: size.width, height: size.height)
        for _ in 0 ..< 100 {
            let point = WindowPlacement.cascadedTopLeft(from: frame, windowSize: size, visibleFrame: visibleFrame)
            frame = NSRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height)
            XCTAssertTrue(visibleFrame.contains(frame), "\(frame)")
        }
    }

    func test_基準ウィンドウが画面上端より上にあっても上端に収める() {
        let reference = NSRect(x: 100, y: 500, width: 960, height: 732)
        let point = WindowPlacement.cascadedTopLeft(from: reference, windowSize: size, visibleFrame: visibleFrame)
        XCTAssertEqual(point.y, 1170)
    }
}
