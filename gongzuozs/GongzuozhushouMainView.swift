import SwiftUI

struct GongzuozhushouMainView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaicar = false

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                ZStack {
                    pageBg.ignoresSafeArea()
                    // 背景烟花：主页面每次出现（启动/从任何系统返回）播放一次，约 5 秒后静止；
                    // 触发时机 = 主页面 onAppear（pop 回根视图必然触发，按钮/手势/派车通知都覆盖）；
                    // 粒子少 + 一次性动画，播完 GPU 无负载，几乎不额外耗电
                    FireworksView(size: geo.size)
                    ScrollView {
                        VStack(spacing: 20) {
                            // 选择系统 + 5 个系统 = 6 项内容
                            Text("选择系统")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(fg)
                                .padding(.bottom, 12)

                            // 派车模块（受控 pop：内部发 paicarBackToRoot 通知可退出）
                            NavigationLink(destination: PaicarModuleView(), isActive: $showPaicar) {
                                Text("寄递派车")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 40)
                                    .padding(.vertical, 16)
                                    .background(blue)
                                    .cornerRadius(25)
                            }

                            entryButton("外网查询", color: green) { WaiwangView() }
                            entryButton("内网查询", color: yellow) { NeiwangView() }
                            entryButton("网址助手", color: Color(red: 1.0, green: 0.43, blue: 0.25)) { WangzhizhushouView() }
                            entryButton("远程开机", color: purple) { YuanchengkaijiView() }

                        }
                        .frame(minHeight: geo.size.height)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                    }
                    .background(Color.clear)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .navigationViewStyle(.stack)
        // 登录失效弹窗改由 AuthDialog.show() 用 UIKit 顶层 UIAlertController 弹出（深层 push 也盖得住），
        // 不在此挂 SwiftUI alert。
        .onAppear {
            FullScreenBack.install()
            UIScrollView.appearance().backgroundColor = .clear
            let navBar = UINavigationBar.appearance()
            navBar.setBackgroundImage(UIImage(), for: .default)
            navBar.shadowImage = UIImage()
            navBar.isTranslucent = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarBackToRoot)) { _ in
            showPaicar = false
            // 派车返回主页面：pop 回根视图后主页面重新 onAppear，FireworksView 自动播放烟花
            //（无需在此手动触发）
            // 清理统一在 onChange(of: showPaicar) 处理（覆盖返回键/通知/系统手势 pop 等所有退出路径）
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigationPopDetected)) { _ in
            // FullScreenBack 左缘右滑确认 pop（手势路径）：UIKit pop 不会反向写回 SwiftUI 的
            // NavigationLink(isActive:) 状态 → 派车模块 pop 后主页面视图层级不变、不重新 appear，
            // 烟花 onAppear 不触发。这里强制同步 isActive=false，让 SwiftUI 状态一致 → 主页面
            // 重新 appear → FireworksView.onAppear 播放烟花。
            // 双保险：通知可能来自模块内页面（详情/登记/申请配置）的手势返回——那种情况栈里
            // 还有派车模块层，不应退模块。延时复查主导航栈，确认真的只剩根（=已回主界面）才退。
            if showPaicar {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if EdgeSwipeBack.isMainNavAtRoot() { showPaicar = false }
                }
            }
        }
        .onChange(of: showPaicar) { newValue in
            if !newValue {
                // 退出派车模块：不再清 token！保留本地会话供下次进入复用（对齐原版 uni-app），
                // 否则每次进出模块都要调 login 接口 → 触发服务端"频繁登录"风控
                // （登录成功但业务接口全 400/410 假 token 锁定，必须换账号才能恢复）。
                // 主界面期间在途请求 410 误弹"账号已在别处登入"的问题，已由
                // PaicarApi.parseBody 的 moduleActive 检查 + 注销 onAuthExpired 解决。
                PaicarProfileHolder.profile = nil
                PaicarApi.onAuthExpired = nil
                PaicarApi.silentAuthExpired = false
                PaicarApi.moduleActive = false
            }
        }
    }

    // 胶囊五色：蓝-绿-黄-橙-紫（与安卓 Flutter 首页一致）
    private var blue: Color { Color(red: 0.13, green: 0.59, blue: 0.95) }    // #2196F3
    private var green: Color { Color(red: 0.30, green: 0.69, blue: 0.31) }   // #4CAF50
    private var yellow: Color { Color(red: 0.98, green: 0.66, blue: 0.15) }  // #F9A825
    private var purple: Color { Color(red: 0.61, green: 0.15, blue: 0.69) }  // #9C27B0

    private func entryButton<D: View>(_ title: String, color: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination(), label: {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(color)
                .cornerRadius(25)
        })
    }
}

// MARK: - 主页面背景烟花（每次页面出现播放一次，约 5 秒后静止）
// 纯 SwiftUI 轻量动画（iOS 14 兼容）：100 个粒子一次性爆开淡出，播完 GPU 无负载。
// 彩色粒子在深色黑底 / 浅色白底上都清晰可见；不拦截任何点击（allowsHitTesting(false)）。

struct FireworkParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let duration: Double
    let delay: Double
}

struct FireworksView: View {
    let size: CGSize
    @State private var particles: [FireworkParticle] = []
    @State private var play = false

    private let colors: [Color] = [
        Color(red: 1.0, green: 0.84, blue: 0.0),   // 金
        Color(red: 1.0, green: 0.35, blue: 0.35),  // 红
        Color(red: 0.35, green: 0.70, blue: 1.0),  // 蓝
        Color(red: 0.35, green: 0.90, blue: 0.60), // 绿
        Color(red: 1.0, green: 1.0, blue: 1.0),    // 白
        Color(red: 0.85, green: 0.50, blue: 1.0),  // 紫
    ]

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .scaleEffect(play ? 1.0 : 0.3)
                    .opacity(play ? 0 : 1)
                    // position 是相对父容器的绝对坐标（左上角原点），保证爆点分布全屏
                    .position(x: play ? p.endX : p.startX, y: play ? p.endY : p.startY)
                    .animation(.easeOut(duration: p.duration).delay(p.delay), value: play)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .onAppear {
            // 主页面每次出现（启动 / 从系统返回——无论按钮、手势还是派车通知，
            // pop 回根视图都会重新 appear）都播放一次烟花；
            // 先置 false 再置 true，保证重复出现时动画一定重新播放
            makeParticles()
            play = false
            DispatchQueue.main.async { play = true }
        }
    }

    private func makeParticles() {
        var list: [FireworkParticle] = []
        let w = size.width
        let h = size.height
        // 5 个爆点分布全屏（四角 + 中心），粒子向四周爆开铺满整个背景
        let bursts: [CGPoint] = [
            CGPoint(x: w * 0.22, y: h * 0.25),
            CGPoint(x: w * 0.78, y: h * 0.25),
            CGPoint(x: w * 0.5, y: h * 0.5),
            CGPoint(x: w * 0.2, y: h * 0.78),
            CGPoint(x: w * 0.8, y: h * 0.78),
        ]
        for (bi, b) in bursts.enumerated() {
            let n = 20   // 每个爆点 20 个粒子，共 100 个，播完即静止
            for i in 0..<n {
                let angle = Double(i) / Double(n) * .pi * 2 + Double(bi) * 0.3
                let dist = CGFloat.random(in: 80...190)
                list.append(FireworkParticle(
                    color: colors.randomElement() ?? .white,
                    size: CGFloat.random(in: 6...11),
                    startX: b.x, startY: b.y,
                    endX: b.x + cos(angle) * dist,
                    endY: b.y + sin(angle) * dist * 0.85,
                    duration: Double.random(in: 2.8...4.2),   // 慢速爆开，总时长约 5 秒
                    delay: Double(bi) * 0.2 + Double.random(in: 0...0.6)
                ))
            }
        }
        particles = list
    }
}
