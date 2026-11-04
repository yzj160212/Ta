import AppKit
import XCTest
@testable import AIScreenshotApp

/// Dock 图标尺寸的回归防线。
///
/// macOS 的 App 图标网格是「1024 画布上 824×824 的图形」（80.47%），Finder、
/// Chrome 等应用在 Dock 里都渲染成 tilesize 的 ~80.5%。踩过的坑：
///
/// 1. `AppDelegate` 里用满幅美术图设置 `applicationIconImage`，Dock 会把它撑满
///    整块图标位（实测 134px vs 邻居 110px @ tilesize 67pt），看起来比其他 App 大一圈；
/// 2. `.icns` 若直接往 ImageIO 里塞 16…1024 的原始尺寸，64 和 1024 会被静默丢弃，
///    缺少 @2x 大层，Retina 上发虚，且图形占比失控。
final class AppIconAssetTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AIScreenshotAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    func testIconFileKeepsAppleStandardGridProportion() throws {
        let icns = repositoryRoot.appendingPathComponent("Resources/Ta.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: icns.path), "缺少 Resources/Ta.icns")

        guard let source = CGImageSourceCreateWithURL(icns as CFURL, nil) else {
            return XCTFail("无法读取 Resources/Ta.icns")
        }

        var largestIndex = 0
        var largestWidth = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int
            else { continue }
            if width > largestWidth {
                largestWidth = width
                largestIndex = index
            }
        }

        XCTAssertGreaterThanOrEqual(largestWidth, 1024, "缺少 1024 大层（@2x），Retina 上会发虚")
        XCTAssertGreaterThanOrEqual(
            CGImageSourceGetCount(source),
            8,
            ".icns 层数不足，@2x 变体被丢了"
        )

        guard let image = CGImageSourceCreateImageAtIndex(source, largestIndex, nil) else {
            return XCTFail("无法解码 .icns 最大层")
        }
        let ratio = try opaqueRatio(of: image)
        XCTAssertEqual(
            ratio,
            0.805,
            accuracy: 0.025,
            "图标图形应占画布的 80.5%（macOS 标准网格），当前 \(String(format: "%.1f%%", ratio * 100))。"
                + " 过大或过小都会和 Dock 里其他 App 不一致。"
        )
    }

    func testAppDelegateDoesNotOverrideBundleIcon() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/AIScreenshotApp/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let offenders = source
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .filter { $0.contains("applicationIconImage") && $0.contains("=") }
        XCTAssertTrue(
            offenders.isEmpty,
            """
            不要在 AppDelegate 里设置 applicationIconImage：Dock 会把满幅美术图撑满整块\
            图标位，导致「拓」比其他 App 明显大一圈。请让 bundle 里的 Ta.icns 决定图标。
            """
        )
    }

    private func opaqueRatio(of image: CGImage) throws -> Double {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("无法创建位图上下文")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where buffer[(y * width + x) * 4 + 3] > 128 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX > 0, maxY > 0 else { throw XCTSkip("图标为空") }
        let contentWidth = Double(maxX - minX + 1)
        let contentHeight = Double(maxY - minY + 1)
        return max(contentWidth, contentHeight) / Double(width)
    }
}