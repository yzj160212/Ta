import AppKit
import SwiftUI
import XCTest
@testable import AIScreenshotApp

/// 深色模式下「看不见字」的回归防线。
///
/// 底色与文字必须成对翻转：任何一处 `.primary` / `.secondary` 文字都靠
/// 所在的面来保证对比度，所以色板里「文字色 / 面底色」这一组对的对比度
/// 必须在两种外观下都达标。
final class TaPaletteAppearanceTests: XCTestCase {
    private let light = NSAppearance(named: .aqua)!
    private let dark = NSAppearance(named: .darkAqua)!

    func testBodyTextStaysReadableOnEverySurface() {
        for appearance in [light, dark] {
            assertContrast(
                TaPalette.inkColor,
                on: TaPalette.paperColor,
                atLeast: 7.0,
                appearance,
                label: "正文 on 页面底色"
            )
            assertContrast(
                TaPalette.inkColor,
                on: TaPalette.elevatedPaperColor,
                atLeast: 7.0,
                appearance,
                label: "正文 on 卡片底色"
            )
            assertContrast(
                TaPalette.mutedInkColor,
                on: TaPalette.paperColor,
                atLeast: 4.5,
                appearance,
                label: "次级文字 on 页面底色"
            )
            assertContrast(
                TaPalette.mutedInkColor,
                on: TaPalette.elevatedPaperColor,
                atLeast: 4.5,
                appearance,
                label: "次级文字 on 卡片底色"
            )
        }
    }

    func testFixedAccentSurfacesKeepTheirOwnContrast() {
        for appearance in [light, dark] {
            assertContrast(
                TaPalette.onInkSurfaceColor,
                on: TaPalette.inkSurfaceColor,
                atLeast: 7.0,
                appearance,
                label: "墨色卡片上的文字"
            )
            assertContrast(
                TaPalette.onCinnabarColor,
                on: TaPalette.cinnabarColor,
                // 朱砂色块只承载图标 / 品牌字样（装饰性，已 accessibilityHidden），
                // 按 WCAG 1.4.11 的非文本对比度下限 3:1 要求，不再抬高。
                atLeast: 3.0,
                appearance,
                label: "朱砂色块上的图标"
            )
            assertContrast(
                TaPalette.cinnabarColor,
                on: TaPalette.paperColor,
                atLeast: 4.0,
                appearance,
                label: "朱砂强调色 on 页面底色"
            )
        }
    }

    func testPaletteActuallyFlipsBetweenAppearances() {
        XCTAssertNotEqual(
            luminance(TaPalette.paperColor, in: light),
            luminance(TaPalette.paperColor, in: dark),
            "页面底色必须随系统外观翻转，否则深色模式下会变成亮底浅字。"
        )
        XCTAssertNotEqual(
            luminance(TaPalette.inkColor, in: light),
            luminance(TaPalette.inkColor, in: dark),
            "正文色必须随系统外观翻转。"
        )
        XCTAssertLessThan(
            luminance(TaPalette.paperColor, in: dark),
            luminance(TaPalette.inkColor, in: dark),
            "深色外观下页面底色应比文字更暗。"
        )
        XCTAssertLessThan(
            luminance(TaPalette.inkColor, in: light),
            luminance(TaPalette.paperColor, in: light),
            "浅色外观下正文色应比页面底色更暗。"
        )
    }

    /// 端到端回归：真的把「品牌底色 + 未指定颜色的文字」渲染成图，
    /// 深色外观下应当是深底浅字。
    @MainActor
    func testRenderedPaperSurfaceIsDarkWithVisibleText() throws {
        let view = ZStack {
            TaPaperBackground()
            VStack(alignment: .leading, spacing: 6) {
                Text("设置").font(.headline)
                Text("跟随系统外观").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(width: 240, height: 120)

        let image = try render(view, appearance: .darkAqua)
        let samples = try pixelSamples(image)

        let meanLuminance = samples.map(\.luminance).reduce(0, +) / Double(samples.count)
        XCTAssertLessThan(meanLuminance, 0.35, "深色外观下设置界面的底色渲染成了亮色。")

        let brightest = samples.map(\.luminance).max() ?? 0
        let contrast = (brightest + 0.05) / (meanLuminance + 0.05)
        XCTAssertGreaterThan(contrast, 4.5, "深色外观下的文字与底色对比不足。")
    }

    func testSystemSemanticTextColorsContrastWithOurSurfaces() {
        // `Text` 不指定颜色时用的是系统语义色（label / secondaryLabel），
        // 它们完全跟随系统外观：深色外观下 label 是纯白。
        // 所以底色必须同步翻转——否则就是白字压在米色纸上，对比度 ≈ 1.07:1，等于看不见。
        for appearance in [light, dark] {
            let isDark = appearance.name == .darkAqua
            for surface in [TaPalette.paperColor, TaPalette.elevatedPaperColor] {
                assertContrast(
                    .labelColor,
                    on: surface,
                    atLeast: 7.0,
                    appearance,
                    label: "系统正文色"
                )
                assertContrast(
                    .secondaryLabelColor,
                    on: surface,
                    atLeast: isDark ? 4.5 : 3.0,
                    appearance,
                    label: "系统次级文字色"
                )
            }
        }
    }

    // MARK: - Helpers

    private func assertContrast(
        _ foreground: NSColor,
        on background: NSColor,
        atLeast minimum: Double,
        _ appearance: NSAppearance,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = contrastRatio(foreground, background, in: appearance)
        XCTAssertGreaterThanOrEqual(
            ratio,
            minimum,
            "\(label)对比度 \(String(format: "%.2f", ratio)) 低于 \(minimum)（外观：\(appearance.name.rawValue)）",
            file: file,
            line: line
        )
    }

    private func contrastRatio(_ a: NSColor, _ b: NSColor, in appearance: NSAppearance) -> Double {
        // secondaryLabel / tertiaryLabel 是带透明度的，需要先叠到底色上再算。
        let background = resolvedLuminanceColor(b, in: appearance)
        let foreground = resolvedLuminanceColor(a, in: appearance)
        let composited = (r: foreground.r * foreground.a + background.r * (1 - foreground.a),
                          g: foreground.g * foreground.a + background.g * (1 - foreground.a),
                          b: foreground.b * foreground.a + background.b * (1 - foreground.a))
        let first = relativeLuminance(red: composited.r, green: composited.g, blue: composited.b)
        let second = relativeLuminance(red: background.r, green: background.g, blue: background.b)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: NSColor, in appearance: NSAppearance) -> Double {
        let resolved = resolvedLuminanceColor(color, in: appearance)
        return relativeLuminance(red: resolved.r, green: resolved.g, blue: resolved.b)
    }

    private func resolvedLuminanceColor(
        _ color: NSColor,
        in appearance: NSAppearance
    ) -> (r: Double, g: Double, b: Double, a: Double) {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return (
            r: Double(resolved.redComponent),
            g: Double(resolved.greenComponent),
            b: Double(resolved.blueComponent),
            a: Double(resolved.alphaComponent)
        )
    }

    private func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    @MainActor
    private func render(_ view: some View, appearance name: NSAppearance.Name) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: name)
        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.appearance = appearance
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 120)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw XCTSkip("无法为视图创建位图上下文")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        return representation
    }

    private func pixelSamples(_ representation: NSBitmapImageRep) throws -> [(luminance: Double, color: NSColor)] {
        var samples: [(luminance: Double, color: NSColor)] = []
        let width = representation.pixelsWide
        let height = representation.pixelsHigh
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        for y in stride(from: 0, to: height, by: 3) {
            for x in stride(from: 0, to: width, by: 3) {
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let value = relativeLuminance(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                )
                samples.append((luminance: value, color: color))
            }
        }
        return samples
    }
}