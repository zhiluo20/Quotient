// 生成 Quotient 应用图标：深色玻璃圆角方块 + 红黄绿 LED + 额度进度条
// 用法: swift Scripts/make_icon.swift <输出 png 路径>
import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "icon_1024.png"

let canvas: CGFloat = 1024
// macOS 图标内容区约占画布 80%，四周留透明边距
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let radius: CGFloat = rect.width * 0.225

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 背景：深色渐变圆角方块
let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1),
])!.draw(in: bg, angle: -90)

// 顶部高光描边，模拟玻璃
NSColor.white.withAlphaComponent(0.18).setStroke()
let strokePath = NSBezierPath(
    roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: radius - 3, yRadius: radius - 3)
strokePath.lineWidth = 6
strokePath.stroke()

// 三颗 LED
let ledColors: [NSColor] = [
    NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.27, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.15, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.90, blue: 0.45, alpha: 1),
]
let ledRadius: CGFloat = 66
let ledSpacing: CGFloat = 210
let ledY = canvas / 2 + 110
for (i, color) in ledColors.enumerated() {
    let x = canvas / 2 + CGFloat(i - 1) * ledSpacing
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color.withAlphaComponent(0.85)
    shadow.shadowBlurRadius = 56
    shadow.set()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: x - ledRadius, y: ledY - ledRadius,
        width: ledRadius * 2, height: ledRadius * 2)).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
}

// 额度进度条：轨道 + 绿色填充
let barWidth: CGFloat = 520
let barHeight: CGFloat = 58
let barY = canvas / 2 - 160
let track = NSRect(x: canvas / 2 - barWidth / 2, y: barY, width: barWidth, height: barHeight)
NSColor.white.withAlphaComponent(0.14).setFill()
NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
var fill = track
fill.size.width = barWidth * 0.68
NSGraphicsContext.current?.saveGraphicsState()
let barShadow = NSShadow()
barShadow.shadowColor = ledColors[2].withAlphaComponent(0.6)
barShadow.shadowBlurRadius = 28
barShadow.set()
ledColors[2].setFill()
NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
NSGraphicsContext.current?.restoreGraphicsState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("无法生成 PNG")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("✅ 图标已生成: \(outPath)")
