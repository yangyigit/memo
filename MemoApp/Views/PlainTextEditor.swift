import SwiftUI
import AppKit

/// 纸感文本编辑器：去掉系统白底与滚动条轨道，行距可调。
///
/// 关键点（防丢字）：
/// - 编辑过程中**绝不**把模型内容写回编辑器（`updateNSView` 只在「换了一天」或「未聚焦时外部改动」才同步）
/// - 输入法组字期间（`hasMarkedText()`）不同步给上层，等确认上屏后再同步
/// - 样式只在创建时设置一次，避免打字时反复改 typingAttributes 打断中文输入
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 14
    var lineSpacing: CGFloat = 6
    /// 内容身份（例如日期 key）：变化时才会强制定位到模型内容
    var identity: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
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

        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = 2
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = NSColor(Theme.ink)
        textView.defaultParagraphStyle = style
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(Theme.ink),
            .paragraphStyle: style
        ]

        textView.string = text
        context.coordinator.identity = identity
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        let identityChanged = context.coordinator.identity != identity
        context.coordinator.identity = identity

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
            // 拼音等输入法还在组字，先不往上同步，避免把半成品写进模型再被回写
            if textView.hasMarkedText() { return }
            guard parent.text != textView.string else { return }
            parent.text = textView.string
        }

        /// 失焦时兜底同步一次（例如输入法组字未确认就点了别处）
        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard parent.text != textView.string else { return }
            parent.text = textView.string
        }
    }
}
