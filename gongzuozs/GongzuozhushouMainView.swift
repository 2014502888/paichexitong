import SwiftUI

struct GongzuozhushouMainView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaicar = false
    // 烟花播放触发器：每次主页面出现/从子系统返回时 +1，FireworksView 监听变化播放一次
    @State private var fireworkTick = 0

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                ZStack {
                    pageBg.ignoresSafeArea()
                    // 背景烟花：每次主页面出现（启动/从子系统返回）播放一次，约 2 秒后静止；
                    // 粒子少 + 一次性动画，播完 GPU 无负载，几乎不额外耗电
                    FireworksView(size: geo.size, tick: fireworkTick)
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
            // 派车模块返回：播放一次背景烟花
            fireworkTick += 1
            // 清理统一在 onChange(of: showPaicar) 处理（覆盖返回键/通知/系统手势 pop 等所有退出路径）
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarReturnToMain)) { _ in
            // 外网/内网/网址助手/远程开机返回主页面：播放一次背景烟花
            fireworkTick += 1
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
        NavigationLink(destination: destination().onDisappear {
            // 从子系统返回主页面时发通知，主页面收到后播放一次背景烟花
            //（onDisappear 在 pop 返回时触发，兼容各 iOS 版本）
            NotificationCenter.default.post(name: .paicarReturnToMain, object: nil)
        }, label: {
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

// MARK: - 主页面背景烟花（每次页面出现播放一次，约 2 秒后静止）
// 纯 SwiftUI 轻量动画（iOS 14 兼容）：几十个粒子一次性爆开淡出，播完 GPU 无负载。
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
    let tick: Int   // 从子系统/派车返回主页面时 +1，监听变化触发一次播放
    @State private var particles: [FireworkParticle] = []
    @State private var play = false
    @State private var playedOnce = false   // 启动播放只做一次，避免与 tick 触发双播

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
                    .scaleEffect(play ? 1.1 : 0.3)
                    .opacity(play ? 0 : 1)
                    .offset(x: play ? p.endX : p.startX, y: play ? p.endY : p.startY)
                    .animation(.easeOut(duration: p.duration).delay(p.delay), value: play)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .onChange(of: tick) { _ in
            // 从子系统/派车返回主页面：重新生成随机烟花并播放一次；
            // 先置 false 再置 true，保证重复触发时动画一定重新播放
            makeParticles()
            play = false
            DispatchQueue.main.async { play = true }
        }
        .onAppear {
            // 启动/首次出现播放一次（带防重复标记，避免与后续 tick 触发双播）
            if !playedOnce {
                playedOnce = true
                makeParticles()
                play = false
                DispatchQueue.main.async { play = true }
            }
        }
    }

    private func makeParticles() {
        var list: [FireworkParticle] = []
        let w = size.width
        let h = size.height
        // 3 个爆点：分布在屏幕中下部横向错开（避开顶部"选择系统"标题区）
        let bursts: [CGPoint] = [
            CGPoint(x: w * 0.5, y: h * 0.42),
            CGPoint(x: w * 0.22, y: h * 0.55),
            CGPoint(x: w * 0.78, y: h * 0.55),
        ]
        for (bi, b) in bursts.enumerated() {
            let n = 18   // 每个爆点 18 个粒子，共 54 个，播完即静止
            for i in 0..<n {
                let angle = Double(i) / Double(n) * .pi * 2 + Double(bi) * 0.4
                let dist = CGFloat.random(in: 60...150)
                list.append(FireworkParticle(
                    color: colors.randomElement() ?? .white,
                    size: CGFloat.random(in: 5...9),
                    startX: b.x, startY: b.y,
                    endX: b.x + cos(angle) * dist,
                    endY: b.y + sin(angle) * dist * 0.8,   // 纵向略压缩，贴近真实烟花
                    duration: Double.random(in: 1.1...1.8),
                    delay: Double(bi) * 0.15 + Double.random(in: 0...0.25)
                ))
            }
        }
        particles = list
    }
}
