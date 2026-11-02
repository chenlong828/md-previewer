#!/usr/bin/env swift
// MDPreview 应用图标生成器（MP 字标）
//
// 设计口径：macOS Big Sur 图标网格 + 界面同款系统字体（SF Pro Heavy）
//   - 画布 1024，四周留白 60，圆角半径 = 内容宽 × 0.225
//   - 底：纸白垂直微渐变 #FFFFFF → #F2F2F3
//   - 字：M 墨黑 #2B2B2D，P 界面链接蓝 #4183C4（与 --link-color 同值）
//   - 字距 -0.035em；按 cap height 光学居中
//
// 每个尺寸按矢量几何原生渲染（不是从 1024 缩放），16/32px 更清晰。
//
// 用法：swift resources/icon/render-icon.swift [输出.icns]
//       默认输出 <repo>/resources/AppIcon.icns
// 依赖：macOS（AppKit + /usr/bin/iconutil），无第三方。

import AppKit
import Foundation

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outputURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : scriptDir.deletingLastPathComponent().appendingPathComponent("AppIcon.icns")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let ink = color(0x2B2B2D)
let blue = color(0x4183C4)
let paperTop = color(0xFFFFFF)
let paperBottom = color(0xF2F2F3)

let masterSize: CGFloat = 1024
let marginRatio: CGFloat = 60 / 1024
let cornerRatio: CGFloat = 0.225
let fontSizeRatio: CGFloat = 430 / 1024
let kernRatio: CGFloat = -0.035

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    let scale = size / masterSize

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let margin = masterSize * marginRatio * scale
    let body = NSRect(x: margin, y: margin,
                      width: size - 2 * margin, height: size - 2 * margin)
    let radius = body.width * cornerRatio
    let squircle = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGradient(starting: paperBottom, ending: paperTop)!.draw(in: squircle, angle: 90)

    // 顶部柔光，避免纯白底在浅色桌面上完全失去体积
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(starting: color(0xFFFFFF, 0), ending: color(0xFFFFFF, 0.55))!
        .draw(in: body, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // 1px 内描边，让白色图标在白底 Finder 里仍有边界
    let border = NSBezierPath(roundedRect: body.insetBy(dx: 0.75 * scale, dy: 0.75 * scale),
                              xRadius: radius, yRadius: radius)
    border.lineWidth = max(1, 1.5 * scale)
    color(0x000000, 0.05).setStroke()
    border.stroke()

    let fontSize = masterSize * fontSizeRatio * scale
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let kern = fontSize * kernRatio
    let baselineY = body.midY - font.capHeight / 2

    func glyph(_ text: String, _ tint: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: tint, .kern: kern
        ])
    }

    let m = glyph("M", ink)
    let p = glyph("P", blue)
    let totalWidth = m.size().width + p.size().width
    let x = body.midX - totalWidth / 2
    let y = baselineY + font.descender
    m.draw(at: NSPoint(x: x, y: y))
    p.draw(at: NSPoint(x: x + m.size().width, y: y))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let representations: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for rep in representations {
    let png = renderIcon(pixels: rep.pixels).representation(using: .png, properties: [:])!
    try png.write(to: iconsetURL.appendingPathComponent(rep.name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconsetURL)

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil 失败，退出码 \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}
print("已生成 \(outputURL.path)（\(representations.count) 个尺寸，16–1024px）")
