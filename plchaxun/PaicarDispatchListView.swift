import SwiftUI

// MARK: - 鐘舵€佽壊涓庡伐鍏?
enum PaicarStyle {
    static func statusColor(_ code: String) -> Color {
        switch code {
        case "999": return Color(red: 0.61, green: 0.15, blue: 0.69)   // 绱?        case "004": return Color(red: 0.30, green: 0.68, blue: 0.31)   // 缁?        case "003": return Color(red: 1.0, green: 0.60, blue: 0.0)     // 姗?        case "001": return Color(red: 0.08, green: 0.28, blue: 0.75)   // 钃?        default: return Color.gray
        }
    }

    /// 閭矾鍘绘帀鍥哄畾鍓嶇紑"鏅嬫睙鍗楀尯鐢靛晢-" / "鍗楀尯鐢靛晢-"锛堝惈-锛?    static func stripRoute(_ name: String) -> String {
        if name.hasPrefix("鏅嬫睙鍗楀尯鐢靛晢-") { return String(name.dropFirst(7)) }
        if name.hasPrefix("鍗楀尯鐢靛晢-") { return String(name.dropFirst(5)) }
        return name
    }

    /// 閭矾 + 鐭悕鎷彿锛堝搴斿畨鍗?routes 鎷兼帴锛?    static func routeLine(_ name: String, _ short: String) -> String {
        stripRoute(name) + (short.isEmpty ? "" : "(\(short))")
    }

    /// 瀹圭Н鍒╃敤鐜?    static func volRate(_ o: PaicarDispatchOrder) -> Int {
        var sum = 0.0
        for a in o.applyList { sum += Double(a.volume) ?? 0 }
        let cap = Double(o.volume) ?? 0
        if cap <= 0 || sum <= 0 { return 0 }
        return Int((sum / cap * 100).rounded())
    }

    /// 鏃ユ湡 yyyy-MM-dd锛堝彇鍓?10 浣嶆牎楠岋級
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

// MARK: - 娲捐溅鍗曞垪琛紙瀵瑰簲 PaicarDispatchListFragment锛?
struct PaicarDispatchListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    // 鏁版嵁
    @State private var showFinished = false
    @State private var applies: [PaicarApplyOrder] = []
    @State private var dispatches: [PaicarDispatchOrder] = []
    @State private var finishedList: [PaicarDispatchOrder] = []
    @State private var finishedPool: [PaicarDispatchOrder] = []

    // 鍔犺浇鐘舵€?    @State private var loading = true
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
    @State private var finishedCursor = ""   // 褰撳墠宸叉樉绀哄埌鍝竴澶╋紙yyyy-MM-dd锛?    @State private var pushApplyId: String?
    @State private var pushDispatchId: String?
    @State private var didInitialLoad = false   // 棣栨杩涘叆蹇呭姞杞斤紙淇 onAppear 瀹堝崼 !loading 鎶婇娆″姞杞芥尅浣忓鑷存案杩滆浆鍦堬級

    // UI
    @State private var toastMsg: String?
    @State private var showMenu = false
    @State private var confirmApply = false
    @State private var confirmRecall = false
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var filterFinishedDay: String? = nil  // nil=褰撳ぉ, 鍚﹀垯绛涢€夐偅澶?    @State private var loadingFiltered = false
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
            // 鍏ㄩ儴 | 宸茬粨鍗?鍒囨崲
            HStack(spacing: 8) {
                tabBtn("鍏ㄩ儴", active: !showFinished) { setShowFinished(false) }
                tabBtn("宸茬粨鍗?, active: showFinished) { setShowFinished(true) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 鑳跺泭琛岋細寰呮淳杞?寰呭垎閰?宸插垎閰嶏紙鍙湪鍏ㄩ儴椤垫樉绀猴級
            if !showFinished && (!applies.isEmpty || !dispatches.isEmpty) {
                HStack(spacing: 6) {
                    capsule("寰呮淳杞?\(applies.count)閮?, blue)
                    capsule("寰呭垎閰?\(dispatches.filter { $0.statusCode == "003" }.count)閮?, Color(red: 1.0, green: 0.60, blue: 0.0))
                    capsule("宸插垎閰?\(dispatches.filter { $0.statusCode == "004" }.count)閮?, Color(red: 0.30, green: 0.68, blue: 0.31))
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
                Button("閲嶈瘯") { load() }
                    .font(.system(size: 14))
                    .foregroundColor(blue)
                    .padding(.top, 12)
                Spacer()
            } else if showFinished ? finishedList.isEmpty : (applies.isEmpty && dispatches.isEmpty) {
                Spacer()
                Text("馃摥").font(.system(size: 50))
                Text(showFinished ? "鏆傛棤宸茬粨鍗? : "鏆傛棤娲捐溅鍗?)
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
                            // 搴曢儴鍝ㄥ叺锛氭粴鍔ㄥ埌搴曡Е鍙戝姞杞斤紙閰嶅悎鍐峰嵈瀹炵幇涓€娆℃墜鍔挎渶澶氬姞杞戒竴澶╋級
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
        // "锛?鑿滃崟鐢卞閮ㄩ《鏍忔寔鏈夛紙PaicarDispatchListToolbar锛?        .confirmationDialog("鎿嶄綔", isPresented: $showMenu, titleVisibility: .visible) {
            Button("娲捐溅鐢宠") { newApply() }
            Button("涓€閿敵璇?) { quickApply() }
            Button("涓€閿挙鍥?) { quickRecall() }
            Button("鐢宠閰嶇疆") {
                NotificationCenter.default.post(name: .paicarOpenQuickEdit, object: nil)
            }
            Button("鍙栨秷", role: .cancel) {}
        }
        .sheet(isPresented: $showDatePicker) {
            VStack(spacing: 16) {
                Text("閫夋嫨鏃ユ湡").font(.system(size: 16, weight: .bold)).padding(.top, 16)
                DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 200)
                HStack(spacing: 20) {
                    Button("鍙栨秷") { showDatePicker = false }
                        .foregroundColor(.secondary)
                    Button("浠婂ぉ") {
                        selectedDate = Date()
                        filterFinishedDay = nil
                        showDatePicker = false
                    }
                    .foregroundColor(.blue)
                    Button("纭畾") {
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
                load()
            } else if PaicarFlags.dispatchDirty || PaicarFlags.finishedDirty {
                // 缁撳崟/鎾ゅ洖/鎻愪氦鎴愬姛鍚庡洖鍒板垪琛? 鑴忔爣璁拌〃绀烘暟鎹凡鍙? 蹇呴』閲嶈浇鍏ㄩ儴鍒楄〃;
                // 涔嬪墠鍙湪"鍒楄〃涓虹┖"鏃舵墠閲嶈浇, 瀵艰嚧鍒氱粨鍗曞畬杩樺崱鍦ㄦ棫鏁版嵁涓嶅埛鏂般€?                PaicarFlags.dispatchDirty = false
                PaicarFlags.finishedDirty = false
                if showFinished { loadFinished() }
                load()
            } else if !loading && applies.isEmpty && dispatches.isEmpty && finishedList.isEmpty {
                load()
            }
        }
        // 鍙崇紭宸︽粦杩斿洖锛氫粠宸茬粨鍗曞瓙tab鍒囧洖鍏ㄩ儴
        .onReceive(NotificationCenter.default.publisher(for: .paicarBackToAllList)) { _ in
            // 缁撳崟鎴愬姛鍚? 寮哄埗鍒囧洖"鍏ㄩ儴", 骞舵寜鑴忔爣璁板埛鏂板叏閮ㄥ垪琛?            // (鍏ㄩ儴鍙綊绫诲緟鍒嗛厤/寰呮淳杞?宸插垎閰? 鍒氱粨鐨勫崟鑷劧浠庡叏閮ㄦ秷澶?
            if showFinished { showFinished = false; filterFinishedDay = nil }
            if PaicarFlags.dispatchDirty || PaicarFlags.finishedDirty {
                PaicarFlags.dispatchDirty = false
                PaicarFlags.finishedDirty = false
                load()
            }
        }
        // 椤舵爮 + 鎸夐挳锛氬脊鍑烘搷浣滆彍鍗?        .onReceive(NotificationCenter.default.publisher(for: .paicarShowMenu)) { _ in
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
                for k in i..<end { l.append(.dispatch(source[k])) }
                l.append(.hint(true))
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

    // MARK: 鍔犺浇

    private func setShowFinished(_ v: Bool) {
        showFinished = v
        filterFinishedDay = nil
        if v { loadFinished() } else { /* renderList 鑷姩 */ }
    }

    private func load() {
        loading = true
        error = ""
        // UI 绾х‖瓒呮椂鍏滃簳锛氬嵆浣跨綉缁滃眰鏋佺寮傚父锛?6 绉掑唴蹇呯粨鏉熻浆鍦堝苟鏄剧ず閿欒锛屼笉鍐嶆棤闄愯浆鍦?        DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
            guard self.loading else { return }
            self.loading = false
            self.error = "鍔犺浇瓒呮椂锛堢綉缁滄棤鍝嶅簲锛夛紝璇锋鏌ョ綉缁滃悗閲嶈瘯"
        }
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                // 涓茶璇锋眰锛涜秴鏃跺凡涓嬫矇鍒?PaicarApi.perform锛堝洖璋冪増+寮哄埗鍙栨秷锛?5 绉掑唴蹇呭嚭缁撴灉锛屼笉鍐嶆棤闄愯浆鍦堬級
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

    /// 棣栨杩涘叆宸茬粨鍗曪細浠庣 1 椤电炕鍒版壘鍒?999 鐘舵€佸崟涓烘锛堟渶澶?50 椤碉級锛屽彇褰撳ぉ鏁版嵁
    private func loadFinished() {
        if loadingFinished { return }
        // 宸插姞杞借繃涓旀棤鏂扮粨鍗曪細鐩存帴鏄剧ず宸插姞杞芥暟鎹紝涓嶉噸澶嶈鏈嶅姟鍣?        if finishedLoadedOnce && !PaicarFlags.finishedDirty {
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

    /// 閫夋棩鏈熷悗锛氫粠鏈€鏂板線鍥炵炕椤碉紝鐩村埌鍔犺浇鍒扮洰鏍囨棩鏈?    private func loadFinishedForDate(_ day: String) {
        loadingFiltered = true
        finishedPool.removeAll()
        finishedPage = 0
        exhausted = false
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                while finishedPool.contains(where: { PaicarStyle.dayOf($0.createTime) == day }) == false && !exhausted && finishedPage < 50 {
                    try await fetchFinishedPage(p: p)
                }
                loadingFiltered = false
            } catch {
                loadingFiltered = false
            }
        }
    }

    /// 缁х画缈婚〉鍔犺浇鍓嶄竴澶╋紙涓€娆℃墜鍔挎渶澶氫竴澶╋級
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

    /// 婊氬姩鍒板簳瑙﹀彂锛氶厤鍚堝喎鍗达紝涓€娆℃墜鍔挎渶澶氬姞杞戒竴澶?    private func onReachBottom() {
        if finishedMoreCooldown {
            finishedMoreCooldown = false
            return
        }
        finishedMoreCooldown = true
        if showFinished { loadMoreFinished() } else { loadMoreDispatch() }
    }

    // MARK: 鎻愮ず鏉?
    private func moreHint(isLast: Bool) -> some View {
        let canMore = loadingMore || loadingMoreFinished ? false : (showFinished ? hasMoreFinished : hasMoreDispatch)
        let text: String = {
            if loadingMore || loadingMoreFinished { return "鍔犺浇涓€? }
            if !canMore && isLast {
                return showFinished ? "娌℃湁鏇村浜? : "褰撳墠杩樻湁 \(applies.count + dispatches.count) 閮ㄨ溅鏈粨鍗?
            }
            if !canMore { return "鏌ョ湅鏇村" }
            if canScrollDown { return "涓嬫粦鏌ョ湅鏇村" }
            return "鐐瑰嚮鏌ョ湅鏇村"
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

    // MARK: 鍗＄墖

    private func applyCard(_ o: PaicarApplyOrder) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                statusTag((o.statusName.isEmpty ? "寰呮淳杞? : o.statusName), PaicarStyle.statusColor(o.statusCode))
                Text(o.orderNumber).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text("瀹㈡埛 \(o.customerName)").font(.system(size: 13)).foregroundColor(.white)
                Text(PaicarStyle.routeLine(o.routeName.isEmpty ? o.routeShortName : o.routeName, o.liaisonName)).font(.system(size: 13)).foregroundColor(.white)
                Text("\(o.number)浠?路 \(o.carSpecs) 路 \(o.arrivalTime)")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.95))
                if !o.createTime.isEmpty {
                    Text("鐧昏 \(o.createName) \(o.createTime)")
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
            .map { "\($0.createName) \($0.createTime) 鐢宠娲捐溅" }
        return HStack(spacing: 0) {
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                statusTag(status, PaicarStyle.statusColor(o.statusCode), size: 15)
                if let first = o.applyList.first {
                    Text("鍒拌揪鏃堕棿:\(first.arrivalTime)").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !customers.isEmpty {
                    Text(customers.joined(separator: "銆?)).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !routes.isEmpty {
                    Text(routes.joined(separator: "銆?)).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.carNo.isEmpty || !o.driverName.isEmpty {
                    Text("\(o.carNo) \(o.driverName) \(o.driverPhone)")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.applyList.isEmpty {
                    Text("娲捐溅鍗曪細\(o.orderNumber)  杞﹁締瑙勬牸锛歕(o.specs)")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                ForEach(Array(creators.enumerated()), id: \.offset) { _, c in
                    Text(c).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.createName.isEmpty {
                    Text("\(o.createName) \(o.createTime) 鍒涘缓娲捐溅").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if !o.receiveName.isEmpty {
                    Text("\(o.receiveName) \(o.receiveTime) 鍒嗛厤杞﹁締").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                if showFinished {
                    Text("杞﹁締 \(o.specs) 路 瑁呰浇 \(o.loadingNum) 浠?路 瑁呰浇鐜?\(PaicarStyle.volRate(o))%")
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

    // MARK: 鑿滃崟鎿嶄綔

    private func newApply() {
        NotificationCenter.default.post(name: .paicarOpenNewApply, object: nil)
    }

    private func quickApply() {
        let cars = PaicarApi.loadQuickCars().filter { $0["enabled"] == "1" }
        if cars.isEmpty {
            toastMsg = "璇峰厛鍘婚厤缃晫闈㈠～鍐欑浉鍏充俊鎭?
            return
        }
        // 浜屾纭
        let alert = UIAlertController(title: "纭涓€閿敵璇凤紵", message: "灏嗘寜閰嶇疆鎵归噺鍒涘缓 \(cars.count) 寮犵敵璇峰崟", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "鍙栨秷", style: .cancel))
        alert.addAction(UIAlertAction(title: "纭鐢宠", style: .default) { _ in
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
                toastMsg = "鎴愬姛鍒涘缓 \(okCount)/\(cars.count) 寮犵敵璇峰崟"
            } else {
                toastMsg = "鍒涘缓瀹屾垚 \(okCount)/\(cars.count) 寮狅紝\(failLog.joined(separator: "\n"))"
            }
            load()
        }
    }

    private func quickRecall() {
        let ids = PaicarApi.loadQuickIds()
        if ids.isEmpty {
            toastMsg = "娌℃湁鍙挙鍥炵殑鐢宠鍗?
            return
        }
        let alert = UIAlertController(title: "纭涓€閿挙鍥烇紵", message: "灏嗘挙鍥炲苟鍒犻櫎鎵€鏈夊揩鎹风敵璇峰崟", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "鍙栨秷", style: .cancel))
        alert.addAction(UIAlertAction(title: "纭鎾ゅ洖", style: .destructive) { _ in
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
                toastMsg = "鐧诲綍宸插け鏁堬紝璇烽噸鏂扮櫥褰?
                load()
                return
            }
            PaicarApi.saveQuickIds([])
            if fail == 0 {
                toastMsg = "宸插叏閮ㄦ挙鍥炲苟鍒犻櫎"
            } else {
                toastMsg = "宸插鐞嗭紙\(fail) 寮犲け璐ワ級"
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
