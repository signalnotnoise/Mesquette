import XCTest
@testable import Mesquette

final class ImageBackgroundRemovalTests: XCTestCase {

    func testAlphaBoundsFindsForeground() {
        // 4x3 mask, foreground at x=1...2, y=0...1
        let mask: [UInt8] = [
            0, 255, 255, 0,
            0, 200, 0, 0,
            0, 0, 0, 0,
        ]
        let bounds = ImageBackgroundRemoval.alphaBounds(data: mask, width: 4, height: 3, threshold: 10)
        XCTAssertEqual(bounds, CGRect(x: 1, y: 0, width: 2, height: 2))
    }

    func testAlphaBoundsEmptyMask() {
        let bounds = ImageBackgroundRemoval.alphaBounds(
            data: [UInt8](repeating: 0, count: 16), width: 4, height: 4, threshold: 10)
        XCTAssertNil(bounds)
    }

    func testSquareCanvasMatchesUpstreamRatio() {
        // Upstream resize_foreground(ratio 0.85): canvas side = max(w,h)/0.85.
        XCTAssertEqual(
            ImageBackgroundRemoval.squareCanvasSide(foregroundWidth: 170, height: 100, ratio: 0.85), 200)
        XCTAssertEqual(
            ImageBackgroundRemoval.squareCanvasSide(foregroundWidth: 100, height: 85, ratio: 0.85), 118)
    }
}
