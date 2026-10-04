import SwiftUI
import UIKit

// MARK: - 派车模块入口（对应 PaicarLoginActivity + PaicarHomeActivity 路由）

enum PaicarNavTarget: Equatable {
    case none
    case newApply
    case quickEdit
    case editApply
    case arrange
    case finish
}

struct PaicarModuleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var navTarget = PaicarNavTarget.none
    @State private var navPostId = ""
    @State private var navOrderId = ""
    @State private var navMode = ""
    @State private var loggedIn = false
    @State private var autoLogging = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if loggedIn {
                PaicarHomeView()
            } else if autoLogging {
                // 对齐安卓自动登录转圈页：不再白屏（Color.clear），登录中显示转圈+文字，
                // 避免 login 慢/失败时用户看到一片空白误以为"进不去/卡死"。
                VStack(spacing: 14) {
                    ProgressView().scaleEffect(1.4)
                    Text("正在登录…")
                        .font(.system(size: 15))
                        .foregroundColor(isDark ? .white : .black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white)
            } else {
                PaicarLoginView()
            }
        }
        .background(
            Group {
                NavigationLink(destination: PaicarApplyEditView(), isActive: isActive(.newApply)) { EmptyView() }
                NavigationLink(destination: PaicarQuickEditView(), isActive: isActive(.quickEdit)) { EmptyView() }
                NavigationLink(destination: PaicarApplyEditView(postId: navPostId), isActive: isActive(.editApply)) { EmptyView() }
                NavigationLink(destination: PaicarArrangeView(orderId: navOrderId), isActive: isActive(.arrange)) { EmptyView() }
                NavigationLink(destination: PaicarFinishView(orderId: navOrderId, mode: navMode), isActive: isActive(.finish)) { EmptyView() }
            }
        )
        .onAppear {
            PaicarApi.moduleActive = true
            // 完全对齐原版 uni-app 登入逻辑：不自动登入！
            // 原版 index 页：有 login_token → 复用 token 拉 profile → 成功进主页 / 失败回登录页；
            // 无 token → 登录页手动登录。登录接口只在用户手动点"登录"时调用，
            // 彻底避免"每次进模块自动调 login → 服务端频繁登录风控 → 假 token 锁定"。
            PaicarSession.load()
            if PaicarApi.justLoggedOut {
                // 用户主动选择不重登：停在登录页等手动点
                loggedIn = false
                autoLogging = false
            } else if PaicarSession.loggedIn {
                // 有 token：复用验证（profile），成功直接进系统，0 次 login 调用
                loggedIn = false
                autoLogging = true
                enterWithToken()
            } else {
                // 无 token：登录页手动登录（即使本地有账密也不自动登入，对齐原版）
                loggedIn = false
                autoLogging = false
            }
            PaicarApi.onAuthExpired = {
                DispatchQueue.main.async {
                    // 对齐安卓 PaicarApp 全局弹：从最顶层 UIViewController 直接弹 UIAlertController，
                    // 不依赖 SwiftUI 根 alert 在深层 push 后能否盖上来（详情->拍照结单这类深层页面
                    // 根 alert 经常不弹），第几层都盖得住。
                    AuthDialog.shared.show()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarLoginOK)) { _ in
            loggedIn = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarForceLogin)) { _ in
            // 对齐安卓取消后清栈回登录页：退出登录态的同时，把所有 push 出去的页面
            // (详情/拍照结单/安排/快捷编辑等) 全部弹回，否则它们还压在登录页上面。
            loggedIn = false
            autoLogging = false
            navTarget = .none
            navPostId = ""
            navOrderId = ""
            navMode = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarReloadAfterLogin)) { _ in
            // 重新登录成功：对齐安卓清栈重启主页。把所有 push 出去的空白详情/拍照页弹回，
            // 列表页自己会监听这个通知重新拉数据。
            loggedIn = true
            navTarget = .none
            navPostId = ""
            navOrderId = ""
            navMode = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarOpenNewApply)) { _ in
            navTarget = .newApply
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarOpenQuickEdit)) { _ in
            navTarget = .quickEdit
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarOpenEditApply)) { note in
            navPostId = (note.userInfo?["orderId"] as? String) ?? ""
            navTarget = .editApply
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarOpenArrange)) { note in
            navOrderId = (note.userInfo?["orderId"] as? String) ?? ""
            navTarget = .arrange
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarOpenFinish)) { note in
            navOrderId = (note.userInfo?["orderId"] as? String) ?? ""
            navMode = (note.userInfo?["mode"] as? String) ?? ""
            navTarget = .finish
        }
        // 登录后右缘左滑由 PaicarHomeView 自己处理(切回全部列表),不在此dismiss;
        // 未登录时(登录页)右缘左滑退出派车模块
        .modifier(PaicarModuleBackModifier(loggedIn: loggedIn))
    }

    /// 复用本地 token 进系统（对齐原版 uni-app 行为）：
    /// 直接用现有 token 拉 profile，成功即进主页（0 次 login 调用）；
    /// 鉴权失败（400/410 token 失效）→ 清掉失效 token 回登录页手动登录（不自动重登）；
    /// 网络等非鉴权错误 → 保留 token 回登录页并提示，下次进模块自动重试。
    private func enterWithToken() {
        Task {
            do {
                _ = try await PaicarProfileHolder.load()
                // 验证期间用户可能已退出派车模块
                guard PaicarApi.moduleActive else { return }
                PaicarApi.lastAuthError = ""
                // profile 成功时 parseBody 已置 hasLoadedOnce=true：会话有效，
                // 后续真被顶号(410)才会弹顶号框
                autoLogging = false
                loggedIn = true
            } catch {
                guard PaicarApi.moduleActive else { return }
                autoLogging = false
                if let e = error as? PaicarError, case .authExpired = e {
                    // token 真失效（被顶/过期）：对齐原版清掉失效会话回登录页，
                    // 不清账密，登录页预填后手动点登录
                    PaicarApi.lastAuthError = "登录会话已过期，请重新登录"
                    PaicarSession.clear()
                } else {
                    // 网络等非鉴权错误：保留 token，提示后回登录页，下次进模块自动重试
                    PaicarApi.lastAuthError = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
                }
                loggedIn = false
            }
        }
    }

    private func isActive(_ t: PaicarNavTarget) -> Binding<Bool> {
        Binding(
            get: { navTarget == t },
            set: { if !$0 { navTarget = .none } }
        )
    }
}

extension Notification.Name {
    static let paicarLoginOK = Notification.Name("paicarLoginOK")
}

// MARK: - 登录页（对应 PaicarLoginActivity）

struct PaicarLoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var userNo = ""
    @State private var pwd = ""
    @State private var loading = false
    @State private var toast: String?

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var inputBg: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.17) : .white }
    private var inputBorder: Color { isDark ? Color(white: 0.33) : Color(white: 0.8) }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：返回键 + 居中"寄递派车"（扣除占位）
            HStack(spacing: 0) {
                Button {
                    // 登录页不是独立 push 的页面，dismiss 无效；直接退出派车模块（与未登录右缘左滑一致）
                    NotificationCenter.default.post(name: .paicarBackToRoot, object: nil)
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text("寄递派车")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 0) {
                    Text("🚚").font(.system(size: 72)).padding(.top, 40)
                    Text("寄递车辆调度系统")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(fg)
                        .padding(.top, 8)
                        .padding(.bottom, 32)

                    TextField("登录账号", text: $userNo)
                        .keyboardType(.numberPad)
                        .font(.system(size: 15))
                        .foregroundColor(fg)
                        .accentColor(fg)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(inputBg)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(inputBorder, lineWidth: 1))
                        .padding(.horizontal, 24)

                    SecureField("密码", text: $pwd)
                        .font(.system(size: 15))
                        .foregroundColor(fg)
                        .accentColor(fg)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(inputBg)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(inputBorder, lineWidth: 1))
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    if PaicarSession.savedUserNo.isEmpty == false && PaicarSession.savedUserPwd.isEmpty == false {
                        Text("✓ 已记住账号和密码，直接点登录")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.3, green: 0.68, blue: 0.31))
                            .padding(.top, 12)
                    }

                    Button {
                        doLogin()
                    } label: {
                        Text(loading ? "登录中…" : "登录")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(blue)
                            .cornerRadius(10)
                    }
                    .disabled(loading)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                    if loading {
                        ProgressView().padding(.top, 12)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(pageBg)
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .overlay(
            Group {
                if let msg = toast {
                    PaicarToast(text: msg, dark: isDark)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.toast = nil
                            }
                        }
                }
            }
        )
        .onAppear {
            let saved = PaicarSession.savedUserNo
            if !saved.isEmpty { userNo = saved }
            let savedPwd = PaicarSession.savedUserPwd
            if !savedPwd.isEmpty { pwd = savedPwd }
            // 自动/重新登录失败的原因在这里显示一次（读完即清），
            // 用户能明确看到"为什么没自动登进去"，而不是白屏/静默。
            if !PaicarApi.lastAuthError.isEmpty {
                toast = PaicarApi.lastAuthError
                PaicarApi.lastAuthError = ""
            }
        }
    }

    private func doLogin() {
        if loading { return }
        let u = userNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.count < 6 { toast = "请填写登录账号"; return }
        if pwd.count < 6 { toast = "密码最短为 6 个字符"; return }
        loading = true
        Task {
            do {
                let info = try await PaicarApi.login(userNo: u, plainPassword: pwd)
                PaicarSession.save(token: info.token, userId: info.userId, userNo: u, userPwd: pwd)
                PaicarProfileHolder.profile = nil
                loading = false
                PaicarApi.justLoggedOut = false
                PaicarApi.silentAuthExpired = false
                NotificationCenter.default.post(name: .paicarLoginOK, object: nil)
            } catch {
                loading = false
                toast = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - 主界面 3 Tab（对应 PaicarHomeActivity）

struct PaicarHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab = 0
    // 右缘左滑：已在 HomeView tab 上时切回「全部」列表；
    // 有 push 子页面时由系统全屏手势(FullScreenBack)自动 pop，不在此处理
    private var rightEdgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let w = UIScreen.main.bounds.width
                let sx = value.startLocation.x
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dy) < 80, sx > w - 45, dx < -60 else { return }
                if tab != 0 { tab = 0 }
                NotificationCenter.default.post(name: .paicarBackToAllList, object: nil)
            }
    }

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：返回键 + 居中标题（随 tab 变）+ 右侧 + 按钮（仅派车单tab显示）
            HStack(spacing: 0) {
                Button {
                    // 返回根（退出派车模块）
                    NotificationCenter.default.post(name: .paicarBackToRoot, object: nil)
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text(tab == 0 ? "派车单" : (tab == 1 ? "看板" : "我的"))
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                // 右上角 + 按钮：仅派车单tab显示，弹出派车申请/一键申请/一键撤回/申请配置
                if tab == 0 {
                    Button {
                        NotificationCenter.default.post(name: .paicarShowMenu, object: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                } else {
                    Color.clear.frame(width: 40, height: 44)
                }
            }
            .foregroundColor(fg)
            .background(pageBg)

            Group {
                if tab == 0 {
                    PaicarDispatchListView()
                } else if tab == 1 {
                    PaicarDashboardView()
                } else {
                    PaicarMineView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部 3 tab（对应 BottomNavigationView）
            HStack(spacing: 0) {
                tabButton("派车单", icon: "shippingbox", index: 0)
                tabButton("看板", icon: "chart.bar.fill", index: 1)
                tabButton("我的", icon: "person.fill", index: 2)
            }
            .frame(height: 52)
            .background(pageBg)
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .highPriorityGesture(rightEdgeBackGesture)
    }

    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button {
            tab = index
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(tab == index ? Color(red: 0.08, green: 0.28, blue: 0.75) : (isDark ? Color(white: 0.6) : Color(white: 0.45)))
            .frame(maxWidth: .infinity)
        }
    }
}

extension Notification.Name {
    static let paicarBackToRoot = Notification.Name("paicarBackToRoot")
    static let paicarBackToAllList = Notification.Name("paicarBackToAllList")
    static let paicarShowMenu = Notification.Name("paicarShowMenu")
    static let paicarOpenNewApply = Notification.Name("paicarOpenNewApply")
    static let paicarOpenQuickEdit = Notification.Name("paicarOpenQuickEdit")
    static let paicarOpenEditApply = Notification.Name("paicarOpenEditApply")
    static let paicarOpenArrange = Notification.Name("paicarOpenArrange")
    static let paicarOpenFinish = Notification.Name("paicarOpenFinish")
}

// MARK: - 通用 Toast（无图标）

struct PaicarToast: View {
    let text: String
    let dark: Bool
    var isError: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(isError ? .red : (dark ? .white : .black))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(dark ? Color(red: 0.086, green: 0.086, blue: 0.086) : Color(red: 0.95, green: 0.95, blue: 0.95))
            .cornerRadius(10)
    }
}

// MARK: - 被顶号弹窗（对齐安卓 PaicarApp.showAuthExpiredDialog）

/// 全局登录失效弹窗（对齐安卓 PaicarApp.showAuthExpiredDialog）
/// 从最顶层 UIViewController 弹 UIAlertController，不依赖 SwiftUI 根 alert 的层级呈现。
final class AuthDialog {
    static let shared = AuthDialog()
    private init() {}
    var isShowing = false

    func show() {
        if isShowing { return }
        guard let scene = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        guard let root = keyWindow?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }

        let alert = UIAlertController(title: "账号已在别处登入", message: "是否重新登录？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            self.isShowing = false
            // 用户主动选择不重登：置 justLoggedOut，防止 alert 关闭后 SwiftUI 触发
            // 模块 onAppear 重跑又强制 autoLogin → autoLogging 空白页死循环
            PaicarApi.justLoggedOut = true
            PaicarApi.lastAuthError = ""
            PaicarSession.clear()
            PaicarProfileHolder.profile = nil
            NotificationCenter.default.post(name: .paicarForceLogin, object: nil)
        })
        alert.addAction(UIAlertAction(title: "重新登录", style: .default) { _ in
            self.isShowing = false
            let u = PaicarSession.savedUserNo, p = PaicarSession.savedUserPwd
            guard !u.isEmpty, !p.isEmpty else {
                PaicarSession.clear()
                NotificationCenter.default.post(name: .paicarForceLogin, object: nil)
                return
            }
            Task {
                do {
                    let info = try await PaicarApi.login(userNo: u, plainPassword: p)
                    // 登录在途期间若已退出派车模块，不再写回 token，避免主界面残留弹框
                    guard PaicarApi.moduleActive else { return }
                    PaicarSession.save(token: info.token, userId: info.userId, userNo: u, userPwd: p)
                    PaicarProfileHolder.profile = nil
                    // 重登成功：复位 justLoggedOut（之前点过取消再重登也能进系统，
                    // 不会退出重进后永远停在登录页）。hasLoadedOnce 由 login 内部自检处理。
                    PaicarApi.justLoggedOut = false
                    PaicarApi.lastAuthError = ""
                    NotificationCenter.default.post(name: .paicarReloadAfterLogin, object: nil)
                } catch {
                    // 服务端拒绝重登（会话被顶/冲突）：记录原因让登录页显示，
                    // 并置 justLoggedOut 停在登录页让用户手动处理（换账号/稍后重试），
                    // 不再自动重登死循环
                    PaicarApi.lastAuthError = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
                    PaicarApi.justLoggedOut = true
                    PaicarSession.clear()
                    NotificationCenter.default.post(name: .paicarForceLogin, object: nil)
                }
            }
        })
        isShowing = true
        top.present(alert, animated: true)
    }
}

extension Notification.Name {
    static let paicarForceLogin = Notification.Name("paicarForceLogin")
    static let paicarReloadAfterLogin = Notification.Name("paicarReloadAfterLogin")
}

// 登录后不挂右缘左滑dismiss手势(由PaicarHomeView自己处理);未登录时才挂
struct PaicarModuleBackModifier: ViewModifier {
    let loggedIn: Bool
    func body(content: Content) -> some View {
        if loggedIn {
            content
        } else {
            content.highPriorityGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let w = UIScreen.main.bounds.width
                        let sx = value.startLocation.x
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dy) < 80, sx > w - 45, dx < -60 else { return }
                        // 未登录时右缘左滑:退出派车模块
                        NotificationCenter.default.post(name: .paicarBackToRoot, object: nil)
                    }
            )
        }
    }
}
