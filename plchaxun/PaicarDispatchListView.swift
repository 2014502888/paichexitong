import SwiftUI

// MARK: - 状态色与工具

enum PaicarStyle {
    static func statusColor(_ code: String) -> Color {
        switch code {
        case "999": return Color(red: 0.61, green: 0.15, blue: 0.69)   // 紫
        case "004": return Color(red: 0.30, green: 0.68, blue: 0.31)   // 绿
        case "003": return Color(red: 1.0, green: 0.60, blue: 0.0)     // 橙
        case "001": return Color(red: 0.08, green: 0.28, blue: 0.75)   // 蓝
        default: return Color.gray
        }
    }

    /// 邮路去掉固定前缀"晋江南区电商-" / "南区电商-"（含-）
    static func stripRoute(_ name: String) -> String {
        if name.hasPrefix("晋江南区电商-") { return String(name.dropFirst(7)) }
        if name.hasPrefix("南区电商-") { return String(name.dropFirst(5)) }
        return name
    }

    /// 邮路 + 短名括号（对应安卓 routes 拼接）
    static func routeLine(_ name: String, _ short: String) -> String {
        stripRoute(name) + (short.isEmpty ? "" : "(\(short))")
    }

    /// 容积利用率
    static func volRate(_ o: PaicarDispatchOrder) -> Int {
        var sum = 0.0
        for a in o.applyList { sum += Double(a.volume) ?? 0 }
        let cap = Double(o.volume) ?? 0
        if cap <= 0 || sum <= 0 { return 0 }
        return Int((sum / cap * 100).rounded())
    }

    /// 日期 yyyy-MM-dd（取前 10 位校验）
    static func dayOf(_ t: String) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 10 {
            let d = String(s.prefix(10))
            if d.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return d }
        }
        return ""
    }

    static func addDays(_ dateStr: String, _ delta: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: dateStr),
              let nd = Calendar.current.date(byAdding: .day, value: delta, to: d) else { return dateStr }
        return f.string(from: nd)
    }
}

// MARK: - 派车单列表（对应 PaicarDispatchListFragment）

struct PaicarDispatchListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    // 数据
    @State private var showFinished = false
    @State private var applies: [PaicarApplyOrder] = []
    @State private var dispatches: [PaicarDispatchOrder] = []
    @State private var finishedList: [PaicarDispatchOrder] = []
    @State private var finishedPool: [PaicarDispatchOrder] = []

    // 加载状态
    @State private var loading = true
    @State private var loadingMore = false
    @State private var loadingMoreFinished = false
    @State private var loadingFinished = false
    @State private var hasMoreDispatch = true
    @State private var hasMoreFinished = true
    @State private var emptyPages = 0
    @State private var dispatchPage = 0
    @State private var finishedPage = 0
    @State private var exhausted = false
    @State private var error = ""
    @State private var finishedLoadedOnce = false
    @State private var finishedMoreCooldown = false
    @State private var finishedCursor = ""   // 当前已显示到哪一天（yyyy-MM-dd）
    @State private var pushApplyId: String?
    @State private var pushDispatchId: String?
    @State private var didInitialLoad = false   // 首次进入必加载（修复 onAppear 守卫 !loading 把首次加载挡住导致永远转圈）

    // UI
    @State private var toastMsg: String?
    @State private var showMenu = false
    @State private var confirmApply = false
    @State private var confirmRecall = false
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var cardBg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : .white }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    private var canScrollDown: Bool { contentHeight > viewportHeight + 8 }

    var body: some View {
        VStack(spacing: 0) {
            // 全部 | 已结单 切换
            HStack(spacing: 8) {
                tabBtn("全部", active: !showFinished) { setShowFinished(false) }
                tabBtn("已结单", active: showFinished) { setShowFinished(true) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 胶囊行：待派车/待分配/已分配（只在全部页显示）
            if !showFinished && (!applies.isEmpty || !dispatches.isEmpty) {
                HStack(spacing: 6) {
                    capsule("待派车 \(applies.count)部", blue)
                    capsule("待分配 \(dispatches.filter { $0.statusCode == "003" }.count)部", Color(red: 1.0, green: 0.60, blue: 0.0))
                    capsule("已分配 \(dispatches.filter { $0.statusCode == "004" }.count)部", Color(red: 0.30, green: 0.68, blue: 0.31))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            if loading {
                Spacer()
                ProgressView()
                Spacer()
            } else if error.isEmpty == false && (showFinished ? finishedList.isEmpty : (applies.isEmpty && dispatches.isEmpty)) {
                Spacer()
                Text(error).font(.system(size: 14)).foregroundColor(fg)
                Button("重试") { load() }
                    .font(.system(size: 14))
                    .foregroundColor(blue)
                    .padding(.top, 12)
                Spacer()
            } else if showFinished ? finishedList.isEmpty : (applies.isEmpty && dispatches.isEmpty) {
                Spacer()
                Text("📭").font(.system(size: 50))
                Text(showFinished ? "暂无已结单" : "暂无派车单")
                    .font(.system(size: 16))
                    .foregroundColor(fg)
                Spacer()
            } else {
                ScrollView {
                    ScrollViewReader { _ in
                        VStack(spacing: 0) {
                            ForEach(renderedItems, id: \.self) { item in
                                switch item {
                                case .apply(let o):
                                    Button { pushApplyId = o.id } label: { applyCard(o) }
                                        .buttonStyle(.plain)
                                case .dispatch(let o):
                                    Button { pushDispatchId = o.id } label: { dispatchCard(o) }
                                        .buttonStyle(.plain)
                                case .hint(let isLast):
                                    moreHint(isLast: isLast)
                                }
                            }
                            // 底部哨兵：滚动到底触发加载（配合冷却实现一次手势最多加载一天）
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        viewportHeight = geo.size.height
                                        onReachBottom()
                                    }
                            }
                            .frame(height: 1)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: PaicarContentHeightKey.self, value: geo.size.height)
                            }
                        )
                    }
                }
                .onPreferenceChange(PaicarContentHeightKey.self) { h in
                    contentHeight = h
                }
            }
        }
        .background(pageBg)
        .background(
            ZStack {
                NavigationLink(
                    destination: PaicarApplyDetailView(orderId: pushApplyId ?? "").paicarAuthGuard(),
                    isActive: Binding(get: { pushApplyId != nil }, set: { if !$0 { pushApplyId = nil } })
                ) { EmptyView() }
                NavigationLink(
                    destination: PaicarDetailView(orderId: pushDispatchId ?? "").paicarAuthGuard(),
                    isActive: Binding(get: { pushDispatchId != nil }, set: { if !$0 { pushDispatchId = nil } })
                ) { EmptyView() }
            }
            .opacity(0)
        )
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
        // "＋"菜单由外部顶栏持有（PaicarDispatchListToolbar）
        .confirmationDialog("操作", isPresented: $showMenu, titleVisibility: .visible) {
            Button("派车申请") { newApply() }
            Button("一键申请") { quickApply() }
            Button("一键撤回") { quickRecall() }
            Button("申请配置") {
                NotificationCenter.default.post(name: .paicarOpenQuickEdit, object: nil)
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            if !didInitialLoad {
                didInitialLoad = true
                load()
            } else if PaicarFlags.dispatchDirty || PaicarFlags.finishedDirty {
                // 结单/撤回/提交成功后回到列表: 脏标记表示数据已变, 必须重载全部列表;
                // 之前只在"列表为空"时才重载, 导致刚结单完还卡在旧数据不刷新。
                PaicarFlags.dispatchDirty = false
                PaicarFlags.finishedDirty = false
                if showFinished { loadFinished() }
                load()
            } else if !loading && applies.isEmpty && dispatches.isEmpty && finishedList.isEmpty {
                load()
            }
        }
        // 右缘左滑返回：从已结单子tab切回全部
        .onReceive(NotificationCenter.default.publisher(for: .paicarBackToAllList)) { _ in
            // 结单成功后: 强制切回"全部", 并按脏标记刷新全部列表
            // (全部只归类待分配/待派车/已分配, 刚结的单自然从全部消失)
            if showFinished { showFinished = false }
            if PaicarFlags.dispatchDirty || PaicarFlags.finishedDirty {
                PaicarFlags.dispatchDirty = false
                PaicarFlags.finishedDirty = false
                load()
            }
        }
        // 顶栏 + 按钮：弹出操作菜单
        .onReceive(NotificationCenter.default.publisher(for: .paicarShowMenu)) { _ in
            showMenu = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarReloadAfterLogin)) { _ in
            load()
        }
    }

    private var renderedItems: [PaicarListItem] {
        if showFinished {
            var l: [PaicarListItem] = []
            var i = 0
            while i < finishedList.count {
                let day = PaicarStyle.dayOf(finishedList[i].createTime)
                var end = i + 1
                while end < finishedList.count && PaicarStyle.dayOf(finishedList[end].createTime) == day { end += 1 }
                for k in i..<end { l.append(.dispatch(finishedList[k])) }
                l.append(.hint(end >= finishedList.count))
                i = end
            }
            return l
        } else {
            var l: [PaicarListItem] = []
            for a in applies { l.append(.apply(a)) }
            for d in dispatches { l.append(.dispatch(d)) }
            l.append(.hint(true))
            return l
        }
    }

    // MARK: 加载

    private func setShowFinished(_ v: Bool) {
        showFinished = v
        if v { loadFinished() } else { /* renderList 自动 */ }
    }

    private func load() {
        loading = true
        error = ""
        // UI 级硬超时兜底：即使网络层极端异常，16 秒内必结束转圈并显示错误，不再无限转圈
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
            guard self.loading else { return }
            self.loading = false
            self.error = "加载超时（网络无响应），请检查网络后重试"
        }
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                // 串行请求；超时已下沉到 PaicarApi.perform（回调版+强制取消，15 秒内必出结果，不再无限转圈）
                let rawApplies = try await PaicarApi.applyOrderList(organId: p.organId, rolesId: p.rolesId)
                let rawDispatch = try await PaicarApi.dispatchOrderList(organId: p.organId, rolesId: p.rolesId, page: 1, perpage: 20)
                dispatchPage = 1
                applies = rawApplies.map { PaicarApplyOrder.fromJson($0) }
                    .filter { $0.statusCode == "000" || $0.statusCode == "001" }
                    .sorted { $0.statusCode < $1.statusCode }
                dispatches = rawDispatch.map { PaicarDispatchOrder.fromJson($0) }
                    .filter { $0.statusCode == "003" || $0.statusCode == "004" }
                    .sorted { $0.statusCode < $1.statusCode }
                hasMoreDispatch = rawDispatch.count >= 20
                loading = false
            } catch PaicarError.authExpired {
                loading = false
            } catch let err {
                loading = false
                error = (err as? PaicarError)?.errorDescription ?? err.localizedDescription
            }
        }
    }

    private func loadMoreDispatch() {
        if loadingMore || !hasMoreDispatch || loading || showFinished { return }
        loadingMore = true
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                let raw = try await PaicarApi.dispatchOrderList(organId: p.organId, rolesId: p.rolesId, page: dispatchPage + 1, perpage: 20)
                dispatchPage += 1
                let more = raw.map { PaicarDispatchOrder.fromJson($0) }
                    .filter { $0.statusCode == "003" || $0.statusCode == "004" }
                    .sorted { $0.statusCode < $1.statusCode }
                if raw.count < 20 { hasMoreDispatch = false }
                if more.isEmpty {
                    emptyPages += 1
                    if emptyPages >= 3 { hasMoreDispatch = false }
                } else {
                    emptyPages = 0
                }
                dispatches.append(contentsOf: more)
                loadingMore = false
            } catch PaicarError.authExpired {
                loadingMore = false
            } catch {
                loadingMore = false
            }
        }
    }

    /// 首次进入已结单：从第 1 页翻到找到 999 状态单为止（最多 50 页），取当天数据
    private func loadFinished() {
        if loadingFinished { return }
        // 已加载过且无新结单：直接显示已加载数据，不重复读服务器
        if finishedLoadedOnce && !PaicarFlags.finishedDirty {
            return
        }
        if PaicarFlags.finishedDirty {
            PaicarFlags.finishedDirty = false
            finishedLoadedOnce = false
        }
        loadingFinished = true
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                finishedList.removeAll()
                finishedPool.removeAll()
                finishedPage = 0
                exhausted = false
                hasMoreFinished = true
                var guardCount = 0
                while finishedPool.contains(where: { $0.statusCode == "999" }) == false && !exhausted && guardCount < 50 {
                    guardCount += 1
                    try await fetchFinishedPage(p: p)
                }
                if let first = finishedPool.first {
                    let day = PaicarStyle.dayOf(first.createTime)
                    if !day.isEmpty {
                        finishedCursor = day
                        finishedList.append(contentsOf: finishedPool.filter { PaicarStyle.dayOf($0.createTime) == day })
                        finishedCursor = PaicarStyle.addDays(day, -1)
                    }
                }
                loadingFinished = false
                finishedLoadedOnce = true
            } catch PaicarError.authExpired {
                loadingFinished = false
            } catch let err {
                loadingFinished = false
                error = (err as? PaicarError)?.errorDescription ?? err.localizedDescription
            }
        }
    }

    private func fetchFinishedPage(p: PaicarProfile) async throws {
        if exhausted || finishedPage >= 50 {
            exhausted = true
            return
        }
        let raw = try await PaicarApi.dispatchOrderList(organId: p.organId, rolesId: p.rolesId, page: finishedPage + 1, perpage: 20)
        finishedPage += 1
        for e in raw {
            let o = PaicarDispatchOrder.fromJson(e)
            if o.statusCode == "999" { finishedPool.append(o) }
        }
        if raw.count < 20 || finishedPage >= 50 { exhausted = true }
    }

    /// 继续翻页加载前一天（一次手势最多一天）
    private func loadMoreFinished() {
        if loadingMoreFinished || !hasMoreFinished || loadingFinished || !showFinished { return }
        loadingMoreFinished = true
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                var guardCount = 0
                var found = false
                while !exhausted && guardCount < 50 {
                    guardCount += 1
                    try await fetchFinishedPage(p: p)
                    let dayList = finishedPool.filter { PaicarStyle.dayOf($0.createTime) == finishedCursor }
                    if !dayList.isEmpty {
                        finishedList.append(contentsOf: dayList)
                        finishedCursor = PaicarStyle.addDays(finishedCursor, -1)
                        found = true
                        break
                    }
                    if exhausted { break }
                }
                if exhausted && !found {
                    hasMoreFinished = false
                }
                loadingMoreFinished = false
            } catch PaicarError.authExpired {
                loadingMoreFinished = false
            } catch {
                loadingMoreFinished = false
            }
        }
    }

    /// 滚动到底触发：配合冷却，一次手势最多加载一天
    private func onReachBottom() {
        if finishedMoreCooldown {
            finishedMoreCooldown = false
            return
        }
        finishedMoreCooldown = true
        if showFinished { loadMoreFinished() } else { loadMoreDispatch() }
    }

    // MARK: 提示条

    private func moreHint(isLast: Bool) -> some View {
        let canMore = loadingMore || loadingMoreFinished ? false : (showFinished ? hasMoreFinished : hasMoreDispatch)
        let text: String = {
            if loadingMore || loadingMoreFinished { return "加载中…" }
            if !canMore && isLast {
                return showFinished ? "没有更多了" : "当前还有 \(applies.count + dispatches.count) 部车未结单"
            }
            if !canMore { return "查看更多" }
            if canScrollDown { return "下滑查看更多" }
            return "点击查看更多"
        }()
        return Button {
            finishedMoreCooldown = false
            if showFinished { loadMoreFinished() } else { loadMoreDispatch() }
        } label: {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .disabled(!canMore)
    }

    // MARK: 卡片

    private func applyCard(_ o: PaicarApplyOrder) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                statusTag((o.statusName.isEmpty ? "待派车" : o.statusName), PaicarStyle.statusColor(o.statusCode))
                Text(o.orderNumber).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text("客户 \(o.customerName)").font(.system(size: 13)).foregroundColor(.white)
                Text(PaicarStyle.routeLine(o.routeName.isEmpty ? o.routeShortName : o.routeName, o.liaisonName)).font(.system(size: 13)).foregroundColor(.white)
                Text("\(o.number)件 · \(o.carSpecs) · \(o.arrivalTime)")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.95))
                if !o.createTime.isEmpty {
                    Text("登记 \(o.createName) \(o.createTime)")
                        .font(.system(size: 12)).foregroundColor(Color(white: 0.95))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(PaicarStyle.statusColor(o.statusCode)))
            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
    }

    private func dispatchCard(_ o: PaicarDispatchOrder) -> some View {
        let status = o.statusName + (o.carNo.isEmpty ? "" : " \(o.carNo)")
        let customers = o.applyList.map { $0.customerName }.filter { !$0.isEmpty }
        let routes = o.applyList.map { PaicarStyle.routeLine($0.routeName, $0.routeShortName) }
        let creators = o.applyList.filter { !$0.createName.isEmpty }
            .map { "\($0.createName) \($0.createTime) 申请派车" }
        return HStack(spacing: 0) {
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                statusTag(status, PaicarStyle.statusColor(o.statusCode), size: 15)
                if let first = o.applyList.first {
                    Text("到达时间:\(first.arrivalTime)").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !customers.isEmpty {
                    Text(customers.joined(separator: "、")).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !routes.isEmpty {
                    Text(routes.joined(separator: "、")).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.carNo.isEmpty || !o.driverName.isEmpty {
                    Text("\(o.carNo) \(o.driverName) \(o.driverPhone)")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.applyList.isEmpty {
                    Text("派车单：\(o.orderNumber)  车辆规格：\(o.specs)")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                ForEach(Array(creators.enumerated()), id: \.offset) { _, c in
                    Text(c).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.createName.isEmpty {
                    Text("\(o.createName) \(o.createTime) 创建派车").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.receiveName.isEmpty {
                    Text("\(o.receiveName) \(o.receiveTime) 分配车辆").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if showFinished {
                    Text("车辆 \(o.specs)米 · 装载 \(o.loadingNum) 件 · 装载率 \(PaicarStyle.volRate(o))%")
                        .font(.system(size: 13)).foregroundColor(Color(white: 0.95))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(PaicarStyle.statusColor(o.statusCode)))
            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
    }

    private func statusTag(_ text: String, _ color: Color, size: CGFloat = 12) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }

    private func capsule(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color))
    }

    private func tabBtn(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: active ? .bold : .regular))
                .foregroundColor(active ? .white : fg)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? blue : (isDark ? Color(white: 0.16) : Color(white: 0.9))))
        }
    }

    // MARK: 菜单操作

    private func newApply() {
        NotificationCenter.default.post(name: .paicarOpenNewApply, object: nil)
    }

    private func quickApply() {
        let cars = PaicarApi.loadQuickCars().filter { $0["enabled"] == "1" }
        if cars.isEmpty {
            toastMsg = "请先去配置界面填写相关信息"
            return
        }
        // 二次确认
        let alert = UIAlertController(title: "确认一键申请？", message: "将按配置批量创建 \(cars.count) 张申请单", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认申请", style: .default) { _ in
            runQuickApply(cars: cars)
        })
        present(alert)
    }

    private func runQuickApply(cars: [[String: String]]) {
        Task {
            var okCount = 0
            var failLog: [String] = []
            var newIds: [String] = []
            for spec in cars {
                do {
                    let id = try await PaicarApi.quickApplyCar(spec)
                    newIds.append(id)
                    okCount += 1
                } catch {
                    failLog.append("\(spec["customerName"] ?? ""): \(error.localizedDescription)")
                }
            }
            var ids = PaicarApi.loadQuickIds()
            for id in newIds where !ids.contains(id) { ids.append(id) }
            PaicarApi.saveQuickIds(ids)
            if failLog.isEmpty {
                toastMsg = "成功创建 \(okCount)/\(cars.count) 张申请单"
            } else {
                toastMsg = "创建完成 \(okCount)/\(cars.count) 张，\(failLog.joined(separator: "\n"))"
            }
            load()
        }
    }

    private func quickRecall() {
        let ids = PaicarApi.loadQuickIds()
        if ids.isEmpty {
            toastMsg = "没有可撤回的申请单"
            return
        }
        let alert = UIAlertController(title: "确认一键撤回？", message: "将撤回并删除所有快捷申请单", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认撤回", style: .destructive) { _ in
            doQuickRecall(ids: ids)
        })
        present(alert)
    }

    private func doQuickRecall(ids: [String]) {
        Task {
            var fail = 0
            var authFailed = false
            for id in ids {
                do {
                    try await PaicarApi.quickRecall(id: id)
                } catch PaicarError.authExpired {
                    authFailed = true
                    break
                } catch {
                    fail += 1
                }
            }
            if authFailed {
                toastMsg = "登录已失效，请重新登录"
                load()
                return
            }
            PaicarApi.saveQuickIds([])
            if fail == 0 {
                toastMsg = "已全部撤回并删除"
            } else {
                toastMsg = "已处理（\(fail) 张失败）"
            }
            load()
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

struct PaicarContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum PaicarListItem: Hashable {
    case apply(PaicarApplyOrder)
    case dispatch(PaicarDispatchOrder)
    case hint(Bool)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .apply(let o): hasher.combine("a"); hasher.combine(o.id)
        case .dispatch(let o): hasher.combine("d"); hasher.combine(o.id)
        case .hint(let last): hasher.combine("h"); hasher.combine(last)
        }
    }
}
