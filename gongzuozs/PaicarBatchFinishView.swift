import SwiftUI
import PhotosUI
import UIKit

// MARK: - 批量结单（A 方案：勾选多部已分配车 → 逐单拍照 → 一键全部提交）
// 每单最多 4 张；提交时逐单串行：查最新状态(非004跳过) → 并行上传该单照片 → finish
// 失败不中断，最后统一弹结果；失败单可单独重试；已成功的单绝不重复提交
struct PaicarBatchFinishView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    let orders: [PaicarDispatchOrder]

    @State private var current = 0
    @State private var drafts: [[DraftImage]]
    @State private var results: [String: (ok: Bool, msg: String)] = [:]
    @State private var submitting = false
    @State private var showResult = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var toastMsg: String?
    @State private var retryDone = false

    private let minImages = 4
    private let maxImages = 4

    // 崩溃修复：drafts 在 init 就按订单数初始化，杜绝 body 首次渲染先于 onAppear 时
    // drafts[current] 数组越界（Swift 越界 = SIGTRAP 闪退，与 10-07 崩溃报告一致）
    init(orders: [PaicarDispatchOrder]) {
        self.orders = orders
        _drafts = State(initialValue: orders.map { _ in [DraftImage]() })
    }

    // 安全访问：body 已做空列表保护，此处 indices 兜底防 current 异常越界
    private var currentOrder: PaicarDispatchOrder {
        orders.indices.contains(current) ? orders[current] : orders[0]
    }
    private var currentDrafts: [DraftImage] {
        drafts.indices.contains(current) ? drafts[current] : []
    }
    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var orange: Color { Color(red: 1.0, green: 0.60, blue: 0.0) }

    var body: some View {
        // 空订单保护：没有可结单车辆时显示空态而非越界崩溃
        // （ViewBuilder 不支持 return 提前返回，必须 if/else 分支）
        if orders.isEmpty {
            emptyState
        } else {
            mainBody
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "car.2")
                .font(.system(size: 44))
                .foregroundColor(fg.opacity(0.4))
            Text("没有可结单的已分配车辆")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(fg)
            Button("返回") {
                presentationMode.wrappedValue.dismiss()
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(orange)
            .cornerRadius(10)
            .padding(.horizontal, 40)
            Spacer()
        }
        .background(pageBg)
        .navigationBarHidden(true)
    }

    private var mainBody: some View {
        VStack(spacing: 0) {
            // 顶栏：返回 + 居中标题（批量结单）
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
                Text("批量结单（\(orders.count) 部）")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 0) {
                    // 进度 + 车牌邮路
                    Text("第 \(current + 1) / \(orders.count) 部")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(fg)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)

                    // 每部车信息三行（对齐单独结单/列表卡片）：第一排「车型 - 司机 - 车牌」，第二排邮路，第三排客户名；居中
                    let o = currentOrder
                    let line1 = [o.specs, o.driverName, o.carNo].filter { !$0.isEmpty }.joined(separator: " - ")
                    let info1 = line1.isEmpty ? o.orderNumber : line1
                    let route = o.applyList.first.map { a -> String in
                        let r = a.routeName.contains("-") ? String(a.routeName.split(separator: "-", maxSplits: 1)[1]) : a.routeName
                        return r + (a.routeShortName.isEmpty ? "" : "(\(a.routeShortName))")
                    } ?? ""
                    let customers = o.applyList.map { $0.customerName }.filter { !$0.isEmpty }.joined(separator: "、")
                    VStack(spacing: 4) {
                        Text(info1)
                            .frame(maxWidth: .infinity)
                        if !route.isEmpty {
                            Text(route)
                                .frame(maxWidth: .infinity)
                        }
                        if !customers.isEmpty {
                            Text(customers)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(fg)
                    .padding(.vertical, 8)

                    // 相册(左) | 标题(中) | 拍照(右)
                    HStack(spacing: 0) {
                        iconBtn("photo.on.rectangle", "相册") {
                            showPhotoPicker = true
                        }
                        .disabled(currentDrafts.count >= maxImages)
                        .opacity(currentDrafts.count >= maxImages ? 0.4 : 1)
                        Text("装车照片·共需要 \(minImages) 张")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(fg)
                            .frame(maxWidth: .infinity)
                        iconBtn("camera.fill", "拍照") {
                            showCamera = true
                        }
                        .disabled(currentDrafts.count >= maxImages || !UIImagePickerController.isSourceTypeAvailable(.camera))
                        .opacity(currentDrafts.count >= maxImages || !UIImagePickerController.isSourceTypeAvailable(.camera) ? 0.4 : 1)
                    }
                    .padding(.horizontal, 16)

                    imagesGrid

                    // 底部按钮：非最后一部 = 下一部；最后一部 = 提交全部。
                    // 当前单照片未传满 minImages 张时禁用，必须每部传满才能继续（不允许跳过）
                    Button {
                        if current < orders.count - 1 {
                            current += 1
                        } else {
                            submitAll()
                        }
                    } label: {
                        Text(submitting ? "提交中…" : (current < orders.count - 1 ? "下一部" : "提交全部"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(orange)
                            .cornerRadius(10)
                    }
                    .disabled(submitting || currentDrafts.count < minImages)
                    .opacity(submitting || currentDrafts.count < minImages ? 0.5 : 1)
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 4)

                    // 照片未传满时的提示（原「跳过剩余」位置，不可点击）：
                    // 非最后一部提示先传满才能点击下一部；最后一部提示先传满才能提交全部
                    if currentDrafts.count < minImages {
                        Text(current < orders.count - 1 ? "请先上传四张照片，才能点击下一部" : "请先上传四张照片，才能提交全部")
                            .font(.system(size: 13))
                            .foregroundColor(fg.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
            .background(pageBg)
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            if drafts.isEmpty {
                drafts = orders.map { _ in [] }
            }
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
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(maxCount: maxImages - currentDrafts.count) { images in
                for img in images {
                    if drafts[current].count >= maxImages { break }
                    if let data = img.jpegData(compressionQuality: 0.85) {
                        let fileName = "img_\(Int(Date().timeIntervalSince1970 * 1000))_\(drafts[current].count).jpg"
                        drafts[current].append(DraftImage(fileName: fileName, data: data, uploaded: false))
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                if drafts[current].count >= maxImages { return }
                if let data = image.jpegData(compressionQuality: 0.85) {
                    let fileName = "img_\(Int(Date().timeIntervalSince1970 * 1000))_\(drafts[current].count).jpg"
                    drafts[current].append(DraftImage(fileName: fileName, data: data, uploaded: false))
                }
            }
        }
        // 结果弹窗（失败单可单独重试）
        .sheet(isPresented: $showResult) {
            resultView
        }
    }

    // MARK: 结果视图（成功/失败/跳过 + 失败单重试）

    private var resultView: some View {
        let okCount = results.values.filter { $0.ok }.count
        let failList = orders.enumerated().filter { results[$0.element.id]?.ok == false }
        return VStack(spacing: 0) {
            Text("结单结果")
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 18)
            Text("成功 \(okCount) / \(orders.count) 部")
                .font(.system(size: 14))
                .foregroundColor(fg)
                .padding(.top, 6)
            if failList.isEmpty {
                Text("全部结单成功")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.30, green: 0.68, blue: 0.31))
                    .padding(.top, 10)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(failList, id: \.offset) { idx, o in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(idx + 1). \(o.orderNumber)\(o.carNo.isEmpty ? "" : " \(o.carNo)")")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(fg)
                                    Text(results[o.id]?.msg ?? "")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.red)
                                }
                                Spacer()
                                Button("重试") {
                                    retryUnit(o.id)
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)
                                .disabled(submitting)
                            }
                            .padding(10)
                            .background(isDark ? Color(red: 0.14, green: 0.14, blue: 0.14) : Color(white: 0.94))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            Button {
                // 关闭结果；有成功则通知列表刷新并退出批量页
                if okCount > 0 {
                    PaicarFlags.finishedDirty = true
                    PaicarFlags.dispatchDirty = true
                    NotificationCenter.default.post(name: .paicarBackToAllList, object: nil)
                }
                showResult = false
                presentationMode.wrappedValue.dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(orange)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(pageBg)
    }

    // MARK: 重试单个失败单

    private func retryUnit(_ id: String) {
        if submitting { return }
        guard let idx = orders.firstIndex(where: { $0.id == id }) else { return }
        submitting = true
        Task {
            var ok = false
            var msg = ""
            do {
                let detail = try await PaicarApi.dispatchOrderDetail(id: id)
                let st = detail["statusCode"] as? String ?? ""
                if st != "004" {
                    msg = "状态已变更(\(st.isEmpty ? "非已分配" : st))，可能已被他人处理"
                } else {
                    try await uploadImages(for: idx)
                    let leaveTime = nowTime()
                    let loadingNum = randomLoadingNum(for: orders[idx])
                    let fr = try await PaicarApi.finish(id: id, leaveTime: leaveTime, finishDesc: "", loadingNum: loadingNum)
                    if fr.ok {
                        ok = true
                        msg = "重试成功"
                    } else {
                        msg = fr.dataMap["msg"] as? String ?? "结单失败"
                    }
                }
            } catch PaicarError.authExpired {
                msg = "登录已失效"
            } catch {
                msg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
            results[id] = (ok, msg)
            submitting = false
            if ok {
                PaicarFlags.finishedDirty = true
                PaicarFlags.dispatchDirty = true
                retryDone = true
            }
        }
    }

    // MARK: 提交全部

    private func submitAll() {
        if submitting { return }
        submitting = true
        Task {
            var res: [String: (ok: Bool, msg: String)] = [:]
            // 一次性拿 profile 判断是否需要最少 4 张
            var needMin = true
            do {
                let p = try await PaicarProfileHolder.load()
                needMin = p.rolesId != "4"
            } catch {
                needMin = true
            }
            for (idx, order) in orders.enumerated() {
                let imgs = drafts[idx]
                if imgs.isEmpty {
                    res[order.id] = (false, "未拍照")
                    continue
                }
                if needMin && imgs.count < minImages {
                    res[order.id] = (false, "照片不足 \(imgs.count)/\(minImages) 张")
                    continue
                }
                do {
                    // 提交前查最新状态：防止已被他人结单/撤销/改分配
                    let detail = try await PaicarApi.dispatchOrderDetail(id: order.id)
                    let st = detail["statusCode"] as? String ?? ""
                    if st != "004" {
                        res[order.id] = (false, "状态已变更(\(st.isEmpty ? "非已分配" : st))，可能已被他人处理")
                        continue
                    }
                    // 并行上传该单所有未传照片
                    try await uploadImages(for: idx)
                    // finish（件数自动随机按车型、发车时间=当前、备注空）
                    let leaveTime = nowTime()
                    let loadingNum = randomLoadingNum(for: order)
                    let fr = try await PaicarApi.finish(id: order.id, leaveTime: leaveTime, finishDesc: "", loadingNum: loadingNum)
                    if fr.ok {
                        res[order.id] = (true, "结单成功")
                    } else {
                        res[order.id] = (false, fr.dataMap["msg"] as? String ?? "结单失败")
                    }
                } catch PaicarError.authExpired {
                    res[order.id] = (false, "登录已失效")
                    break
                } catch {
                    res[order.id] = (false, (error as? PaicarError)?.errorDescription ?? error.localizedDescription)
                }
            }
            results = res
            submitting = false
            showResult = true
        }
    }

    /// 并行上传第 idx 部所有未上传照片（对齐单笔结单 uploadAllImages 的判定：ret==200 即成功）
    private func uploadImages(for idx: Int) async throws {
        let pending = drafts[idx].enumerated().filter { !$0.element.uploaded }.map { (index: $0.offset, item: $0.element) }
        guard !pending.isEmpty else { return }
        var successIdx: [Int] = []
        var failed: [String] = []
        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for (i, d) in pending {
                group.addTask {
                    do {
                        _ = try await PaicarApi.uploadImage(fileData: d.data, fileName: d.fileName, extra: [("id", orders[idx].id)])
                        return (i, nil)
                    } catch let e {
                        return (i, (e as? PaicarError)?.errorDescription ?? e.localizedDescription)
                    }
                }
            }
            for try await (i, msg) in group {
                if msg == nil {
                    successIdx.append(i)
                } else {
                    failed.append("第 \(i + 1) 张：\(msg ?? "")")
                }
            }
        }
        var updated = drafts[idx]
        for i in successIdx {
            let d = updated[i]
            updated[i] = DraftImage(fileName: d.fileName, data: d.data, uploaded: true)
        }
        drafts[idx] = updated
        if !failed.isEmpty {
            throw PaicarError.api("照片上传失败：\n" + failed.joined(separator: "\n"))
        }
    }

    // MARK: 辅助

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func iconBtn(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 14))
            }
            .foregroundColor(fg)
            .padding(.vertical, 6)
        }
    }

    /// 车牌排最前，邮路只取"-"后面的内容（对齐单笔结单 routeLine）
    private func routeLine(_ o: PaicarDispatchOrder) -> String {
        let tail = o.applyList.first.map { a -> String in
            var t = a.routeName
            if let idx = t.firstIndex(of: "-") {
                t = String(t[t.index(after: idx)...])
            }
            if !a.routeShortName.isEmpty { t += "(\(a.routeShortName))" }
            return t
        } ?? ""
        return (o.carNo.isEmpty ? "" : o.carNo + " ") + tail
    }

    /// 随机装车件数（按车型，对齐单笔结单）
    private func randomLoadingNum(for o: PaicarDispatchOrder) -> String {
        let specsText = [o.specs] + o.applyList.map { $0.carSpecs }
        if specsText.contains(where: { $0.contains("9.6") }) {
            return "\(Int.random(in: 2789...2946))"
        } else if specsText.contains(where: { $0.contains("7.6") }) {
            return "\(Int.random(in: 1755...1888))"
        } else if specsText.contains(where: { $0.contains("5.3") }) {
            return "\(Int.random(in: 823...987))"
        }
        return ""
    }

    private func nowTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private var imagesGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Array(currentDrafts.enumerated()), id: \.offset) { idx, d in
                VStack(spacing: 2) {
                    if let img = UIImage(data: d.data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 80)
                            .clipped()
                            .cornerRadius(4)
                    }
                    Button {
                        if !d.uploaded {
                            drafts[current].remove(at: idx)
                        }
                    } label: {
                        Text(d.uploaded ? "已传 ✓" : "✕")
                            .font(.system(size: 10))
                            .foregroundColor(d.uploaded ? Color.green : Color.red)
                    }
                    .disabled(d.uploaded)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
