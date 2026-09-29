import SwiftUI
import UIKit

// MARK: - 远程图片加载（兼容 iOS 14）

struct PaicarRemoteImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable()
            } else {
                Color.gray.opacity(0.2)
                    .overlay(ProgressView())
                    .onAppear(perform: load)
            }
        }
    }

    private func load() {
        guard image == nil, let url = url else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = img
                }
            }
        }.resume()
    }
}

// MARK: - 派车单详情（对应 PaicarDetailActivity）

struct PaicarDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    let orderId: String

    @State private var order: PaicarDispatchOrder?
    @State private var loading = true
    @State private var error = ""
    @State private var toastMsg: String?
    @State private var showPreview = false
    @State private var previewIndex = 0
    @State private var acting = false

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var cardBg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : .white }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：返回 + "详情"居中（右侧无按钮补占位）
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text("详情")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 10) {
                    if loading {
                        ProgressView().padding(.top, 160)
                    } else if !error.isEmpty {
                        Text(error).font(.system(size: 14)).foregroundColor(fg).padding(.top, 160)
                        Button("重试") { load() }
                            .font(.system(size: 14)).foregroundColor(blue).padding(.top, 12)
                    } else if let o = order {
                        headCard(o)
                        infoTiles(o)
                        if !o.images.isEmpty {
                            photosGrid(o)
                        }
                    }
                }
                .padding(16)
            }
            .background(pageBg)

            if let o = order, !loading, error.isEmpty {
                actionBar(o)
            }
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            load()
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
        .fullScreenCover(isPresented: $showPreview) {
            if let imgs = order?.images {
                PaicarImagePreview(images: imgs, start: previewIndex, dark: isDark)
            }
        }
    }

    // MARK: 头部卡片

    private func headCard(_ o: PaicarDispatchOrder) -> some View {
        VStack(spacing: 6) {
            Text(o.carNo.isEmpty ? "" : o.carNo)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(fg)
            Text("状态：\(o.statusName)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(PaicarStyle.statusColor(o.statusCode))
            if let a = o.applyList.first(where: { !$0.createName.isEmpty }) {
                Text("申请派车：\(a.createName) \(a.createTime)")
                    .font(.system(size: 12)).foregroundColor(fg)
            }
            if !o.createName.isEmpty {
                Text("创建派车：\(o.createName) \(o.createTime)")
                    .font(.system(size: 12)).foregroundColor(fg)
            }
            if !o.receiveName.isEmpty {
                Text("分配车辆：\(o.receiveName) \(o.receiveTime)")
                    .font(.system(size: 12)).foregroundColor(fg)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardBg))
    }

    // MARK: 信息块

    private func infoTiles(_ o: PaicarDispatchOrder) -> some View {
        VStack(spacing: 0) {
            if let a = o.applyList.first(where: { !$0.routeName.isEmpty }) {
                infoTile("邮路", PaicarStyle.routeLine(a.routeName, a.routeShortName))
            }
            infoTile("车辆规格", o.specs)
            infoTile("派车单", o.orderNumber)
            infoTile("司机", "\(o.driverName) \(o.driverPhone)")
            infoTile("到达时间", o.receiveTime)
            if !o.leaveTime.isEmpty { infoTile("发车时间", o.leaveTime) }
            if !o.loadingNum.isEmpty { infoTile("装载件数", "\(o.loadingNum) 件") }
            if PaicarStyle.volRate(o) > 0 { infoTile("容积利用率", "\(PaicarStyle.volRate(o))%") }
            if !o.finishDesc.isEmpty { infoTile("结单备注", o.finishDesc) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardBg))
    }

    private func infoTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12)).foregroundColor(fg)
                .padding(.top, 8)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 14)).foregroundColor(fg)
        }
    }

    // MARK: 照片网格

    private func photosGrid(_ o: PaicarDispatchOrder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("装车照片")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(fg)
                .frame(maxWidth: .infinity)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Array(o.images.enumerated()), id: \.element.id) { idx, img in
                    Button {
                        previewIndex = idx
                        showPreview = true
                    } label: {
                        PaicarRemoteImage(url: URL(string: PaicarApi.imageUrl(img.imageFile)))
                            .frame(height: 72)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
    }

    // MARK: 底部操作

    private func actionBar(_ o: PaicarDispatchOrder) -> some View {
        let p = PaicarProfileHolder.profile
        let canArrange = o.statusCode == "004" && (p?.rolesId == "1" || p?.rolesId == "7")
        let canRecall = (o.statusCode == "001" || o.statusCode == "003") && (p == nil || o.createId == p!.id || p!.rolesId == "1" || p!.rolesId == "7")
        let canFinish = o.statusCode == "004"

        return HStack(spacing: 8) {
            if canArrange {
                actionBtn("分配车辆", Color(red: 0.08, green: 0.28, blue: 0.75)) {
                    NotificationCenter.default.post(name: .paicarOpenArrange, object: nil, userInfo: ["orderId": o.id])
                }
            }
            if canFinish {
                actionBtn("拍照结单", Color(red: 1.0, green: 0.60, blue: 0.0)) {
                    NotificationCenter.default.post(name: .paicarOpenFinish, object: nil, userInfo: ["orderId": o.id, "mode": ""])
                }
            }
            if o.statusCode == "999" {
                actionBtn("上传照片", Color(red: 1.0, green: 0.60, blue: 0.0)) {
                    NotificationCenter.default.post(name: .paicarOpenFinish, object: nil, userInfo: ["orderId": o.id, "mode": "photos"])
                }
            }
            if canRecall {
                actionBtn("撤销派车", Color.red) {
                    confirmRecall(o)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(pageBg)
    }

    private func actionBtn(_ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(color))
        }
    }

    private func confirmRecall(_ o: PaicarDispatchOrder) {
        let alert = UIAlertController(title: "撤销派车", message: "确认撤销派车单 \(o.orderNumber)？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认", style: .destructive) { _ in
            acting = true
            Task {
                do {
                    _ = try await PaicarApi.dispatchAction(id: o.id, action: "recall")
                    acting = false
                    toastMsg = "操作成功"
                    PaicarFlags.dispatchDirty = true
                    load()
                } catch PaicarError.authExpired {
                    acting = false
                } catch {
                    acting = false
                    toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
                }
            }
        })
        present(alert)
    }

    private func load() {
        loading = true
        error = ""
        Task {
            do {
                let d = try await PaicarApi.dispatchOrderDetail(id: orderId)
                var orderMap: [String: Any] = [:]
                if let o = d["order"] as? [String: Any] { orderMap = o }
                if orderMap["applyList"] == nil, let l = d["applyList"] as? [Any] { orderMap["applyList"] = l }
                if orderMap["images"] == nil, let l = d["imageList"] as? [Any] { orderMap["images"] = l }
                order = PaicarDispatchOrder.fromJson(orderMap)
                loading = false
            } catch PaicarError.authExpired {
                loading = false
            } catch let err {
                loading = false
                error = (err as? PaicarError)?.errorDescription ?? err.localizedDescription
            }
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

// MARK: - 照片全屏预览（左右滑动、下滑缩小、点外部关闭）

struct PaicarImagePreview: View {
    let images: [PaicarImage]
    @State var start: Int
    let dark: Bool
    @Environment(\.presentationMode) private var presentationMode
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $start) {
                ForEach(Array(images.enumerated()), id: \.element.id) { idx, img in
                    PaicarRemoteImage(url: URL(string: PaicarApi.imageUrl(img.imageFile)))
                        .scaledToFit()
                        .tag(idx)
                        .padding(.horizontal, 20)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .scaleEffect(1 - min(dragOffset / 800, 0.4))
            .opacity(1 - min(dragOffset / 500, 0.6))
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if v.translation.height > 0 { dragOffset = v.translation.height }
                    }
                    .onEnded { v in
                        if v.translation.height > 100 {
                            withAnimation(.easeOut(duration: 0.15)) {
                                dragOffset = 200
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                presentationMode.wrappedValue.dismiss()
                            }
                        } else {
                            withAnimation { dragOffset = 0 }
                        }
                    }
            )
            .onTapGesture {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

// MARK: - 申请单详情（对应 PaicarApplyDetailActivity）

struct PaicarApplyDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    let orderId: String

    @State private var order: PaicarApplyOrder?
    @State private var loading = true
    @State private var acting = false
    @State private var toastMsg: String?

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var cardBg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : .white }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    private var isCreator: Bool {
        let p = PaicarProfileHolder.profile
        return p != nil && (order?.createName == p!.name || p!.rolesId == "1" || p!.rolesId == "7")
    }
    private var canEdit: Bool { order?.statusCode == "000" }
    private var canRecall: Bool {
        guard let o = order else { return false }
        let c = o.statusCode
        return c != "002" && c != "000" && c != "003" && c != "004" && c != "999" && isCreator
    }
    private var canDelete: Bool {
        guard let o = order else { return false }
        return (o.statusCode == "000" || o.statusCode.isEmpty ||
                (o.statusCode != "001" && o.statusCode != "003" && o.statusCode != "004" && o.statusCode != "999")) && isCreator
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text("详情")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 10) {
                    if loading {
                        ProgressView().padding(.top, 160)
                    } else if let o = order {
                        headCard(o)
                        infoRows(o)
                    }
                }
                .padding(16)
            }
            .background(pageBg)

            if let o = order, !loading, canEdit || canRecall || canDelete {
                HStack(spacing: 8) {
                    if canDelete {
                        actionBtn("删除申请单", red: true) {
                            confirmDelete(o)
                        }
                    }
                    if canRecall {
                        actionBtn("撤回申请", red: true) {
                            confirmRecall(o)
                        }
                    }
                    if canEdit {
                        actionBtn("编辑申请单", red: false) {
                            NotificationCenter.default.post(name: .paicarOpenEditApply, object: nil, userInfo: ["orderId": orderId])
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(pageBg)
            }
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            if order == nil { refresh() }
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
    }

    private func headCard(_ o: PaicarApplyOrder) -> some View {
        VStack(spacing: 6) {
            Text(o.statusName.isEmpty ? "待派车" : o.statusName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(blue))
            Text(o.orderNumber)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(fg)
            Text("创建：\(o.createName) \(o.createTime)")
                .font(.system(size: 12))
                .foregroundColor(fg)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardBg))
    }

    private func infoRows(_ o: PaicarApplyOrder) -> some View {
        VStack(spacing: 0) {
            infoRow("客户", o.customerName)
            infoRow("邮路", PaicarStyle.stripRoute(o.routeName.isEmpty ? o.routeShortName : o.routeName))
            infoRow("联系人", "\(o.liaisonName) \(o.liaisonPhone)")
            infoRow("件数", o.number)
            infoRow("体积", o.volume)
            infoRow("申请车型", o.carSpecs)
            infoRow("到达时间", o.arrivalTime)
            infoRow("创建机构", o.organName)
            if !o.remarks.isEmpty { infoRow("备注", o.remarks) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardBg))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundColor(fg).padding(.top, 8)
            Text(value.isEmpty ? "-" : value).font(.system(size: 14)).foregroundColor(fg)
        }
    }

    private func actionBtn(_ label: String, red: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(red ? .red : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(red ? Color.clear : blue))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(red ? Color.red : Color.clear, lineWidth: 1))
        }
    }

    private func confirmDelete(_ o: PaicarApplyOrder) {
        let alert = UIAlertController(title: "删除申请单", message: "确认删除申请单？删除后不可恢复。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认删除", style: .destructive) { _ in
            acting = true
            Task {
                do {
                    _ = try await PaicarApi.applyOrderAction(id: orderId, action: "delete")
                    presentationMode.wrappedValue.dismiss()
                } catch PaicarError.authExpired {
                    acting = false
                } catch {
                    acting = false
                    toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
                }
            }
        })
        present(alert)
    }

    private func confirmRecall(_ o: PaicarApplyOrder) {
        let alert = UIAlertController(title: "撤回申请", message: "确认撤回申请单 \(o.orderNumber)？撤回后状态变为待提交。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认", style: .destructive) { _ in
            acting = true
            Task {
                do {
                    _ = try await PaicarApi.applyOrderAction(id: orderId, action: "recall")
                    acting = false
                    toastMsg = "已撤回，状态变为待提交"
                    refresh()
                } catch PaicarError.authExpired {
                    acting = false
                } catch {
                    acting = false
                    toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
                }
            }
        })
        present(alert)
    }

    private func refresh() {
        loading = true
        Task {
            do {
                let d = try await PaicarApi.applyOrderDetail(id: orderId)
                order = PaicarApplyOrder.fromJson(d)
                loading = false
            } catch PaicarError.authExpired {
                loading = false
            } catch {
                loading = false
            }
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
