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
    @State private var dispatchPage = 0
    @State private var finishedPage = 0
    @State private var exhausted = false
    @State private var error = ""
    // 登录失效标记：error 为"登录已失效"时按钮显示"登入"（换 token 自动登入），否则显示"重试"
    @State private var authError = false
    @State private var finishedLoadedOnce = false
    @State private var finishedCursor = ""   // 当前已显示到哪一天（yyyy-MM-dd）
    @State private var moreLoadedDays: Set<String> = []   // 通过"查看更多"加载出来的日期（列表里显示"以下是 YYYY-MM-DD"静态标识）
    @State private var lastPageOldestDay = ""   // 最近翻到的一页里最旧单的日期，用于提前终止（翻过目标日后不再无谓翻页）
    @State private var pushApplyId: String?
    @State private var pushDispatchId: String?
    @State private var didInitialLoad = false   // 首次进入必加载（修复 onAppear 守卫 !loading 把首次加载挡住导致永远转圈）

    // UI
    @State private var toastMsg: String?
    @State private var showMenu = false
    @State private var confirmApply = false
    @State private var confirmRecall = false
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var filterFinishedDay: String? = nil
    // 批量结单：独立 tab（全部 | 批量结单 | 已结单），进入时静默刷新已分配，勾选后抬头"开始结单"
    @State private var showBatch = false
    @State private var batchSelected: Set<String> = []
    @State private var batchOrders: [PaicarDispatchOrder] = []
    @State private var showBatchFinish = false

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var cardBg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : .white }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    var body: some View {
        VStack(spacing: 0) {
            // 全部 | 批量结单 | 已结单 切换
            HStack(spacing: 8) {
                tabBtn("全部", active: !showFinished && !showBatch) { setShowAll() }
                tabBtn("结单", active: showBatch) { setShowBatch(true) }
                tabBtn("已结单", active: showFinished) { setShowFinished(true) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 结单 tab 抬头：开始结单按钮居中显示（标题"批量结单（N部）"已去除）+ 下方小字提示（浅色灰/深色灰白）
            if showBatch {
                Button("开始结单") {
                    startBatchFinish()
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Capsule().fill(batchSelected.isEmpty ? Color.gray.opacity(0.5) : blue))
                .disabled(batchSelected.isEmpty)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
                Text("（请选择派车单批量结单）")
                    .font(.system(size: 12))
                    .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
            }

            // 胶囊行：待派车/待分配/已分配（只在全部页显示）
            if !showFinished && !showBatch && (!applies.isEmpty || !dispatches.isEmpty) {
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
            } else if error.isEmpty == false && (showFinished ? finishedList.isEmpty : (showBatch ? batchDispatches.isEmpty : (applies.isEmpty && dispatches.isEmpty))) {
                Spacer()
                Text(error).font(.system(size: 14)).foregroundColor(fg)
                // 登录失效：重试无效（旧 token 永远 410），换成"登入"直接换新 token 自动登入
                if authError {
                    Button("登入") { PaicarApi.reLoginWithSaved() }
                        .font(.system(size: 14))
                        .foregroundColor(blue)
                        .padding(.top, 12)
                } else {
                    Button("重试") { load() }
                        .font(.system(size: 14))
                        .foregroundColor(blue)
                        .padding(.top, 12)
                }
                Spacer()
            } else if showFinished ? finishedList.isEmpty : (showBatch ? batchDispatches.isEmpty : (applies.isEmpty && dispatches.isEmpty)) {
                Spacer()
                Text("📭").font(.system(size: 50))
                Text(showFinished ? "暂无已结单" : (showBatch ? "暂无已分配车辆" : "暂无派车单"))
                    .font(.system(size: 16))
                    .foregroundColor(fg)
                Spacer()
            } else if showBatch {
                // 批量结单列表：只显示已分配(004)车，整卡点击切换勾选
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(batchDispatches, id: \.id) { o in
                            Button { toggleBatchSelect(o.id) } label: { batchCard(o) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(renderedItems, id: \.self) { item in
                                switch item {
                                case .apply(let o):
                                    Button { pushApplyId = o.id } label: { applyCard(o) }
                                        .buttonStyle(.plain)
                                case .dispatch(let o):
                                    Button {
                                        // 进详情前清除该单的"详情观察记录"：详情加载成功会重新写入，
                                        // 加载失败则无记录 → 返回不误刷
                                        PaicarFlags.detailSeenState.removeValue(forKey: o.id)
                                        pushDispatchId = o.id
                                    } label: { dispatchCard(o) }
                                        .buttonStyle(.plain)
                                case .hint(let isLast):
                                    moreHint(isLast: isLast)
                                case .dateLabel(let day):
                                    dateLabel(day)
                                }
                            }
                        }
                }
            }
        }
        .background(pageBg)
        .background(
            ZStack {
                NavigationLink(
                    destination: PaicarApplyDetailView(orderId: pushApplyId ?? ""),
                    isActive: Binding(get: { pushApplyId != nil }, set: { if !$0 { pushApplyId = nil } })
                ) { EmptyView() }
                NavigationLink(
                    destination: PaicarDetailView(orderId: pushDispatchId ?? ""),
                    isActive: Binding(get: { pushDispatchId != nil }, set: { if !$0 { pushDispatchId = nil } })
                ) { EmptyView() }
                // 批量结单页：与其他子页面一致用 NavigationLink push（fullScreenCover 不在导航栈，
                // 没有系统左缘右滑跟手返回；push 后自动获得全屏手势返回）
                NavigationLink(
                    destination: PaicarBatchFinishView(orders: batchOrders),
                    isActive: $showBatchFinish
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
        // 批量结单页已改为 NavigationLink push（见上方 ZStack），保留 showDatePicker 等 sheet
        .sheet(isPresented: $showDatePicker) {
            VStack(spacing: 16) {
                Text("选择日期").font(.system(size: 16, weight: .bold)).padding(.top, 16)
                DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 200)
                HStack(spacing: 20) {
                    Button("取消") { showDatePicker = false }
                        .foregroundColor(.secondary)
                    Button("今天") {
                        selectedDate = Date()
                        filterFinishedDay = nil
                        showDatePicker = false
                    }
                    .foregroundColor(.blue)
                    Button("确定") {
                        let fmt = DateFormatter()
                        fmt.dateFormat = "yyyy-MM-dd"
                        let d = fmt.string(from: selectedDate)
                        filterFinishedDay = d
                        showDatePicker = false
                        loadFinishedForDate(d)
                    }
                    .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            if !didInitialLoad {
                didInitialLoad = true
                load(showLoading: true)
            } else if PaicarFlags.dispatchDirty || PaicarFlags.finishedDirty {
                // 结单/撤回/提交成功后回到列表: 脏标记表示数据已变, 必须重载全部列表;
                // 之前只在"列表为空"时才重载, 导致刚结单完还卡在旧数据不刷新。
                PaicarFlags.dispatchDirty = false
                PaicarFlags.finishedDirty = false
                if showFinished { loadFinished() }
                load(showLoading: false)
            } else if !loading && applies.isEmpty && dispatches.isEmpty {
                // 只要"全部"列表为空就补加载（不再要求 finishedList 也空）：
                // 之前看过已结单后返回，finishedList 非空会把补加载条件挡住，
                // 导致"全部"页一直空、要切走再切回才出现数据。
                load(showLoading: true)
            } else {
                // 详情差异检测：详情页观察到某单状态 ≠ 列表当前状态 → 静默刷新。
                // 场景：外部系统把待分配改成已分配，详情页拉到新状态，返回列表对比发现不一致才刷；
                // 状态没变零请求。静默刷新不闪转圈，刷新完直接把新数据换上去。
                let mismatch = dispatches.contains { o in
                    guard let seen = PaicarFlags.detailSeenState[o.id] else { return false }
                    return seen != o.statusCode
                }
                if mismatch {
                    load(showLoading: false)
                }
            }
        }
        // 右缘左滑返回：从已结单子tab切回全部
        .onReceive(NotificationCenter.default.publisher(for: .paicarBackToAllList)) { _ in
            // 结单成功后: 强制切回"全部", 并按脏标记刷新全部列表
            // (全部只归类待分配/待派车/已分配, 刚结的单自然从全部消失)
            if showFinished { showFinished = false; filterFinishedDay = nil }
            if showBatch { showBatch = false; batchSelected.removeAll() }
            if PaicarFlags.dispatchDirty || PaicarFlags.finishedDirty {
                PaicarFlags.dispatchDirty = false
                PaicarFlags.finishedDirty = false
                load()
            }
        }
        // 顶栏 + 按钮：弹出操作菜单
        .onReceive(NotificationCenter.default.publisher(for: .paicarShowMenu)) { _ in
            if showFinished {
                showDatePicker = true
            } else {
                showMenu = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .paicarReloadAfterLogin)) { _ in
            load()
        }
    }

    private var renderedItems: [PaicarListItem] {
        if showFinished {
            let source: [PaicarDispatchOrder]
            if let fd = filterFinishedDay {
                source = finishedPool.filter { PaicarStyle.dayOf($0.createTime) == fd }
            } else {
                source = finishedList
            }
            var l: [PaicarListItem] = []
            var i = 0
            while i < source.count {
                let day = PaicarStyle.dayOf(source[i].createTime)
                var end = i + 1
                while end < source.count && PaicarStyle.dayOf(source[end].createTime) == day { end += 1 }
                // 通过"查看更多"加载出来的日期分组：上方加静态日期标识"以下是 YYYY-MM-DD"
                //（首次进入显示的最新一天不加，用户能直接看到内容）
                if moreLoadedDays.contains(day) {
                    l.append(.dateLabel(day))
                }
                for k in i..<end { l.append(.dispatch(source[k])) }
                i = end
            }
            // 最底部始终是"点击查看更多"按钮（可继续点），到底显示"没有更多了"
            l.append(.hint(true))
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

    /// 批量结单可结单列表：只显示已分配(004)
    private var batchDispatches: [PaicarDispatchOrder] {
        dispatches.filter { $0.statusCode == "004" }
    }

    private func setShowAll() {
        showFinished = false
        showBatch = false
        batchSelected.removeAll()
        filterFinishedDay = nil
        if !loading && applies.isEmpty && dispatches.isEmpty {
            // 切回"全部"且数据为空时补加载，避免空列表一直不刷新
            load()
        }
    }

    private func setShowFinished(_ v: Bool) {
        showFinished = v
        // 切 tab 时退出批量结单 tab
        showBatch = false
        batchSelected.removeAll()
        filterFinishedDay = nil
        if v {
            loadFinished()
        } else if !loading && applies.isEmpty && dispatches.isEmpty {
            // 切回"全部"且数据为空时补加载，避免空列表一直不刷新
            load()
        }
    }

    /// 进入批量结单 tab：清勾选 + 静默刷新已分配（有更新用新的，失败保留旧数据不报错）
    private func setShowBatch(_ v: Bool) {
        showBatch = v
        showFinished = false
        filterFinishedDay = nil
        batchSelected.removeAll()
        if v {
            refreshDispatchesSilently()
        }
    }

    /// 静默刷新已分配列表：成功且有数据才覆盖 dispatches；失败/空保留旧数据（用户要求"没更新显示之前的"）
    private func refreshDispatchesSilently() {
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                let raw = try await PaicarApi.dispatchOrderList(organId: p.organId, rolesId: p.rolesId, page: 1, perpage: 20)
                let list = raw.map { PaicarDispatchOrder.fromJson($0) }
                    .filter { $0.statusCode == "003" || $0.statusCode == "004" }
                    .sorted { $0.statusCode < $1.statusCode }
                if !list.isEmpty {
                    await MainActor.run {
                        dispatches = list
                        dispatchPage = 1
                    }
                }
            } catch {
                // 静默：保留旧数据
            }
        }
    }

    // MARK: 批量结单（A 方案）

    private func toggleBatchSelect(_ id: String) {
        if batchSelected.contains(id) {
            batchSelected.remove(id)
        } else {
            batchSelected.insert(id)
        }
    }

    private func startBatchFinish() {
        guard !batchSelected.isEmpty else {
            toastMsg = "请先勾选要结单的车"
            return
        }
        let selected = dispatches.filter { batchSelected.contains($0.id) }
        guard !selected.isEmpty else {
            toastMsg = "勾选的车已不在当前列表"
            return
        }
        batchOrders = selected
        batchSelected.removeAll()
        showBatchFinish = true
    }

    private func load(showLoading: Bool = true) {
        if showLoading { loading = true }
        error = ""
        authError = false
        // UI 级硬超时兜底：即使网络层极端异常，16 秒内必结束转圈并显示错误，不再无限转圈
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
            guard self.loading else { return }
            self.loading = false
            self.error = "加载超时（网络无响应），请检查网络后重试"
        }
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                // 两个列表接口互相独立，改为并行请求，加快首次加载
                // （PaicarApi 每请求独立 ephemeral 会话 + NSURLConnection，并行无死锁风险）
                async let a = PaicarApi.applyOrderList(organId: p.organId, rolesId: p.rolesId)
                async let d = PaicarApi.dispatchOrderList(organId: p.organId, rolesId: p.rolesId, page: 1, perpage: 20)
                let (rawApplies, rawDispatch) = try await (a, d)
                dispatchPage = 1
                applies = rawApplies.map { PaicarApplyOrder.fromJson($0) }
                    .filter { $0.statusCode == "000" || $0.statusCode == "001" }
                    .sorted { $0.statusCode < $1.statusCode }
                let filteredDispatch = rawDispatch.map { PaicarDispatchOrder.fromJson($0) }
                    .filter { $0.statusCode == "003" || $0.statusCode == "004" }
                    .sorted { $0.statusCode < $1.statusCode }
                dispatches = filteredDispatch
                // 用过滤后条数判断是否还有下一页：接口原始返回满 20 条但过滤后
                // 不足 20 时不再误判"还有更多"，避免显示无效的"下滑查看更多"
                hasMoreDispatch = filteredDispatch.count >= 20
                loading = false
            } catch PaicarError.authExpired {
                loading = false
                // token 失效（被顶号/过期）不再静默置空：明确提示用户重新登录，
                // 否则表现为"刚打开完全没数据"，只有退出重登才恢复
                authError = true
                error = "登录已失效，请重新登录"
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
                // 用过滤后条数判断：本页过滤后不足 20 即到底（与 load() 口径一致；
                // 空页时 more.count=0<20 同样会置 false，无需额外空页计数兜底）
                if more.count < 20 { hasMoreDispatch = false }
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
                moreLoadedDays.removeAll()
                lastPageOldestDay = ""
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
                // 与"全部"页一致：token 失效不再静默空，明确提示重新登录
                authError = true
                error = "登录已失效，请重新登录"
            } catch let err {
                loadingFinished = false
                error = (err as? PaicarError)?.errorDescription ?? err.localizedDescription
            }
        }
    }

    private func fetchFinishedPage(p: PaicarProfile) async throws {
        if exhausted {
            return
        }
        let raw = try await PaicarApi.dispatchOrderList(organId: p.organId, rolesId: p.rolesId, page: finishedPage + 1, perpage: 20)
        finishedPage += 1
        for e in raw {
            let o = PaicarDispatchOrder.fromJson(e)
            if o.statusCode == "999" { finishedPool.append(o) }
        }
        // 记录本页最旧单的日期（接口按创建时间倒序）：供"查看更多"判断是否已翻过目标日
        if let last = raw.last {
            let d = PaicarStyle.dayOf(PaicarDispatchOrder.fromJson(last).createTime)
            if !d.isEmpty { lastPageOldestDay = d }
        }
        // 服务器返回不满一页 = 真到底（不再人为设置 50 页上限截断历史数据）
        if raw.count < 20 { exhausted = true }
    }

    private func loadFinishedForDate(_ day: String) {
        finishedPool.removeAll()
        finishedPage = 0
        exhausted = false
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                // 翻到找到目标日为止（服务器数据有限，翻完即 exhausted，不会死循环）
                while finishedPool.contains(where: { PaicarStyle.dayOf($0.createTime) == day }) == false && !exhausted {
                    try await fetchFinishedPage(p: p)
                }
            } catch {}
        }
    }

    /// 继续翻页加载前一天（点击"查看更多"触发，一次最多加载一天）
    private func loadMoreFinished() {
        if loadingMoreFinished || !hasMoreFinished || loadingFinished || !showFinished { return }
        loadingMoreFinished = true
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                var guardCount = 0
                var found = false
                // 每天都有已结单 → 翻到找到目标日为止（不再限制 5 页）；
                // 200 页上限仅防接口异常死循环，正常靠"找到/翻过目标日/服务器到底"三个条件自然退出
                while !exhausted && guardCount < 200 {
                    guardCount += 1
                    try await fetchFinishedPage(p: p)
                    let dayList = finishedPool.filter { PaicarStyle.dayOf($0.createTime) == finishedCursor }
                    if !dayList.isEmpty {
                        // 找到目标日的 999 单：显示该天并记录为"查看更多加载的日期"，光标前推一天
                        moreLoadedDays.insert(finishedCursor)
                        finishedList.append(contentsOf: dayList)
                        finishedCursor = PaicarStyle.addDays(finishedCursor, -1)
                        found = true
                        break
                    }
                    // 已翻到日期早于目标日的页 → 目标日已全部翻完且无单 → 到底，不再继续翻更早
                    if !lastPageOldestDay.isEmpty && lastPageOldestDay < finishedCursor { break }
                    if exhausted { break }
                }
                if !found {
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

    // MARK: 提示条

    private func moreHint(isLast: Bool) -> some View {
        let canMore = loadingMore || loadingMoreFinished ? false : (showFinished ? hasMoreFinished : hasMoreDispatch)
        let text: String = {
            if loadingMore || loadingMoreFinished { return "加载中…" }
            if !canMore && isLast {
                return showFinished ? "没有更多了" : "当前还有 \(applies.count + dispatches.count) 部车未结单"
            }
            if !canMore { return "查看更多" }
            // 已结单/全部页底部按钮统一"点击查看更多"：
            // 加载出来的日期用独立的静态"以下是 YYYY-MM-DD"标识（dateLabel），按钮本身始终显示"点击查看更多"
            return "点击查看更多"
        }()
        return Button {
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

    /// 静态日期标识："以下是 YYYY-MM-DD"（点"查看更多"加载出来的日期分组上方显示，不可点）
    private func dateLabel(_ day: String) -> some View {
        Text("以下是 \(day)")
            .font(.system(size: 13))
            .foregroundColor(Color.gray)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 2)
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

    /// 批量结单模式卡片：车牌 + 邮路（邮路去固定前缀、短名括号），整卡已分配绿色白字
    private func batchCard(_ o: PaicarDispatchOrder) -> some View {
        let route = o.applyList.first.map { PaicarStyle.routeLine($0.routeName, $0.routeShortName) } ?? ""
        let customers = o.applyList.map { $0.customerName }.filter { !$0.isEmpty }
        // 三排信息字号统一 12 加粗白字：第一排「车型 - 司机 - 车牌」（用「-」连接）；
        // 第二排邮路；第三排客户名（原派车单号改为客户）
        let line1 = [o.specs, o.driverName, o.carNo].filter { !$0.isEmpty }.joined(separator: " - ")
        return HStack(spacing: 0) {
            Image(systemName: batchSelected.contains(o.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .padding(.leading, 14)
                .padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(line1.isEmpty ? o.orderNumber : line1)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                if !route.isEmpty {
                    Text(route)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                if !customers.isEmpty {
                    Text(customers.joined(separator: "、"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Spacer(minLength: 8)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(PaicarStyle.statusColor(o.statusCode)))
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
                    Text(c).font(.system(size: 15, weight: .bold)).foregroundColor(.white).monospacedDigit()
                }
                if !o.createName.isEmpty {
                    Text("\(o.createName) \(o.createTime) 创建派车").font(.system(size: 15, weight: .bold)).foregroundColor(.white).monospacedDigit()
                }
                if !o.receiveName.isEmpty {
                    Text("\(o.receiveName) \(o.receiveTime) 分配车辆").font(.system(size: 15, weight: .bold)).foregroundColor(.white).monospacedDigit()
                }
                if showFinished {
                    Text("车辆 \(o.specs) · 装载 \(o.loadingNum) 件 · 装载率 \(PaicarStyle.volRate(o))%")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
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
            toastMsg = "没有可撤回的待派车申请单"
            return
        }
        Task {
            do {
                // 一次列表查询拿到本营业部全部申请单，只取 000/001（不逐个查状态，避免为已分配/待分配/已结单白跑请求）
                // 用 load() 而不是缓存：刚进模块还没加载过列表时 profile 为 nil，
                // 直接用缓存会误报"未登录"导致一键撤回不可用
                let p = try await PaicarProfileHolder.load()
                let all = try await PaicarApi.applyOrderList(organId: p.organId, rolesId: p.rolesId)
                var sts: [String: String] = [:]
                for item in all {
                    // 与列表页 fromJson 同口径：id/statusCode 服务端可能是数字类型，
                    // 直接 as? String 会得 nil 导致"没有可撤回的申请单"，必须用兼容解析 s()
                    let id = s(item, "id")
                    if !id.isEmpty { sts[id] = s(item, "statusCode") }
                }
                // 交集：本地一键创建记录中仍为 001（待派车）的 = 真正可撤回
                let recallable = ids.filter { sts[$0] == "001" }
                // 000（未进入待派车/可编辑申请单）：保留本地记录，待转入 001 后再撤
                let kept = ids.filter { sts[$0] == "000" }
                // 本地记录中已进入派车/结单流程（非 000/001）或已不存在的 → 自动移出
                let stale = ids.filter { sts[$0] != "000" && sts[$0] != "001" }
                if !stale.isEmpty { PaicarApi.saveQuickIds(recallable + kept) }
                if recallable.isEmpty {
                    toastMsg = "没有可撤回的待派车申请单（未进入待派车的申请单可在申请单详情处理）"
                    return
                }
                var extra: [String] = []
                if !kept.isEmpty { extra.append("\(kept.count) 张未进入待派车状态暂不处理") }
                if !stale.isEmpty { extra.append("\(stale.count) 张已进入派车/结单流程将自动移出") }
                let msg = extra.isEmpty
                    ? "将删除 \(recallable.count) 张待派车申请单，确定？"
                    : "将删除 \(recallable.count) 张待派车申请单，\(extra.joined(separator: "，"))，确定？"
                let alert = UIAlertController(title: "确认一键撤回？", message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.addAction(UIAlertAction(title: "确认撤回", style: .destructive) { _ in
                    doQuickRecall(ids: recallable)
                })
                present(alert)
            } catch PaicarError.authExpired {
                toastMsg = "登录已失效，请重新登录"
            } catch {
                toastMsg = "获取申请单失败"
            }
        }
    }

    private func doQuickRecall(ids: [String]) {
        Task {
            var ok = 0
            var skipped = 0
            var fail = 0
            var authFailed = false
            var remaining: [String] = []
            for id in ids {
                do {
                    if try await PaicarApi.quickRecall(id: id) { ok += 1 } else { skipped += 1 }
                } catch PaicarError.authExpired {
                    authFailed = true
                    break
                } catch {
                    fail += 1
                    remaining.append(id)
                }
            }
            if authFailed {
                toastMsg = "登录已失效，请重新登录"
                load()
                return
            }
            // 已成功删除、状态已变更被跳过的都不再是可撤回申请单 → 移出本地记录；失败保留供重试
            PaicarApi.saveQuickIds(remaining)
            var parts: [String] = []
            if ok > 0 { parts.append("已删除 \(ok) 张待派车申请单") }
            if skipped > 0 { parts.append("\(skipped) 张状态已变更，跳过") }
            if fail > 0 { parts.append("\(fail) 张失败") }
            toastMsg = parts.isEmpty ? "没有可撤回的待派车申请单" : parts.joined(separator: "，")
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

enum PaicarListItem: Hashable {
    case apply(PaicarApplyOrder)
    case dispatch(PaicarDispatchOrder)
    case hint(Bool)
    case dateLabel(String)   // 静态日期标识："以下是 YYYY-MM-DD"（不可点，仅提示新加载分组的日期）

    func hash(into hasher: inout Hasher) {
        switch self {
        case .apply(let o): hasher.combine("a"); hasher.combine(o.id)
        case .dispatch(let o): hasher.combine("d"); hasher.combine(o.id)
        case .hint(let last): hasher.combine("h"); hasher.combine(last)
        case .dateLabel(let s): hasher.combine("dl"); hasher.combine(s)
        }
    }
}
