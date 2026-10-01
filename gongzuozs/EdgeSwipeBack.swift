import SwiftUI
import UIKit

// MARK: - 边缘滑动返回
// 左缘右滑跟手pop：由 FullScreenBack 统一驱动系统原生转场（见下方）
// 右缘左滑返回：由 InteractiveSwipeBackModifier 实现（屏幕右边沿45px内、左滑>60pt触发）
enum EdgeSwipeBack {
    /// 禁用系统左缘 pop 手势：带导航栏页面（内网/外网）的系统返回手势会吞掉左边缘触摸
    /// 但又不触发（navigationBarBackButtonHidden 下），导致页面自己的手势也收不到。
    static func disableSystemPop() {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first else { return }
            findNav(window.rootViewController)?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    /// 截取导航栈「上一页」的全屏快照（交互式返回时左边露出的内容）。
    /// 当前页是 NavigationLink push 的，栈倒数第二个 VC 就是返回目标页。
    static func snapshotOfPreviousPage() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first,
            let nav = findNav(window.rootViewController) else { return nil }
        let vcs = nav.viewControllers
        guard vcs.count >= 2, let prev = vcs[vcs.count - 2].view else { return nil }
        let size = prev.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            prev.drawHierarchy(in: prev.bounds, afterScreenUpdates: false)
        }
    }

    static func findNav(_ vc: UIViewController?) -> UINavigationController? {
        if let n = vc as? UINavigationController { return n }
        if let tab = vc as? UITabBarController {
            for c in tab.viewControllers ?? [] {
                if let n = findNav(c) { return n }
            }
        }
        for c in vc?.children ?? [] {
            if let n = findNav(c) { return n }
        }
        return nil
    }
}

// MARK: - 交互式边缘返回 modifier

struct InteractiveSwipeBackModifier: ViewModifier {
    let onSwipe: () -> Void
    // 全屏返回已由 FullScreenBack 统一驱动系统原生转场(左缘右滑跟手pop)
    // 这里补一个右缘左滑手势：屏幕右边沿45px内、左滑>60pt，触发返回(与系统pop等效)
    func body(content: Content) -> some View {
        content.highPriorityGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let w = UIScreen.main.bounds.width
                    let sx = value.startLocation.x
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dy) < 80, sx > w - 45, dx < -60 else { return }
                    onSwipe()
                }
        )
    }
}

// MARK: - 全屏边缘返回（驱动系统原生转场，效果与系统一致：跟手、露真上一页、过半才返回）

final class FullScreenPanGesture: UIPanGestureRecognizer {}

// 返回手势过半时的轻震动（与参考 dylib 一致，弱=light）
final class FBSHaptic: NSObject {
    static let shared = FBSHaptic()
    private var generator: UIImpactFeedbackGenerator?
    @objc func track(_ g: UIPanGestureRecognizer) {
        let w = UIScreen.main.bounds.width
        switch g.state {
        case .began:
            generator = UIImpactFeedbackGenerator(style: .heavy)
            generator?.prepare()
        case .changed:
            // 只记录拖过多少，不在 changed 时震
            break
        case .ended:
            // 手指离开屏幕时，判断是否真的会返回：位移过半 或 快速右滑
            let tx = g.translation(in: g.view).x
            let vx = g.velocity(in: g.view).x
            if tx > w * 0.35 || vx > 300 {
                generator?.impactOccurred(intensity: 1.0)
            }
            generator = nil
        case .cancelled, .failed:
            generator = nil
        default: break
        }
    }
}

final class FullScreenBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = FullScreenBackDelegate()
    private func nav(of view: UIView?) -> UINavigationController? {
        var r: UIResponder? = view?.next
        while let cur = r {
            if let n = cur as? UINavigationController { return n }
            if let vc = cur as? UIViewController, let n = vc.navigationController { return n }
            r = cur.next
        }
        return nil
    }
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer,
              let nav = nav(of: g.view) else { return false }
        // 页面自行拦截时（如网址助手还有网页历史，需先网页后退）不触发系统pop
        if FullScreenBack.blockPop { return false }
        // 只有导航栈多于一页才允许返回
        guard nav.viewControllers.count > 1 else { return false }
        let t = pan.translation(in: g.view)
        // 只响应向右（返回方向）的横向拖动；纵向滚动不抢
        guard t.x > 2, abs(t.x) > abs(t.y) else { return false }
        return true
    }
}

enum FullScreenBack {
    /// 页面内有需要优先处理的返回（网址助手网页历史）时置 true，拦截系统全屏pop
    static var blockPop = false
    private static func install(on nav: UINavigationController) {
        if nav.view.gestureRecognizers?.contains(where: { $0 is FullScreenPanGesture }) == true { return }
        // KVC 拿到系统边缘返回手势的 target（_UINavigationInteractiveTransition），
        // 全屏手势直接驱动它的私有 handleNavigationTransition:，复用系统原生 pop 动画
        guard let sys = nav.interactivePopGestureRecognizer,
              let targets = sys.value(forKey: "_targets") as? [NSObject],
              let target = targets.first?.value(forKey: "_target") else { return }
        let sel = NSSelectorFromString("handleNavigationTransition:")
        let g = FullScreenPanGesture(target: target, action: sel)
        g.delegate = FullScreenBackDelegate.shared
        g.addTarget(FBSHaptic.shared, action: #selector(FBSHaptic.track(_:)))
        nav.view.addGestureRecognizer(g)

    }
    private static func walk(_ vc: UIViewController?) {
        guard let vc = vc else { return }
        if let n = vc as? UINavigationController { install(on: n) }
        for c in vc.children { walk(c) }
    }
    /// 遍历所有窗口的所有导航控制器，全部装上全屏手势（与 dylib 插件行为一致）
    static func install() {
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let ws = scene as? UIWindowScene else { continue }
                for w in ws.windows { walk(w.rootViewController) }
            }
        }
    }
}

extension View {
    func interactiveEdgeSwipeBack(_ onSwipe: @escaping () -> Void) -> some View {
        modifier(InteractiveSwipeBackModifier(onSwipe: onSwipe))
    }
}

