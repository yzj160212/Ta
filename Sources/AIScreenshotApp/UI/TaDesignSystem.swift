import AppKit
import SwiftUI

enum TaBrand {
    static let name = "拓"
    static let englishName = "Ta"
    static let tagline = "把屏幕上的信息，拓下来。"
    static let productDescription = "截图、识别、翻译与标注，一步完成"
}

/// 品牌色板。纸与墨成对翻转：浅色外观是「米纸 + 墨字」，
/// 深色外观是「深墨纸 + 米白字」，因此任何一处 `.primary` / `.secondary`
/// 文字都会和它所在的面自动保持对比，不会出现深色模式下看不见字。
///
/// 少数元素本身就是强反差色块（主按钮、强调行、朱砂图标块），它们用
/// `inkSurface` / `onInkSurface` / `onCinnabar` 这组**固定**色，
/// 不跟随外观翻转，避免「深底上的浅字」被翻成「浅底上的深字」。
enum TaPalette {
    // MARK: 随外观翻转

    /// 页面底色。
    static let paper = Color(nsColor: paperColor)
    /// 卡片、栏位等抬升一层后的底色。
    static let elevatedPaper = Color(nsColor: elevatedPaperColor)
    /// 正文与图标。
    static let ink = Color(nsColor: inkColor)
    /// 次级说明文字。
    static let mutedInk = Color(nsColor: mutedInkColor)
    /// 品牌朱砂。
    static let cinnabar = Color(nsColor: cinnabarColor)

    // MARK: 固定不翻转

    /// 用于「墨色卡片」的底色（主按钮、菜单强调行），两种外观下都保持深墨。
    static let inkSurface = Color(nsColor: inkSurfaceColor)
    /// 墨色卡片上的文字。
    static let onInkSurface = Color(nsColor: onInkSurfaceColor)
    /// 朱砂色块上的文字与图标。
    static let onCinnabar = Color(nsColor: onCinnabarColor)

    static var hairline: Color { ink.opacity(0.10) }

    // MARK: NSColor 实体（测试按外观解析对比度时直接使用）

    static let paperColor = dynamicColor(light: (250, 246, 238), dark: (32, 30, 28))
    static let elevatedPaperColor = dynamicColor(light: (255, 253, 248), dark: (44, 41, 38))
    static let inkColor = dynamicColor(light: (26, 26, 26), dark: (240, 235, 227))
    static let mutedInkColor = dynamicColor(light: (104, 100, 94), dark: (168, 162, 153))
    static let cinnabarColor = dynamicColor(light: (214, 64, 47), dark: (232, 96, 78))

    static let inkSurfaceColor = solidColor(26, 26, 26)
    static let onInkSurfaceColor = solidColor(250, 246, 238)
    static let onCinnabarColor = solidColor(255, 251, 243)
}

private func dynamicColor(
    light: (Double, Double, Double),
    dark: (Double, Double, Double)
) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rgb = isDark ? dark : light
        return NSColor(
            srgbRed: rgb.0 / 255,
            green: rgb.1 / 255,
            blue: rgb.2 / 255,
            alpha: 1
        )
    }
}

private func solidColor(_ red: Double, _ green: Double, _ blue: Double) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

enum TaBrandAssets {
    static let appIcon: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "Ta-AppIcon",
            withExtension: "png",
            subdirectory: "Brand"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

struct TaAppIcon: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let image = TaBrandAssets.appIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(TaPalette.paper)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(TaPalette.cinnabar)
                .padding(size * 0.20)
            Text(TaBrand.name)
                .font(.system(size: size * 0.42, weight: .bold, design: .serif))
                .foregroundStyle(TaPalette.onCinnabar)
        }
    }

}

struct TaPaperBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                TaPalette.paper

                TaAppIcon(size: min(proxy.size.width, proxy.size.height) * 0.62)
                    .opacity(0.025)
                    .offset(x: proxy.size.width * 0.12, y: proxy.size.height * 0.18)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct TaSectionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(TaPalette.cinnabar)
                .frame(width: 18, height: 2)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TaPalette.mutedInk)
        }
    }
}