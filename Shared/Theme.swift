import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// 纸感手账视觉系统：颜色、字体、间距
public enum Theme {

    // MARK: - 颜色

    private static func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        #if canImport(AppKit)
        let color = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(srgbHex: isDark ? dark : light)
        }
        return Color(nsColor: color)
        #else
        return Color(hex: light)
        #endif
    }

    /// 纸底
    public static let paper = dynamicColor(light: 0xFBF7EF, dark: 0x1C1A17)
    /// 浮起卡片
    public static let paperRaised = dynamicColor(light: 0xFFFDF8, dark: 0x24211D)
    /// 主文字（墨色）
    public static let ink = dynamicColor(light: 0x2E2A24, dark: 0xEDE6D8)
    /// 次文字
    public static let inkSecondary = dynamicColor(light: 0x8B8272, dark: 0x9A9081)
    /// 朱红强调
    public static let accent = dynamicColor(light: 0xC2533D, dark: 0xD9694F)

    /// 发丝分隔线
    public static var hairline: Color { ink.opacity(0.10) }
    /// 网格纸线
    public static var gridLine: Color { ink.opacity(0.055) }
    /// 纸纤维噪点
    public static var fiber: Color { ink.opacity(0.035) }
    /// 休息日底色
    public static var restDayFill: Color { ink.opacity(0.04) }
    /// 悬停高亮
    public static var hoverFill: Color { ink.opacity(0.045) }
    /// 选中/今天底色
    public static var todayFill: Color { accent.opacity(0.10) }

    // MARK: - 字体

    /// 衬线（New York）：数字、标题
    public static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// 正文无衬线
    public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// 小号大写标签感
    public static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium)
    }

    // MARK: - 尺寸

    public static let cardRadius: CGFloat = 12
    public static let pagePadding: CGFloat = 24
    public static let cardPadding: CGFloat = 16
    public static let sidebarWidth: CGFloat = 84
}

// MARK: - 颜色工具

public extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

#if canImport(AppKit)
extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
#endif
