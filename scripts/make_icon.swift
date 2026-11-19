import AppKit
import CoreText

// 生成 1024×1024 的 App 图标：深墨圆角底 + 白色 ¥ + 一条品牌蓝进度条
// 用法：swift scripts/make_icon.swift <out.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let side: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: side, height: side))
canvas.lockFocus()

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()

// macOS 图标网格：内容 824×824，圆角 185
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

NSGradient(starting: NSColor(calibratedRed: 0x1B/255.0, green: 0x20/255.0, blue: 0x2B/255.0, alpha: 1),
           ending: NSColor(calibratedRed: 0x0C/255.0, green: 0x0F/255.0, blue: 0x15/255.0, alpha: 1))?
    .draw(in: shape, angle: -90)

shape.addClip()
// 顶部内高光 + 一圈 1px 亮边，浅色背景上也能立住
NSColor.white.withAlphaComponent(0.07).setFill()
NSRect(x: rect.minX, y: rect.maxY - 3, width: rect.width, height: 3).fill()
NSColor.white.withAlphaComponent(0.05).setStroke()
shape.lineWidth = 3
shape.stroke()

// ---- ¥（用 CoreText 的紧致字形框定位，避免行高导致偏移）----
let font = NSFont.systemFont(ofSize: 420, weight: .semibold)
let attr = NSAttributedString(string: "¥", attributes: [.font: font, .foregroundColor: NSColor.white])
let line = CTLineCreateWithAttributedString(attr)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

let glyphCenterY: CGFloat = 572
let baselineY = glyphCenterY - bounds.midY
if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: (side - bounds.width) / 2 - bounds.minX, y: baselineY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// ---- 底部进度条 ----
let barW: CGFloat = 366
let barH: CGFloat = 30
let barY: CGFloat = 297
let barRect = NSRect(x: (side - barW) / 2, y: barY, width: barW, height: barH)
NSColor(calibratedRed: 0x2B/255.0, green: 0x31/255.0, blue: 0x3C/255.0, alpha: 1).setFill()
NSBezierPath(roundedRect: barRect, xRadius: barH / 2, yRadius: barH / 2).fill()

NSColor(calibratedRed: 0x4D/255.0, green: 0x6B/255.0, blue: 0xFE/255.0, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: barRect.minX, y: barY, width: barW * 0.62, height: barH),
             xRadius: barH / 2, yRadius: barH / 2).fill()

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("render failed"); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
