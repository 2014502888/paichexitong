import SwiftUI
import UIKit

// MARK: - 远程开机（对应安卓 RemoteBootActivity）

struct RemoteBootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    // 登录态
    @State private var account = ""
    @State private var password = ""
    @State private var remember = false
    @State private var cookie: String = UserDefaults.standard.string(forKey: "rb_cookie") ?? ""
    @State private var devices: [(name: String, id: String)] = []
    @State private var isLoading = false
    @State private var toastMsg: String?

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var sub: Color { isDark ? Color(white: 0.78) : Color(white: 0.22) }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var cardBg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.95) }
    private var statusColor: Color {
        if isLoggedIn { return isDark ? Color(red: 0.5, green: 0.86, blue: 0.55) : Color(red: 0.18, green: 0.49, blue: 0.2) }
        return isDark ? Color(red: 1.0, green: 0.55, blue: 0.55) : Color(red: 0.83, green: 0.18, blue: 0.18)
    }

    private var isLoggedIn: Bool { !cookie.isEmpty }

    private let loginURL = "https://songguoyun.topwd.top/Esp_Share_Manage.php?code="
    private let cmdURL = "https://songguoyun.topwd.top/mqtt_subscribe_app.php"
    private let actions: [(name: String, code: String, icon: String)] = [
        ("开机", "1", "power"),
        ("关机", "0", "poweroff"),
        ("强制关机", "14", "restart"),
        ("强制重启", "2", "restart"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：返回键 + 居中标题（扣除占位）；右侧无开关，补对称占位
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
                Text("远程开机")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 12) {
                    // 账号 / 密码：屏幕 1/3 宽居中（与登录行左右占位列对齐）
                    accountField
                    passwordField
                    loginRow
                    deviceTitle
                    deviceList
                    tipText
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            let d = UserDefaults.standard
            remember = d.bool(forKey: "rb_remember")
            if remember {
                account = d.string(forKey: "rb_account") ?? ""
                password = d.string(forKey: "rb_password") ?? ""
            }
            if isLoggedIn {
                devices = loadDevices()
            }
        }
        .overlay(
            Group {
                if let msg = toastMsg {
                    ToastLabel(text: msg, dark: isDark)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.toastMsg = nil
                            }
                        }
                }
            }
        )
    }

    // MARK: 输入框：宽度 = 屏幕 1/3，居中
    private var accountField: some View {
        inputField(hint: "账号", text: $account)
    }
    private var passwordField: some View {
        inputField(hint: "密码", text: $password, secure: true)
    }

    private func inputField(hint: String, text: Binding<String>, secure: Bool = false) -> some View {
        let w = (UIScreen.main.bounds.width / 3.0)
        return Group {
            if secure {
                SecureField(hint, text: text)
            } else {
                TextField(hint, text: text)
            }
        }
        .font(.system(size: 15))
        .foregroundColor(fg)
        .accentColor(fg)
        .padding(.horizontal, 12)
        .frame(width: w, height: 42)
        .background(cardBg)
        .cornerRadius(10)
        .frame(maxWidth: .infinity)
    }

    // MARK: 登录行：状态（左）｜记住密码（中）｜登录按钮（右）
    private var loginRow: some View {
        HStack(spacing: 0) {
            // 左：登录状态
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(isLoggedIn ? "已登录" : "未登录")
                    .font(.system(size: 13))
                    .foregroundColor(statusColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 中：记住密码（居中）
            Button {
                remember.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: remember ? "checkmark.square.fill" : "square")
                        .foregroundColor(fg)
                    Text("记住密码")
                        .font(.system(size: 13))
                        .foregroundColor(fg)
                }
            }
            .frame(maxWidth: .infinity)

            // 右：登录按钮（无背景文字按钮）
            Button {
                login()
            } label: {
                Text("登录")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(fg)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 48)
        .disabled(isLoading)
    }

    private var deviceTitle: some View {
        Text("选择要控制的电脑")
            .font(.system(size: 15))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }

    // MARK: 设备列表：无背景，横线分隔（浅色黑线/深色白线）
    private var deviceList: some View {
        VStack(spacing: 0) {
            if devices.isEmpty {
                Text(isLoading ? "正在登录…" : "暂无设备，请先登录")
                    .font(.system(size: 14))
                    .foregroundColor(sub)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                    Button {
                        showActions(device)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 20))
                                .foregroundColor(fg)
                            Text(device.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(fg)
                            Text(" ›")
                                .font(.system(size: 18))
                                .foregroundColor(sub)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    if index < devices.count - 1 {
                        Rectangle()
                            .fill(isDark ? Color.white : Color.black)
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var tipText: some View {
        Text("提示：发送命令需要网络连接，电脑需已接入远程电源控制设备")
            .font(.system(size: 12))
            .foregroundColor(sub)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    // MARK: 操作弹窗：居中、带图标
    private func showActions(_ device: (name: String, id: String)) {
        let alert = UIAlertController(title: "操作设备：" + device.name, message: nil, preferredStyle: .alert)
        for action in actions {
            alert.addAction(UIAlertAction(title: action.name, style: .default, handler: { _ in
                send(device: device, action: action)
            }))
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert)
    }

    // MARK: 登录
    private func login() {
        guard !account.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            toastMsg = "请先填写账号和密码"
            return
        }
        isLoading = true
        var req = URLRequest(url: URL(string: loginURL)!)
        req.httpMethod = "POST"
        req.setValue(WebHelperConfig.wechatUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let a = account.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account
        let p = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        req.httpBody = "account=\(a)&password=\(p)".data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, resp, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.toastMsg = "登录失败：" + error.localizedDescription
                    return
                }
                guard let http = resp as? HTTPURLResponse,
                      let data = data,
                      let html = String(data: data, encoding: .utf8) else {
                    self.toastMsg = "登录失败：网络异常"
                    return
                }
                let setCookie = http.allHeaderFields["Set-Cookie"] as? String ?? ""
                guard let m = setCookie.range(of: "Share_ESPopenid=([^;]+)", options: .regularExpression) else {
                    self.toastMsg = "登录失败：账号或密码错误"
                    return
                }
                let value = String(setCookie[m]).replacingOccurrences(of: "Share_ESPopenid=", with: "")
                let newCookie = "Share_ESPopenid=" + value
                self.cookie = newCookie
                UserDefaults.standard.set(newCookie, forKey: "rb_cookie")
                if self.remember {
                    UserDefaults.standard.set(true, forKey: "rb_remember")
                    UserDefaults.standard.set(self.account, forKey: "rb_account")
                    UserDefaults.standard.set(self.password, forKey: "rb_password")
                } else {
                    UserDefaults.standard.set(false, forKey: "rb_remember")
                    UserDefaults.standard.removeObject(forKey: "rb_account")
                    UserDefaults.standard.removeObject(forKey: "rb_password")
                }
                let parsed = Self.parseDevices(html)
                self.devices = parsed
                self.saveDevices(parsed)
                self.toastMsg = "登录成功，共 \(parsed.count) 台设备"
            }
        }.resume()
    }

    /// 从登录页 HTML 解析设备（与安卓正则一致：class='weui-cells' id=Axxx <p>设备名</p>）
    static func parseDevices(_ html: String) -> [(name: String, id: String)] {
        var result: [(name: String, id: String)] = []
        let pattern = "class='weui-cells' id=(A[0-9A-Za-z]+)[\\s\\S]*?<p>([^<]+)</p>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = html as NSString
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let m = match else { return }
            let id = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty && !name.isEmpty {
                result.append((name, id))
            }
        }
        return result
    }

    // MARK: 发送命令
    private func send(device: (name: String, id: String), action: (name: String, code: String, icon: String)) {
        guard !cookie.isEmpty else {
            toastMsg = "请先登录"
            return
        }
        isLoading = true
        var req = URLRequest(url: URL(string: cmdURL + "?topics=\(device.id)&message=\(action.code)")!)
        req.setValue(WebHelperConfig.wechatUA, forHTTPHeaderField: "User-Agent")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue(loginURL, forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.toastMsg = "发送失败：" + error.localizedDescription
                    return
                }
                guard let data = data, let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
                    self.toastMsg = "命令发送失败，请稍后重试"
                    return
                }
                if body.contains("404") {
                    self.toastMsg = "登录会话已失效，请重新登录"
                    return
                }
                // 显示服务器真实反馈（指令有效/指令无效/请检查设备网络或稍后重试）
                self.toastMsg = body
            }
        }.resume()
    }

    private func saveDevices(_ list: [(name: String, id: String)]) {
        let text = list.map { $0.name + "|" + $0.id }.joined(separator: "\n")
        UserDefaults.standard.set(text, forKey: "rb_devices")
    }

    private func loadDevices() -> [(name: String, id: String)] {
        let text = UserDefaults.standard.string(forKey: "rb_devices") ?? ""
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return (parts[0], parts[1])
        }
    }

    private func present(_ alert: UIAlertController) {
        guard let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first?.rootViewController else { return }
        var top = host
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
}

// MARK: - 通用无图标提示

struct ToastLabel: View {
    let text: String
    let dark: Bool
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(dark ? .white : .black)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(dark ? Color(red: 0.086, green: 0.086, blue: 0.086) : Color(red: 0.95, green: 0.95, blue: 0.95))
            .cornerRadius(10)
    }
}
