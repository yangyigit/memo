import SwiftUI

/// 确定性随机数（保证纸纹每次渲染一致）
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}

/// 纸底：底色 + 细网格 + 纸纤维噪点
public struct PaperTexture: View {
    public var gridSpacing: CGFloat
    public var showsGrid: Bool
    public var showsNoise: Bool
    public var fiberCount: Int

    public init(gridSpacing: CGFloat = 14, showsGrid: Bool = true, showsNoise: Bool = true, fiberCount: Int = 240) {
        self.gridSpacing = gridSpacing
        self.showsGrid = showsGrid
        self.showsNoise = showsNoise
        self.fiberCount = fiberCount
    }

    public var body: some View {
        ZStack {
            Theme.paper
            Canvas { context, size in
                if showsGrid, gridSpacing > 1 {
                    var grid = Path()
                    var x = gridSpacing
                    while x < size.width {
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                        x += gridSpacing
                    }
                    var y = gridSpacing
                    while y < size.height {
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                        y += gridSpacing
                    }
                    context.stroke(grid, with: .color(Theme.gridLine), lineWidth: 0.5)
                }

                if showsNoise {
                    var rng = SeededGenerator(seed: 0x4D45_4D4F)
                    var dots = Path()
                    for _ in 0..<fiberCount {
                        let px = rng.unit() * Double(size.width)
                        let py = rng.unit() * Double(size.height)
                        let r = 0.4 + rng.unit() * 0.8
                        dots.addEllipse(in: CGRect(x: px, y: py, width: r, height: r))
                    }
                    context.fill(dots, with: .color(Theme.fiber))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 纸卡片容器（圆角 + 发丝描边 + 极轻阴影）
public struct PaperCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let showsGrid: Bool
    private let content: Content

    public init(cornerRadius: CGFloat = Theme.cardRadius,
                padding: CGFloat = Theme.cardPadding,
                showsGrid: Bool = true,
                @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.showsGrid = showsGrid
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background {
                PaperTexture(showsGrid: showsGrid)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

/// 发丝分隔线
public struct Hairline: View {
    public var vertical: Bool

    public init(vertical: Bool = false) {
        self.vertical = vertical
    }

    public var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// 细线条进度（手账感，不用实心色块）
public struct ThinProgressBar: View {
    public var value: Double
    public var height: CGFloat

    public init(value: Double, height: CGFloat = 2) {
        self.value = max(0, min(1, value))
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.10))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, geo.size.width * value))
            }
        }
        .frame(height: height)
    }
}

/// 小节标题（字距略放松）
public struct SectionLabel: View {
    public var text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Theme.label(11))
            .tracking(1.2)
            .foregroundStyle(Theme.inkSecondary)
    }
}
