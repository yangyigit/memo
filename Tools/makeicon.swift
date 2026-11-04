import AppKit
import CoreGraphics
import Foundation

// 生成 1024x1024 应用图标：纸底 + 细网格 + 衬线日期数字 + 朱红小点
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// 纸底（圆角方形，macOS 风格留边）
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: 180, cornerHeight: 180, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()

let paper = CGColor(srgbRed: 0.984, green: 0.969, blue: 0.937, alpha: 1)
ctx.setFillColor(paper)
ctx.fill(rect)

// 细网格
ctx.setStrokeColor(CGColor(srgbRed: 0.18, green: 0.16, blue: 0.14, alpha: 0.08))
ctx.setLineWidth(2)
var x = rect.minX + 78
while x < rect.maxX {
    ctx.move(to: CGPoint(x: x, y: rect.minY))
    ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
    x += 78
}
var y = rect.minY + 78
while y < rect.maxY {
    ctx.move(to: CGPoint(x: rect.minX, y: y))
    ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
    y += 78
}
ctx.strokePath()

// 朱红小点（今天）
let accent = CGColor(srgbRed: 0.76, green: 0.33, blue: 0.24, alpha: 1)
ctx.setFillColor(accent)
ctx.fillEllipse(in: CGRect(x: rect.maxX - 250, y: rect.maxY - 250, width: 56, height: 56))

// 衬线数字 4
let ink = CGColor(srgbRed: 0.18, green: 0.16, blue: 0.14, alpha: 1)
NSGraphicsContext.current?.shouldAntialias = true
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "NewYork-Bold", size: 560) ?? NSFont.systemFont(ofSize: 560, weight: .bold),
    .foregroundColor: NSColor(cgColor: ink)!,
    .paragraphStyle: paragraph
]
let text = NSAttributedString(string: "4", attributes: attributes)
let textSize = text.size()
text.draw(in: CGRect(x: rect.midX - textSize.width / 2,
                     y: rect.midY - textSize.height / 2 + 10,
                     width: textSize.width,
                     height: textSize.height))

ctx.restoreGState()

// 描边
ctx.addPath(path)
ctx.setStrokeColor(CGColor(srgbRed: 0.18, green: 0.16, blue: 0.14, alpha: 0.12))
ctx.setLineWidth(3)
ctx.strokePath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
