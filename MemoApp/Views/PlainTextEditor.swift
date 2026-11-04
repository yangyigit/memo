import SwiftUI
import AppKit

/// 自带 placeholder 的 NSTextView：内容为空且**没有聚焦**时才绘制提示文字。
/// 画在文本视图内部，不依赖 SwiftUI 的状态同步，光标和提示文字不会打架。
final class PlaceholderTextView: NSTextView {
    var placeholder: String = ""
    var placeholderFont: NSFont = .systemFont(ofSize: 14)
    var placeholderColor: NSColor = .secondaryLabelColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, window?.firstResponder !== self else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: placeholderFont,
            .foregroundColor: placeholderColor,
            .paragraphStyle: paragraph
        ]
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        let width = max(0, bounds.width - inset.width * 2 - padding * 2)
        let rect = NSRect(x: inset.width + padding,
                          y: inset.height,
                          width: width,
                          height: placeholderFont.pointSize * 2)
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

/// 纸感文本编辑器：去掉系统白底与滚动条轨道，行距可调。
///
/// 防丢字要点：
/// - 编辑过程中**绝不**把模型内容写回编辑器（只在「换了一天」或「未聚焦时外部改动」才同步）
/// - 输入法组字期间（`hasMarkedText()`）不同步给上层，等确认上屏后再同步
/// - 样式只在创建时设置一次，避免打字时反复改 typingAttributes 打断中文输入
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 14
    var lineSpacing: CGFloat = 6
    /// 内容身份（例如日期 key）：变化时才会强制定位到模型内容
    var identity: String = ""
    /// 空内容时的提示文字
    var placeholder: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 2, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = NSColor(Theme.accent)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = 2
        let font = NSFont.systemFont(ofSize: fontSize)
        textView.font = font
        textView.textColor = NSColor(Theme.ink)
        textView.defaultParagraphStyle = style
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor(Theme.ink),
            .paragraphStyle: style
        ]
        textView.placeholder = placeholder
        textView.placeholderFont = font
        textView.placeholderColor = NSColor(Theme.inkSecondary).withAlphaComponent(0.55)

        textView.string = text
        scroll.documentView = textView
        context.coordinator.identity = identity
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? PlaceholderTextView else { return }
        context.coordinator.parent = self

        let identityChanged = context.coordinator.identity != identity
        context.coordinator.identity = identity

        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
            textView.needsDisplay = true
        }

        // 正在打字（有焦点 / 输入法组字中）时不要覆盖编辑器内容，否则会丢字
        let isFocused = textView.window?.firstResponder === textView
        let isComposing = textView.hasMarkedText()
        guard identityChanged || (!isFocused && !isComposing && textView.string != text) else { return }
        guard textView.string != text else { return }

        textView.string = text
        let length = (text as NSString).length
        if length > 0 {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = 2
            textView.textStorage?.setAttributes([
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(Theme.ink),
                .paragraphStyle: style
            ], range: NSRange(location: 0, length: length))
        }
        textView.setSelectedRange(NSRange(location: length, length: 0))
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var identity: String = ""

        init(_ parent: PlainTextEditor) {
            self.parent = parent
            self.identity = parent.identity
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.needsDisplay = true
            // 拼音等输入法还在组字，先不往上同步，避免把半成品写进模型再被回写
            if textView.hasMarkedText() { return }
            guard parent.text != textView.string else { return }
            parent.text = textView.string
        }

        /// 失焦时兜底同步一次（例如输入法组字未确认就点了别处）
        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.needsDisplay = true
            guard parent.text != textView.string else { return }
            parent.text = textView.string
        }
    }
}
