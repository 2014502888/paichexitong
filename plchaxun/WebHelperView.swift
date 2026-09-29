import SwiftUI
import UIKit
import WebKit

// MARK: - 站点配置（与安卓 WebConfig 一致）

struct WebSite: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let needWechatUA: Bool
    let desktopUA: Bool
}

enum WebHelperConfig {
    static let sites: [WebSite] = [
        WebSite(name: "吾爱破解", url: "https://www.52pojie.cn", needWechatUA: false, desktopUA: false),
        WebSite(name: "无忧启动", url: "https://wuyou.net", needWechatUA: false, desktopUA: false),
        WebSite(name: "远景论坛", url: "https://bbs.pcbeta.com", needWechatUA: false, desktopUA: false),
        WebSite(name: "纯净分享", url: "https://www.mefcl.com", needWechatUA: false, desktopUA: false),
        WebSite(name: "爱纯净", url: "https://www.aichunjing.com", needWechatUA: false, desktopUA: true),
    ]

    static let wechatUA = "Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230805.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/107.0.0.0 Mobile Safari/537.36 MicroMessenger/8.0.49.2560(0x28003135) WeChat/arm64 Weixin NetType/WIFI Language/zh_CN ABI/arm64"
    static let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    static func host(of url: String) -> String {
        URL(string: url)?.host ?? url
    }
}

// MARK: - 账号密码存储（对应安卓 SharedPreferences）

enum WebPasswordStore {
    static func get(_ host: String) -> (String, String)? {
        let d = UserDefaults.standard
        guard let a = d.string(forKey: "wh_account_" + host),
              let p = d.string(forKey: "wh_password_" + host) else { return nil }
        return (a, p)
    }
    static func save(_ host: String, _ account: String, _ password: String) {
        let d = UserDefaults.standard
        if account.isEmpty && password.isEmpty {
            d.removeObject(forKey: "wh_account_" + host)
            d.removeObject(forKey: "wh_password_" + host)
        } else {
            d.set(account, forKey: "wh_account_" + host)
            d.set(password, forKey: "wh_password_" + host)
        }
    }
}

// MARK: - 单个站点 WebView 封装

struct WebHelperWebView: UIViewRepresentable {
    let site: WebSite
    let index: Int
    let backTick: Int
    let isActive: Bool
    @Binding var progress: Double
    @Binding var title: String
    @Binding var canGoBack: Bool
    let onDownloadFinish: (String) -> Void
    let isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // 深色模式：文档一打开就注入反色CSS，避免白屏闪烁
        if isDark {
            let css: String
            if site.name == "爱纯净" {
                css = "html,body{background:#000!important;}"
            } else {
                css = "body{-webkit-filter:invert(1) hue-rotate(180deg)!important;}img,video,iframe,canvas{-webkit-filter:invert(1) hue-rotate(180deg)!important;}"
            }
            let js: String
            if site.name == "爱纯净" {
                js = "var m=document.createElement('meta');m.name='color-scheme';m.content='dark';document.documentElement.appendChild(m);document.documentElement.style.background='#000';var s=document.createElement('style');s.textContent='html,body{background:#000!important;}';(document.head||document.documentElement).appendChild(s);"
            } else {
                js = "var m=document.createElement('meta');m.name='color-scheme';m.content='dark';document.documentElement.appendChild(m);document.documentElement.style.background='#000';document.documentElement.style.filter='invert(1) hue-rotate(180deg)';document.documentElement.style.colorScheme='dark';"
            }
            let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // 关闭系统网页后退手势：由页面手势统一处理（左滑无上一页时可返回主界面）
        webView.allowsBackForwardNavigationGestures = false
        webView.tag = 1000 + index
        if site.needWechatUA {
            webView.customUserAgent = WebHelperConfig.wechatUA
        } else if site.desktopUA {
            webView.customUserAgent = WebHelperConfig.desktopUA
        }
        context.coordinator.webView = webView
        // 仅当前选中的站点立即加载；其余等到被点击切换时再加载（见 updateUIView ensureLoaded）
        if isActive { context.coordinator.ensureLoaded(webView) }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 切换到本站点时首次加载
        if isActive { context.coordinator.ensureLoaded(webView) }
        // 深浅色：背景跟随
        webView.isOpaque = false
        webView.backgroundColor = isDark ? UIColor.black : UIColor.white
        webView.scrollView.backgroundColor = isDark ? UIColor.black : UIColor.white
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = isDark ? .black : .white
        }
        // 网页返回上一页（顶栏按钮触发，仅当前选中站点响应）
        if backTick != context.coordinator.lastBackTick && isActive {
            context.coordinator.lastBackTick = backTick
            if webView.canGoBack { webView.goBack() }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var parent: WebHelperWebView
        weak var webView: WKWebView?
        var lastBackTick = 0
        /// 网页「上一页」快照：交互式后退时左边露出的预览内容
        var previousSnapshot: UIImage?
        /// 最近一次导航类型（WKNavigation 无 navigationType，从 navigationAction 记录）
        private var lastNavigationType: WKNavigationType = .other
        private var didLoad = false
        private var didAutoFill = false
        private var pendingDownloadFilename: String?

        init(_ parent: WebHelperWebView) {
            self.parent = parent
        }

        /// 每个站点只真正加载一次；非选中态不加载，点击切换时才加载（对应 makeUIView/updateUIView 调用）
        func ensureLoaded(_ webView: WKWebView) {
            guard !didLoad else { return }
            didLoad = true
            webView.load(URLRequest(url: URL(string: parent.site.url)!))
        }

        // MARK: 导航
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.progress = 0.1
            // 前进离开当前页时缓存当前页快照（后退预览用）；后退导航不覆盖
            if lastNavigationType != .backForward, webView.canGoBack {
                webView.takeSnapshot(with: nil) { [weak self] img, _ in
                    if let img = img { self?.previousSnapshot = img }
                }
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            parent.progress = 0.5
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.progress = 1.0
            parent.title = webView.title ?? parent.site.name
            parent.canGoBack = webView.canGoBack
            // 深色模式CSS已在atDocumentStart注入，这里不用重复
            // 自动填充账号密码（对应安卓 autofillCredentials）
            autoFillIfNeeded(webView)
            // 后退完成后若还有更早历史，缓存当前页供下次后退预览
            if lastNavigationType == .backForward, webView.canGoBack {
                webView.takeSnapshot(with: nil) { [weak self] img, _ in
                    if let img = img { self?.previousSnapshot = img }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled {
                parent.progress = 1.0
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.progress = 1.0
        }

        // 新窗口链接：在当前 WebView 内打开，不跳系统浏览器
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: 下载（对应安卓 setDownloadListener + 扩展名检测）
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 记录导航类型：用于区分前进/后退（判断后退预览快照是否需要更新）
            lastNavigationType = navigationAction.navigationType
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
            // 扩展名识别下载链接（对应安卓 DOWNLOAD_EXTS）
            if let url = navigationAction.request.url {
                let ext = (url.path as NSString).pathExtension.lowercased()
                let downloadExts = ["zip", "rar", "7z", "apk", "exe", "msi", "tar", "gz", "bz2", "xz",
                                    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                                    "iso", "img", "torrent", "mp4", "mkv", "flv", "avi"]
                if downloadExts.contains(ext) {
                    decisionHandler(.download)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            pendingDownloadFilename = suggestedFilename
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Downloads", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            completionHandler(dir.appendingPathComponent(suggestedFilename))
        }

        func downloadDidFinish(_ download: WKDownload) {
            DispatchQueue.main.async {
                self.parent.onDownloadFinish(self.pendingDownloadFilename ?? "文件")
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            DispatchQueue.main.async {
                self.parent.onDownloadFinish("下载失败：" + error.localizedDescription)
            }
        }

        // MARK: 自动填充（对应安卓 autofillCredentials，JS 注入账号密码）
        private func autoFillIfNeeded(_ webView: WKWebView) {
            guard !didAutoFill, let url = webView.url else { return }
            let host = WebHelperConfig.host(of: url.absoluteString)
            guard let cred = WebPasswordStore.get(host) else { return }
            didAutoFill = true
            let safeAccount = String(data: try! JSONSerialization.data(withJSONObject: [cred.0]), encoding: .utf8)!
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let safePassword = String(data: try! JSONSerialization.data(withJSONObject: [cred.1]), encoding: .utf8)!
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let script = """
            (function() {
                var u = document.querySelector('input[type="text"], input[type="email"], input[type="tel"], input[name*="user" i], input[name*="name" i], input[name*="account" i], input[name*="login" i], input[id*="user" i], input[id*="name" i]');
                var p = document.querySelector('input[type="password"], input[name*="pass" i], input[id*="pass" i]');
                if (u) { u.value = \(safeAccount); u.dispatchEvent(new Event('input', {bubbles:true})); u.dispatchEvent(new Event('change', {bubbles:true})); }
                if (p) { p.value = \(safePassword); p.dispatchEvent(new Event('input', {bubbles:true})); p.dispatchEvent(new Event('change', {bubbles:true})); }
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

// MARK: - 主界面（对应安卓 WebHelperMainActivity）

struct WebHelperView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    @State private var currentIndex = 0
    @State private var showAccount = false
    @State private var progress: Double = 0
    @State private var title = "网址助手"
    @State private var canGoBack = false
    @State private var backTick = 0
    @State private var downloadTip: String?
    @State private var showShare = false
    @State private var shareURL: URL?

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var bg: Color { isDark ? .black : .white }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var gray: Color { isDark ? Color(red: 0.69, green: 0.69, blue: 0.69) : Color(red: 0.62, green: 0.62, blue: 0.62) }

    var body: some View {
        VStack(spacing: 0) {
                topBar
                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.clear)
                        Rectangle()
                            .fill(Color(red: 0.1, green: 0.48, blue: 1.0))
                            .frame(width: geo.size.width * CGFloat(progress))
                    }
                }
                .frame(height: 3)
                .opacity(progress >= 1.0 || progress <= 0 ? 0 : 1)

                // 5 个站点 WebView 常驻切换
                ZStack {
                    ForEach(0..<WebHelperConfig.sites.count, id: \.self) { i in
                        WebHelperWebView(
                            site: WebHelperConfig.sites[i],
                            index: i,
                            backTick: backTick,
                            isActive: currentIndex == i,
                            progress: $progress,
                            title: $title,
                            canGoBack: $canGoBack,
                            onDownloadFinish: { tip in
                                downloadTip = tip
                                if tip.hasPrefix("下载失败") {
                                    showToast(tip)
                                } else if let fileURL = downloadsDir()?.appendingPathComponent(tip), FileManager.default.fileExists(atPath: fileURL.path) {
                                    shareURL = fileURL
                                    showShare = true
                                } else {
                                    showToast(tip)
                                }
                            },
                            isDark: isDark
                        )
                        .opacity(i == currentIndex ? 1 : 0)
                        .allowsHitTesting(i == currentIndex)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomTabs
        }
        .background(pageBg)
        .clipped()
        .navigationBarHidden(true)
        // 右缘左滑：直接网页后退（与左上角返回按钮效果一致，不做跟手预览）
        .highPriorityGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let w = UIScreen.main.bounds.width
                    let sx = value.startLocation.x
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dy) < 80, sx > w - 45, dx < -60,
                          let wv = webView(at: currentIndex), wv.canGoBack else { return }
                    wv.goBack()
                }
        )
        .sheet(isPresented: $showAccount) {
            WebHelperAccountView()
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .onChange(of: currentIndex) { newIndex in
            title = WebHelperConfig.sites[newIndex].name
        }
        .onChange(of: showShare) { showing in
            if showing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showShare = false
                    shareURL = nil
                }
            }
        }
    }

    /// 顶部栏：返回键(←) + 居中标题 + 刷新(↻) + 更多(⋮)；浅色黑/深色白
    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            // 网页返回上一页（浅色黑 / 深色白）
            Button {
                if canGoBack { backTick += 1 }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(fg)
                    .frame(width: 40, height: 44)
            }
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0.35)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button {
                reload()
            } label: {
                Text("↻")
                    .font(.system(size: 20))
                    .frame(width: 40, height: 44)
            }
            Button {
                showAccount = true
            } label: {
                Text("⋮")
                    .font(.system(size: 22))
                    .frame(width: 40, height: 44)
            }
        }
        .foregroundColor(fg)
        .background(bg)
    }

    /// 底部 5 个 tab：字号 13 固定；选中四周实线边框（浅色黑线/深色白线），未选中灰字
    private var bottomTabs: some View {
        HStack(spacing: 6) {
            ForEach(0..<WebHelperConfig.sites.count, id: \.self) { i in
                Button {
                    currentIndex = i
                } label: {
                    Text(WebHelperConfig.sites[i].name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(i == currentIndex ? fg : Color.clear, lineWidth: 1)
                        )
                        .foregroundColor(i == currentIndex ? fg : gray)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(bg)
    }

    private func reload() {
        guard let webView = webView(at: currentIndex) else { return }
        webView.reload()
    }

    private func webView(at index: Int) -> WKWebView? {
        // 通过 UIKit 层级按 tag 查找当前 tab 的 WKWebView（tag = 1000 + index）
        guard let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first else { return nil }
        return findWebView(in: host.rootViewController?.view, tag: 1000 + index)
    }

    private func findWebView(in view: UIView?, tag: Int) -> WKWebView? {
        guard let view = view else { return nil }
        if let wv = view as? WKWebView, wv.tag == tag { return wv }
        for sub in view.subviews {
            if let found = findWebView(in: sub, tag: tag) { return found }
        }
        return nil
    }

    private func downloadsDir() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    private func showToast(_ msg: String) {
        // 简单提示：借用下载提示展示
        downloadTip = msg
    }
}

// MARK: - 账号管理（对应安卓 WebHelperAccountActivity）

struct WebHelperAccountView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    @State private var accounts: [String: String] = [:]
    @State private var passwords: [String: String] = [:]
    @State private var toast: String?

    private var fg: Color { colorScheme == .dark ? .white : .black }
    private var pageBg: Color { colorScheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var fieldBg: Color { colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.95) }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部：返回键(←) + 居中标题"账号密码管理"（扣除占位符）
                HStack(spacing: 0) {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    Text("账号密码管理")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 40, height: 44)
                }
                .foregroundColor(fg)
                .background(pageBg)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(WebHelperConfig.sites.enumerated()), id: \.element.id) { index, site in
                            let host = WebHelperConfig.host(of: site.url)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(site.name)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(fg)
                                TextField("账号", text: bindingAccount(host))
                                    .font(.system(size: 15))
                                    .foregroundColor(fg)
                                    .padding(.horizontal, 12)
                                    .frame(height: 42)
                                    .background(fieldBg)
                                    .cornerRadius(8)
                                SecureField("密码", text: bindingPassword(host))
                                    .font(.system(size: 15))
                                    .foregroundColor(fg)
                                    .padding(.horizontal, 12)
                                    .frame(height: 42)
                                    .background(fieldBg)
                                    .cornerRadius(8)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)

                            if index < WebHelperConfig.sites.count - 1 {
                                Divider().background(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
                            }
                        }
                    }
                }

                // 保存按钮：居中、非胶囊（对应安卓 btn_save）
                Button {
                    save()
                } label: {
                    Text("保存")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(6)
                }
                .padding(.vertical, 14)
            }
            .background(pageBg)
            .navigationBarHidden(true)
            .onAppear {
                for site in WebHelperConfig.sites {
                    let host = WebHelperConfig.host(of: site.url)
                    if let cred = WebPasswordStore.get(host) {
                        accounts[host] = cred.0
                        passwords[host] = cred.1
                    } else {
                        accounts[host] = ""
                        passwords[host] = ""
                    }
                }
            }
            .alert(item: Binding(
                get: { toast.map { ToastItem(text: $0) } },
                set: { toast = $0?.text }
            )) { item in
                Alert(title: Text(item.text))
            }
        }
        .navigationViewStyle(.stack)
    }

    private func bindingAccount(_ host: String) -> Binding<String> {
        Binding(get: { accounts[host] ?? "" }, set: { accounts[host] = $0 })
    }
    private func bindingPassword(_ host: String) -> Binding<String> {
        Binding(get: { passwords[host] ?? "" }, set: { passwords[host] = $0 })
    }

    private func save() {
        var saved = 0
        for site in WebHelperConfig.sites {
            let host = WebHelperConfig.host(of: site.url)
            let account = (accounts[host] ?? "").trimmingCharacters(in: .whitespaces)
            let password = passwords[host] ?? ""
            if !account.isEmpty || !password.isEmpty {
                WebPasswordStore.save(host, account, password)
                saved += 1
            } else {
                WebPasswordStore.save(host, "", "")
            }
        }
        toast = "已保存 \(saved) 个站点的账号密码"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

struct ToastItem: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - 系统分享（下载完成后选择保存位置）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
