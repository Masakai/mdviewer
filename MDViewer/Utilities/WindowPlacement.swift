import AppKit

/// 新しいドキュメントウィンドウの配置位置を決める。
enum WindowPlacement {
    /// 標準のカスケードに近いずらし幅。
    static let cascadeOffset: CGFloat = 29

    /// 基準ウィンドウから右下へ1段ずらした左上座標を返す。
    /// 画面からはみ出す場合は、画面の左上に戻して重ねていく。
    static func cascadedTopLeft(from reference: NSRect, windowSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let x = max(reference.minX + cascadeOffset, visibleFrame.minX)
        let y = min(reference.maxY - cascadeOffset, visibleFrame.maxY)
        let fitsRight = x + windowSize.width <= visibleFrame.maxX
        let fitsBottom = y - windowSize.height >= visibleFrame.minY
        if fitsRight, fitsBottom {
            return NSPoint(x: x, y: y)
        }
        return NSPoint(x: visibleFrame.minX, y: visibleFrame.maxY)
    }
}
