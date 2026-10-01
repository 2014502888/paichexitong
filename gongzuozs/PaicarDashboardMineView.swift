import SwiftUI

// MARK: - 数据看板（对应 PaicarDashboardFragment）

struct PaicarDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var apply: [String: Any] = [:]
    @State private var dispatch: [String: Any] = [:]
    @State private var loading = true
    @State private var error = ""
    @State private var col = 0

    private let cols = ["今日", "昨天", "本月", "上月"]
    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var sub: Color { isDark ? Color(white: 0.7) : Color(white: 0.35) }
    private var cardBg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : .white }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if loading {
                    ProgressView().padding(.top, 160)
                } else if !error.isEmpty {
                    Text(error).font(.system(size: 14)).foregroundColor(fg).padding(.top, 160)
                    Button("重试") { load() }
                        .font(.system(size: 14))
                        .foregroundColor(blue)
                        .padding(.top, 12)
                } else {
                    card
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : Color(white: 0.96))
        .onAppear {
            if loading && apply.isEmpty && dispatch.isEmpty { load() }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            // 标题：居中 + 右侧刷新（箭头圆圈，浅黑深白）
            HStack(spacing: 0) {
                Color.clear.frame(width: 32, height: 32)
                Text("我的派车单")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(fg)
                    .frame(maxWidth: .infinity)
                Button {
                    load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15))
                        .foregroundColor(fg)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)

            // 列头
            HStack(spacing: 0) {
                Color.clear.frame(width: 90, height: 1)
                ForEach(0..<4, id: \.self) { i in
                    Button {
                        col = i
                    } label: {
                        VStack(spacing: 0) {
                            Text(cols[i])
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(col == i ? blue : sub)
                            Rectangle()
                                .fill(col == i ? blue : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            row("待派车", pendingDispatch, blue)
            row("待分配车辆", pendingAssign, Color(red: 1.0, green: 0.60, blue: 0.0))
            row("已分配车辆", assigned, Color(red: 0.30, green: 0.68, blue: 0.31))
            row("已结单", finished, Color(red: 0.61, green: 0.15, blue: 0.69))
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(cardBg))
    }

    private func row(_ label: String, _ vals: [Int], _ barColor: Color) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(barColor).frame(width: 4, height: 18)
            Spacer().frame(width: 10)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(fg)
                .frame(width: 90, alignment: .leading)
            ForEach(0..<4, id: \.self) { i in
                Text("\(vals[i])")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(col == i ? blue : fg)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func v(_ m: [String: Any], _ k: String) -> Int {
        Int((m[k] as? String) ?? "") ?? ((m[k] as? NSNumber)?.intValue ?? 0)
    }

    private var pendingDispatch: [Int] {
        [v(apply, "today_zt1"), v(apply, "yesterday_zt1"), v(apply, "month_zt1"), v(apply, "lastmonth_zt1")]
    }
    private var pendingAssign: [Int] {
        [v(dispatch, "today_zt3"), v(dispatch, "yesterday_zt3"), v(dispatch, "month_zt3"), v(dispatch, "lastmonth_zt3")]
    }
    private var assigned: [Int] {
        [v(dispatch, "today_zt4"), v(dispatch, "yesterday_zt4"), v(dispatch, "month_zt4"), v(dispatch, "lastmonth_zt4")]
    }
    private var finished: [Int] {
        [v(dispatch, "today_finished"), v(dispatch, "yesterday_finished"), v(dispatch, "month_finished"), v(dispatch, "lastmonth_finished")]
    }

    private func load() {
        loading = true
        error = ""
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                async let a = PaicarApi.applyOrderGather(organId: p.organId, rolesId: p.rolesId)
                async let d = PaicarApi.dispatchOrderGather(organId: p.organId, rolesId: p.rolesId)
                let (aa, dd) = try await (a, d)
                apply = aa
                dispatch = dd
                loading = false
            } catch PaicarError.authExpired {
                loading = false
            } catch let err {
                loading = false
                error = (err as? PaicarError)?.errorDescription ?? err.localizedDescription
            }
        }
    }
}

// MARK: - 我的（对应 PaicarMineFragment）

struct PaicarMineView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    @State private var profile: PaicarProfile?
    @State private var toastMsg: String?
    @State private var showChangePwd = false

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var sub: Color { isDark ? Color(white: 0.67) : Color(white: 0.35) }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)
            if let p = profile {
                Text(String(p.name.first ?? "?"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(blue)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(blue.opacity(0.12)))
                Text(p.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(fg)
                    .padding(.top, 10)
                Text(p.organName)
                    .font(.system(size: 13))
                    .foregroundColor(sub)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }

            // 修改密码：锁图标 + 文字整体居中
            Button {
                showChangePwd = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(fg)
                    Text("修改密码")
                        .font(.system(size: 15))
                        .foregroundColor(fg)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            Rectangle().fill(Color(white: 0.5).opacity(0.16)).frame(height: 1)
                .padding(.leading, 16)

            // 退出登录：居中红字
            Button {
                logout()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.square.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                    Text("退出登录")
                        .font(.system(size: 15))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            Spacer()
        }
        .background(pageBg)
        .onAppear {
            if profile == nil { load() }
        }
        .overlay(
            Group {
                if let msg = toastMsg {
                    PaicarToast(text: msg, dark: isDark)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.toastMsg = nil
                            }
                        }
                }
            }
        )
        .sheet(isPresented: $showChangePwd) {
            ChangePwdSheet()
        }
    }

    private func load() {
        Task {
            do {
                profile = try await PaicarProfileHolder.load()
            } catch { /* 静默 */ }
        }
    }

    private func logout() {
        PaicarApi.silentAuthExpired = true
        PaicarApi.justLoggedOut = true
        PaicarSession.clear()
        PaicarProfileHolder.profile = nil
        NotificationCenter.default.post(name: .paicarForceLogin, object: nil)
    }
}

// MARK: - 修改密码（对应 PaicarMineFragment.changePwd）

struct ChangePwdSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    @State private var old = ""
    @State private var neu = ""
    @State private var neu2 = ""
    @State private var toastMsg: String?
    @State private var working = false

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var inputBg: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.17) : Color(white: 0.96) }
    private var border: Color { isDark ? Color(white: 0.33) : Color(white: 0.8) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text("修改密码")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            VStack(spacing: 14) {
                secureField("原密码", $old)
                secureField("新密码", $neu)
                secureField("确认新密码", $neu2)

                Button {
                    submit()
                } label: {
                    Text(working ? "提交中…" : "确定")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(red: 0.08, green: 0.28, blue: 0.75))
                        .cornerRadius(10)
                }
                .disabled(working)
                .padding(.top, 10)
            }
            .padding(20)
            Spacer()
        }
        .background(pageBg)
        .overlay(
            Group {
                if let msg = toastMsg {
                    PaicarToast(text: msg, dark: isDark)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.toastMsg = nil
                            }
                        }
                }
            }
        )
    }

    private func secureField(_ hint: String, _ text: Binding<String>) -> some View {
        SecureField(hint, text: text)
            .font(.system(size: 15))
            .foregroundColor(fg)
            .accentColor(fg)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(inputBg)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
    }

    private func submit() {
        if neu != neu2 {
            toastMsg = "两次新密码不一致"
            return
        }
        if old == neu {
            toastMsg = "新密码不能与原密码相同"
            return
        }
        working = true
        Task {
            do {
                _ = try await PaicarApi.changePwd(orgPwd: old, newPwd: neu)
                working = false
                toastMsg = "修改成功，请重新登录"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    PaicarSession.clear()
                    PaicarProfileHolder.profile = nil
                    NotificationCenter.default.post(name: .paicarForceLogin, object: nil)
                }
            } catch {
                working = false
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
