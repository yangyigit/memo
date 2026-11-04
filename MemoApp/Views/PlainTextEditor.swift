import SwiftUI
import AppKit

/// 纸感文本编辑器：去掉系统白底与滚动条轨道，行距可调。
/// 系统 TextEditor 在 macOS 上会残留一条白色滚动条轨道，这里用 NSTextView 接管。
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 14
    var lineSpacing: CGFloat = 6

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
        textView.insertionPointColor = NSColor(Theme.accent)

        configureStyle(textView)
        textView.string = text
        applyParagraphStyle(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        configureStyle(textView)
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            applyParagraphStyle(textView)
            let limit = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, limit), length: 0))
        }
    }

    private func configureStyle(_ textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        textView.font = font
        textView.textColor = NSColor(Theme.ink)
    }

    private func applyParagraphStyle(_ textView: NSTextView) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(Theme.ink),
            .paragraphStyle: style
        ]
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = style
        let length = (textView.string as NSString).length
        if length > 0 {
            textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
