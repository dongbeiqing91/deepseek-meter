import AppKit
import SwiftUI

/// 离线渲染：不依赖网络与屏幕权限，用来跟设计稿比对
@MainActor
enum RenderPreview {
    static func write(to path: String) {
        let model = AppModel(preview: true)
        model.cardPinned = true

        let card = CardView(model: model, onSettings: {}, onRefresh: {}, onOpenPlatform: {})
        let newHeight: CGFloat = 35
        let activeShape = WidgetView(model: model, height: newHeight, active: true)
        let idleShape = WidgetView(model: model, height: newHeight, active: false)
        let oldShape = WidgetView(model: model, height: 50, active: true)

        let cardImage = render(card, scale: 2)
        let activeImage = render(activeShape, scale: 4)
        let idleImage = render(idleShape, scale: 4)
        let oldImage = render(oldShape, scale: 4)

        let size = NSSize(width: 940, height: 440)
        let canvas = NSImage(size: size)
        canvas.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        ])?.draw(in: rect, angle: -60)

        // 卡片：按自身比例
        let cardW: CGFloat = 268
        let cardH = cardImage.size.height * (cardW / cardImage.size.width)
        cardImage.draw(in: NSRect(x: 30, y: 70, width: cardW, height: cardH))

        // 矩形 66×35，4 倍渲染
        let rectW: CGFloat = 264, rectH: CGFloat = 140
        activeImage.draw(in: NSRect(x: 350, y: 250, width: rectW, height: rectH))
        idleImage.draw(in: NSRect(x: 350, y: 70, width: rectW, height: rectH))

        // 旧圆形 50，4 倍渲染
        oldImage.draw(in: NSRect(x: 660, y: 190, width: 200, height: 200))

        func label(_ text: String, _ x: CGFloat, _ y: CGFloat) {
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55)
            ]).draw(at: NSPoint(x: x, y: y))
        }
        label("矩形 66 × 35 · hover 100%", 350, 400)
        label("矩形 66 × 35 · idle 50%", 350, 40)
        label("旧：圆形 50", 660, 400)
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            NSLog("[DeepSeekMeter] render failed")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            NSLog("[DeepSeekMeter] rendered \(path)")
        } catch {
            NSLog("[DeepSeekMeter] render write failed: \(error)")
        }
    }

    static func debugWidget(to path: String, active: Bool) {
        let model = AppModel(preview: true)
        let view = ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.13)
            WidgetView(model: model, height: 50, active: active)
                .border(Color.red.opacity(0.6))
        }
        .frame(width: 70, height: 70)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 6
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func render<V: View>(_ view: V, scale: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        if let image = renderer.nsImage { return image }
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}
