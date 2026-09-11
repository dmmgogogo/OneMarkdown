#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreText

// OneMarkdown 应用图标生成器：靛蓝渐变 squircle + 白色折角纸页 + "M↓" 标记
// 用法: swift generate_app_icon.swift <output_1024.png> [--simple]
//   --simple  只画底色 + 白色 M↓，用于 16/32 小尺寸

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: generate_app_icon.swift <output.png> [--simple]\n", stderr)
    exit(1)
}
let outPath = args[1]
let simple = args.contains("--simple")

let size: CGFloat = 1024
let inset: CGFloat = 100
let cornerRadius: CGFloat = 185
let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let center = CGPoint(x: size / 2, y: size / 2)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.interpolationQuality = .high
ctx.setShouldAntialias(true)
ctx.setAllowsAntialiasing(true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r / 255, g / 255, b / 255, a])!
}

let indigoTop = rgb(0x5B, 0x7C, 0xFF)
let indigoBottom = rgb(0x2E, 0x3F, 0xD1)

// ---- 1. squircle 底：靛蓝纵向渐变 + 顶部高光 ----
let bgPath = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let bgGradient = CGGradient(colorsSpace: colorSpace, colors: [indigoTop, indigoBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
let highlight = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(255, 255, 255, 0.14), rgb(255, 255, 255, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(highlight, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: size * 0.5), options: [])
// 底部一点暗角，增加厚度感
let shade = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.12)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: size * 0.4), end: CGPoint(x: 0, y: inset), options: [])
ctx.restoreGState()

// ---- 2. 纸页（带折角）----
let paperW: CGFloat = 520
let paperH: CGFloat = 640
let paperR: CGFloat = 44
let fold: CGFloat = 128
let paper = CGRect(x: center.x - paperW / 2, y: center.y - paperH / 2, width: paperW, height: paperH)

func paperPath() -> CGPath {
    let p = CGMutablePath()
    let minX = paper.minX, maxX = paper.maxX, minY = paper.minY, maxY = paper.maxY
    p.move(to: CGPoint(x: minX + paperR, y: maxY))
    p.addLine(to: CGPoint(x: maxX - fold, y: maxY))          // 顶边到折角起点
    p.addLine(to: CGPoint(x: maxX, y: maxY - fold))          // 斜切
    p.addLine(to: CGPoint(x: maxX, y: minY + paperR))
    p.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX - paperR, y: minY), radius: paperR)
    p.addLine(to: CGPoint(x: minX + paperR, y: minY))
    p.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX, y: minY + paperR), radius: paperR)
    p.addLine(to: CGPoint(x: minX, y: maxY - paperR))
    p.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX + paperR, y: maxY), radius: paperR)
    p.closeSubpath()
    return p
}

if !simple {
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // 投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44, color: rgb(0, 0, 0, 0.28))
    ctx.addPath(paperPath())
    ctx.setFillColor(rgb(255, 255, 255))
    ctx.fillPath()
    ctx.restoreGState()

    // 折角三角（略灰，表示翻折的背面）
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: paper.maxX - fold, y: paper.maxY))
    foldPath.addLine(to: CGPoint(x: paper.maxX - fold, y: paper.maxY - fold))
    foldPath.addLine(to: CGPoint(x: paper.maxX, y: paper.maxY - fold))
    foldPath.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -4, height: -4), blur: 10, color: rgb(0, 0, 0, 0.18))
    ctx.addPath(foldPath)
    ctx.setFillColor(rgb(0xE3, 0xE8, 0xF2))
    ctx.fillPath()
    ctx.restoreGState()

    // 三条文本条
    let barColor = rgb(0xC9, 0xD1, 0xE0)
    let barH: CGFloat = 30
    let barX = paper.minX + 60
    let usable = paperW - 120 - fold * 0.35
    let widths: [CGFloat] = [0.55, 0.85, 0.42]
    var y = paper.maxY - 88
    for w in widths {
        let rect = CGRect(x: barX, y: y - barH, width: usable * w, height: barH)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        ctx.setFillColor(barColor)
        ctx.fillPath()
        y -= barH + 28
    }
    ctx.restoreGState()
}

// ---- 3. "M↓" 标记 ----
let markFontSize: CGFloat = simple ? 520 : 290
let nsFont = NSFont.systemFont(ofSize: markFontSize, weight: .heavy)
let ctFont = nsFont as CTFont
var unichars: [UniChar] = Array("M".utf16)
var glyphs: [CGGlyph] = [0]
guard CTFontGetGlyphsForCharacters(ctFont, &unichars, &glyphs, 1),
      let mPath = CTFontCreatePathForGlyph(ctFont, glyphs[0], nil) else {
    fputs("glyph lookup failed\n", stderr); exit(4)
}
let mBounds = mPath.boundingBox

// 箭头尺寸随字号缩放
let arrowGap = markFontSize * 0.10
let shaftW = markFontSize * 0.16
let headW = markFontSize * 0.40
let headH = markFontSize * 0.26
let arrowH = mBounds.height
let arrowW = headW
let totalW = mBounds.width + arrowGap + arrowW

// 标记整体的中心：simple 模式居中；正常模式放在纸页下半部
let markCenterY: CGFloat = simple ? center.y : paper.minY + paperH * 0.34
let startX = center.x - totalW / 2

var mTransform = CGAffineTransform(translationX: startX - mBounds.minX, y: markCenterY - mBounds.midY)
let mCentered = mPath.copy(using: &mTransform)!

let arrowX = startX + mBounds.width + arrowGap
let arrowTop = markCenterY + arrowH / 2
let arrowBottom = markCenterY - arrowH / 2
let arrow = CGMutablePath()
// 竖杆
arrow.addRect(CGRect(x: arrowX + (arrowW - shaftW) / 2, y: arrowBottom + headH - 4, width: shaftW, height: arrowTop - arrowBottom - headH + 4))
// 箭头
arrow.move(to: CGPoint(x: arrowX, y: arrowBottom + headH))
arrow.addLine(to: CGPoint(x: arrowX + arrowW, y: arrowBottom + headH))
arrow.addLine(to: CGPoint(x: arrowX + arrowW / 2, y: arrowBottom))
arrow.closeSubpath()

let markPath = CGMutablePath()
markPath.addPath(mCentered)
markPath.addPath(arrow)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
if simple {
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(markPath)
    ctx.setFillColor(rgb(255, 255, 255))
    ctx.fillPath()
} else {
    ctx.addPath(markPath)
    ctx.clip()
    let markGradient = CGGradient(colorsSpace: colorSpace, colors: [indigoTop, indigoBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        markGradient,
        start: CGPoint(x: 0, y: markCenterY + arrowH / 2),
        end: CGPoint(x: 0, y: markCenterY - arrowH / 2),
        options: []
    )
}
ctx.restoreGState()

// ---- 输出 PNG ----
guard let cgImage = ctx.makeImage() else { fputs("makeImage failed\n", stderr); exit(2) }
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let data = rep.representation(using: .png, properties: [:]) else { fputs("png encode failed\n", stderr); exit(3) }
try data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
