#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 把一张「满幅圆角纸面」母版（如 Resources/Brand/Ta-AppIcon.png，1024×1024，圆角半径 228）
// 生成为符合 macOS 图标网格的 .icns。
//
// 用法：
//   swift scripts/generate-app-icon.swift INPUT.png OUTPUT.icns [contentScale]
//
// contentScale 是图形内容占画布的比例。macOS 自家 App（Finder、备忘录等）在 Dock 里
// 稳定渲染成 tilesize 的 ~80.5%，要让「拓」和邻居看起来一样大，就得对齐这个比例。
// 具体数值由实测 Dock 像素反推，见下方 DEFAULT_CONTENT_SCALE 的注释。
//
// 实现上走 Apple 推荐的 iconset → iconutil 路径，而不是直接往 .icns 里塞原始尺寸：
// ImageIO 对 64 / 1024 这类尺寸没有对应的 icns 元素类型，会静默丢弃，
// 结果就是缺少 @2x 大层（Retina 上发虚）。

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fputs("Usage: swift generate-app-icon.swift INPUT.png OUTPUT.icns [contentScale]\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let contentScale = arguments.count > 3 ? (Double(arguments[3]) ?? 0.686) : 0.686

// Apple 的 macOS 图标网格：1024 画布上图形本体 824×824（80.47%）。
// 实测本机 Finder / Chrome / Telegram / WeChat 在 tilesize=67pt 时都渲染成 110px/134px = 82%，
// 而当前 .icns（contentScale 0.82）渲染成 134px = 100%，比邻居大一圈。
// 0.686 由线性反推得到，装机后再实测校准。
let points: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Unable to read input image: \(inputURL.path)\n", stderr)
    exit(3)
}

let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("TaAppIcon-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetURL) }

for (name, size) in points {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Unable to create \(size)px canvas.\n", stderr)
        exit(4)
    }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    let contentSize = CGFloat(size) * CGFloat(contentScale)
    let inset = (CGFloat(size) - contentSize) / 2
    context.draw(
        sourceImage,
        in: CGRect(x: inset, y: inset, width: contentSize, height: contentSize)
    )

    guard
        let iconImage = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            iconsetURL.appendingPathComponent("\(name).png") as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        fputs("Unable to render \(name).\n", stderr)
        exit(5)
    }
    CGImageDestinationAddImage(destination, iconImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        fputs("Unable to write \(name).\n", stderr)
        exit(6)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed with status \(iconutil.terminationStatus)\n", stderr)
    exit(7)
}

print("wrote \(outputURL.path) (contentScale \(contentScale))")