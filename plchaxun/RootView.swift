import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaicar = false

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 20) {
                        // 选择系统 + 5 个系统 = 6 项内容
                        Text("选择系统")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(fg)
                            .padding(.bottom, 12)

                        // 派车模块（受控 pop：内部发 paicarBackToRoot 通知可退出）
                        NavigationLink(destination: PaicarModuleView().paicarAuthGuard(), isActive: $showPaicar) {
                            Text("寄递派车")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 16)
                                .background(blue)
                                .cornerRadius(25)
                        }

                        entryButton("外网查询", color: green) { ExternalView() }
                        entryButton("内网查询", color: yellow) { InternalView() }
                        entryButton("网址助手", color: Color(red: 1.0, green: 0.43, blue: 0.25)) { WebHelperView() }
                        entryButton("远程开机", color: purple) { RemoteBootView() }

                    }
                    .frame(minHeight: geo.size.height)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
                .background(pageBg)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
            }
            .background(pageBg.ignoresSafeArea())
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
        }
    }

    // 胶囊五色：蓝-绿-黄-橙-紫（与安卓 Flutter 首页一致）
    private var blue: Color { Color(red: 0.13, green: 0.59, blue: 0.95) }    // #2196F3
    private var green: Color { Color(red: 0.30, green: 0.69, blue: 0.31) }   // #4CAF50
    private var yellow: Color { Color(red: 0.98, green: 0.66, blue: 0.15) }  // #F9A825
    private var orange: Color { Color(red: 1.0, green: 0.60, blue: 0.0) }    // #FF9800
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
