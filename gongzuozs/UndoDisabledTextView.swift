import SwiftUI
import UIKit

/// 禁用撤销（Undo）的多行文本输入组件，替代 SwiftUI TextEditor。
///
/// 为什么：iOS 16.x 上 SwiftUI TextEditor（内部 UITextView + UITextUndoManager）在 arm64e 设备
/// （如 iPhone 15 系列）存在崩溃 bug——用户按键盘撤销键 / 摇一摇撤销时，链路
/// `_UIUndoRedoTextOperation: -> _UITextUndoManager undo -> NSUndoManager undoNestedGroup
/// -> _NSUndoStack popAndInvoke -> objc_msgSend` 会访问已失效指针（EXC_BAD_ACCESS / SIGSEGV，
/// "possible pointer authentication failure"）。且该崩溃仅在撤销栈非空（输入框里打过字）时触发，
/// 表现为"间接性闪退"。
///
/// 解决办法：子类覆写 `undoManager` 返回 nil，把整个撤销栈关掉——键盘撤销键不再触发 undo，
/// 系统也不会再进入那条崩溃链路。输入、多行、滚动、深浅色自适应均保留，与 TextEditor 视觉一致。
struct UndoDisabledTextView: UIViewRepresentable {

    @Binding var text: String
    var font: UIFont = .systemFont(ofSize: 20)
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = NoUndoTextView()
        tv.font = font
        tv.textColor = .label                       // 浅色黑字 / 深色白字，自适应
        tv.backgroundColor = .systemBackground      // 浅色白底 / 深色黑底，与原 TextEditor 一致
        tv.isEditable = isEditable
        tv.isScrollEnabled = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)  // 替代原 .padding(8)
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEditable = isEditable
        uiView.font = font
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: UndoDisabledTextView
        init(_ parent: UndoDisabledTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

/// 覆写 undoManager 返回 nil，彻底关闭撤销栈，绕开 iOS 16 的 TextEditor 撤销崩溃 bug。
final class NoUndoTextView: UITextView {
    override var undoManager: UndoManager? { nil }
}
