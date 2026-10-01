import SwiftUI
import UIKit

// MARK: - 申请单登记 / 编辑（对应 PaicarApplyEditActivity）

struct PaicarApplyEditView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    var postId: String?

    @State private var customerList: [PaicarCustomer] = []
    @State private var liaisonList: [PaicarLiaison] = []
    @State private var routeList: [PaicarRoute] = []
    @State private var specList: [PaicarCarSpec] = []
    @State private var selectedCustomerId = ""
    @State private var numText = ""
    @State private var arrivalTime = ""
    @State private var liaisonId = ""
    @State private var routeId = ""
    @State private var carSpecs = ""
    @State private var remarks = ""
    @State private var loading = true
    @State private var saving = false
    @State private var error = ""
    @State private var toastMsg: String?
    @State private var showCustomTime = false
    @State private var customDate = Date()

    private let quickTimes = ["08:00", "10:00", "16:00", "17:00", "18:00", "19:00", "20:00", "23:00"]
    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var inputBg: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.17) : Color(white: 0.96) }
    private var border: Color { isDark ? Color(white: 0.33) : Color(white: 0.8) }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }
    private var tileBg: Color { Color(white: 0.5).opacity(isDark ? 0.12 : 0.06) }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：← + 居中标题 + 右侧"提交"
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text(postId == nil ? "登记申请单" : "编辑申请单")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 0) {
                    if loading {
                        ProgressView().padding(.top, 160)
                    } else if !error.isEmpty {
                        Text(error).font(.system(size: 14)).foregroundColor(fg).padding(.top, 160)
                        Button("重试") { load() }
                            .font(.system(size: 14)).foregroundColor(blue).padding(.top, 12)
                    } else {
                        section("到达时间")
                        Button {
                            pickArrival()
                        } label: {
                            Text(arrivalTime.isEmpty ? "请选择时间 ▼" : arrivalTime)
                                .font(.system(size: 14))
                                .foregroundColor(arrivalTime.isEmpty ? Color(white: 0.55) : fg)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(inputBg)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                        }
                        .padding(.horizontal, 16)

                        section("装货点 / 客户")
                        dropdown(items: customerList.map { ($0.name, $0.id) }, selected: selectedCustomerId, hint: "请选择客户") { v in
                            selectedCustomerId = v
                            if let c = customerList.first(where: { $0.id == v }) { autoFillFromQuickCar(c) }
                        }
                        .padding(.horizontal, 16)

                        section("申请车型")
                        dropdown(items: specList.map { ($0.specs, $0.specs) }, selected: carSpecs, hint: "请选择车型") { v in
                            carSpecs = v
                            if v.contains("5.3") { numText = "1000" }
                            else if v.contains("7.6") { numText = "2500" }
                            else if v.contains("9.6") { numText = "3000" }
                        }
                        .padding(.horizontal, 16)

                        section("联系人")
                        dropdown(items: liaisonList.map { ($0.name, $0.id) }, selected: liaisonId, hint: "请选择联系人") { v in liaisonId = v }

                        section("邮路名称")
                        dropdown(items: routeList.map { ($0.name, $0.id) }, selected: routeId, hint: "请选择邮路") { v in routeId = v }

                        section("件数")
                        TextField("请输入件数", text: $numText)
                            .keyboardType(.numberPad)
                            .font(.system(size: 14))
                            .foregroundColor(fg)
                            .accentColor(fg)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(inputBg)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                        .padding(.horizontal, 16)

                        section("备注")
                        TextField("选填", text: $remarks)
                            .font(.system(size: 14))
                            .foregroundColor(fg)
                            .accentColor(fg)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .frame(minHeight: 88)
                            .background(inputBg)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                            .padding(.horizontal, 16)

                        Button {
                            save()
                        } label: {
                            Text(saving ? "保存中…" : "保存")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(blue)
                                .cornerRadius(10)
                        }
                        .disabled(saving)
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(pageBg)
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            if customerList.isEmpty { load() }
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
        .sheet(isPresented: $showCustomTime) {
            CustomTimeSheet(initial: customDate) { date in
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                f.locale = Locale(identifier: "en_US_POSIX")
                arrivalTime = f.string(from: date)
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func dropdown(items: [(String, String)], selected: String, hint: String, onSelect: @escaping (String) -> Void) -> some View {
        let current = selected.isEmpty ? (hint + " ▼") : (items.first(where: { $0.1 == selected })?.0 ?? (hint + " ▼"))
        return Button {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            for item in items {
                alert.addAction(UIAlertAction(title: item.0, style: .default) { _ in
                    onSelect(item.1)
                })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            present(alert)
        } label: {
            Text(current)
                .font(.system(size: 14))
                .foregroundColor(selected.isEmpty ? Color(white: 0.55) : fg)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(inputBg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
        }
        .padding(.horizontal, 16)
    }

    private func pickArrival() {
        let alert = UIAlertController(title: "到达时间", message: nil, preferredStyle: .actionSheet)
        for t in quickTimes {
            alert.addAction(UIAlertAction(title: t, style: .default) { _ in
                arrivalTime = today() + " " + t
            })
        }
        alert.addAction(UIAlertAction(title: "自定义...", style: .default) { _ in
            customDate = Date()
            showCustomTime = true
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert)
    }

    private func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func autoFillFromQuickCar(_ c: PaicarCustomer) {
        let cars = PaicarApi.defaultQuickCars()
        guard let match = cars.first(where: { $0["customerName"] == c.name }) else { return }
        if numText.isEmpty, let n = match["number"] { numText = n }
        if liaisonId.isEmpty { liaisonId = match["liaisonId"] ?? "" }
        if routeId.isEmpty { routeId = match["routeId"] ?? "" }
        if carSpecs.isEmpty { carSpecs = match["carSpecs"] ?? "" }
        if arrivalTime.isEmpty || arrivalTime.hasSuffix(" 00:00") {
            arrivalTime = today() + " " + (match["hour"] ?? "20:00")
        }
    }

    private func load() {
        loading = true
        error = ""
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                async let c = PaicarApi.getCustomer(organId: p.organId)
                async let l = PaicarApi.getLiaison(organId: p.organId)
                async let r = PaicarApi.getRouteList(organId: p.organId)
                async let s = PaicarApi.getCarSpecs()
                let (customers, liaisons, routes, specs) = try await (c, l, r, s)
                customerList = customers.map { PaicarCustomer.fromJson($0) }
                liaisonList = liaisons.map { PaicarLiaison.fromJson($0) }
                routeList = routes.map { PaicarRoute.fromJson($0) }
                specList = specs.map { PaicarCarSpec.fromJson($0) }
                loading = false
                if let pid = postId {
                    let o = try await PaicarApi.applyOrderDetail(id: pid)
                    fill(o)
                }
            } catch PaicarError.authExpired {
                loading = false
            } catch let err {
                loading = false
                error = (err as? PaicarError)?.errorDescription ?? err.localizedDescription
            }
        }
    }

    /// 兼容服务端整数/字符串/"null" 字段解析（服务端 id/件数等常为整数，as? String 会解析失败导致回填为空）
    private func s(_ j: [String: Any], _ key: String) -> String {
        let v = j[key]
        let t = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (v as? NSNumber)?.stringValue
            ?? ""
        return t.lowercased() == "null" ? "" : t
    }

    private func fill(_ o: [String: Any]) {
        arrivalTime = s(o, "arrivalTime")
        liaisonId = s(o, "liaison_id")
        routeId = s(o, "route_id")
        carSpecs = s(o, "carSpecs")
        remarks = s(o, "remarks")     // 备注回填（之前遗漏，从未回填过）
        if let customers = o["customer"] as? [Any] {
            for e in customers {
                guard let c = e as? [String: Any] else { continue }
                let cid = s(c, "customer_id")
                if !cid.isEmpty {
                    selectedCustomerId = cid
                    numText = s(c, "number")
                }
            }
        }
    }

    private func save() {
        if saving { return }
        if selectedCustomerId.isEmpty { toastMsg = "请选择客户"; return }
        var totalNumber = 0
        var customerJson: [[String: Any]] = []
        for cid in [selectedCustomerId] {
            guard let c = customerList.first(where: { $0.id == cid }) else { continue }
            let num = Int(numText) ?? 0
            totalNumber += num
            customerJson.append([
                "id": cid,
                "customer_id": cid,
                "customerName": c.name,
                "number": numText,
                "shipment": 1,
            ])
        }
        if totalNumber < 1 { toastMsg = "请填写件数"; return }
        if arrivalTime.isEmpty || !arrivalTime.contains(" ") { toastMsg = "请填写到达时间"; return }
        if liaisonId.isEmpty { toastMsg = "请选择联系人"; return }
        if routeId.isEmpty { toastMsg = "请选择邮路名称"; return }
        if carSpecs.isEmpty { toastMsg = "请选择申请车型"; return }
        saving = true
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                let jsonData = try JSONSerialization.data(withJSONObject: customerJson)
                let json = String(data: jsonData, encoding: .utf8) ?? ""
                let r = try await PaicarApi.applyOrderSave(
                    id: postId, organId: p.organId,
                    customerListJson: json, arrivalTime: arrivalTime,
                    number: "\(totalNumber)", liaisonId: liaisonId,
                    routeId: routeId, carSpecs: carSpecs, remarks: remarks.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                saving = false
                if r.ok {
                    toastMsg = "保存成功"
                    // 通知列表页数据已变：返回派车单界面时自动重载
                    PaicarFlags.dispatchDirty = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        presentationMode.wrappedValue.dismiss()
                    }
                } else {
                    toastMsg = (r.dataMap["msg"] as? String) ?? "保存失败"
                }
            } catch {
                saving = false
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
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

// MARK: - 自定义时间选择

struct CustomTimeSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State var initial: Date
    let onPick: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("取消").font(.system(size: 15)).frame(width: 60, height: 44)
                }
                Spacer()
                Button {
                    onPick(initial)
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("确定").font(.system(size: 15, weight: .bold)).frame(width: 60, height: 44)
                }
            }
            .padding(.horizontal, 8)
            DatePicker("", selection: $initial, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.top, 8)
        }
        .padding(.top, 20)
    }
}

// MARK: - 分配车辆（对应 PaicarArrangeActivity）

struct PaicarArrangeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    let orderId: String

    @State private var order: PaicarDispatchOrder?
    @State private var carList: [PaicarFleetCar] = []
    @State private var driverList: [PaicarDriver] = []
    @State private var carNo = ""
    @State private var driverId = ""
    @State private var loading = true
    @State private var submitting = false
    @State private var toastMsg: String?

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var inputBg: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.17) : Color(white: 0.96) }
    private var border: Color { isDark ? Color(white: 0.33) : Color(white: 0.8) }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }
    private var chipBg: Color { isDark ? Color(white: 0.14) : Color(white: 0.9) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text("分配车辆")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 0) {
                    if loading {
                        ProgressView().padding(.top, 160)
                    } else if let o = order {
                        Text("派车单：\(o.orderNumber)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(fg)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        Text("车型：\(o.specs)")
                            .font(.system(size: 13))
                            .foregroundColor(Color(white: 0.5))
                            .padding(.top, 2)

                        section("选择车牌号")
                        searchRow(hint: "搜索车牌") { text in
                            loadCars(filter: text)
                        }
                        carsGrid
                        section("选择驾驶员")
                        searchRow(hint: "搜索姓名") { text in
                            loadDrivers(filter: text)
                        }
                        driversGrid

                        Button {
                            submit()
                        } label: {
                            Text("确认分配")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(blue)
                                .cornerRadius(10)
                        }
                        .disabled(submitting)
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(pageBg)
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            if order == nil { load() }
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

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func searchRow(hint: String, onSearch: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            TextField(hint, text: .constant(""))
                .font(.system(size: 14))
                .foregroundColor(fg)
                .accentColor(fg)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(inputBg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                .onSubmit { onSearch("") }
            Button {
                onSearch("")
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(fg)
                    .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    private var carsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(carList) { c in
                Button {
                    carNo = c.carNo
                } label: {
                    Text(c.carNo)
                        .font(.system(size: 13))
                        .foregroundColor(carNo == c.carNo ? .white : fg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(carNo == c.carNo ? blue : chipBg))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var driversGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
            ForEach(driverList) { d in
                Button {
                    driverId = d.id
                } label: {
                    Text("\(d.name) \(d.phone)")
                        .font(.system(size: 13))
                        .foregroundColor(driverId == d.id ? .white : fg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(driverId == d.id ? blue : chipBg))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func load() {
        loading = true
        Task {
            do {
                let d = try await PaicarApi.dispatchOrderDetail(id: orderId)
                var orderMap: [String: Any] = [:]
                if let o = d["order"] as? [String: Any] { orderMap = o }
                if orderMap["applyList"] == nil, let l = d["applyList"] as? [Any] { orderMap["applyList"] = l }
                if orderMap["images"] == nil, let l = d["imageList"] as? [Any] { orderMap["images"] = l }
                order = PaicarDispatchOrder.fromJson(orderMap)
                loading = false
                loadCars(filter: "")
                loadDrivers(filter: "")
            } catch {
                loading = false
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func loadCars(filter: String) {
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                var specsId = ""
                let specs = try await PaicarApi.getCarSpecs()
                for e in specs {
                    if ((e["specs"] as? String) ?? "") == order?.specs {
                        specsId = (e["id"] as? String) ?? ""
                        break
                    }
                }
                let raw = try await PaicarApi.getFleetCarList(organId: p.organId, specsId: specsId, carNo: filter)
                carList = raw.map { PaicarFleetCar.fromJson($0) }
            } catch {
                carList = []
            }
        }
    }

    private func loadDrivers(filter: String) {
        Task {
            do {
                let p = try await PaicarProfileHolder.load()
                let raw = try await PaicarApi.getDriver(organId: p.organId, name: filter)
                driverList = raw.map { PaicarDriver.fromJson($0) }
            } catch {
                driverList = []
            }
        }
    }

    private func submit() {
        if carNo.isEmpty { toastMsg = "请选择车牌号"; return }
        if driverId.isEmpty { toastMsg = "请选择驾驶员"; return }
        submitting = true
        Task {
            do {
                _ = try await PaicarApi.arrangeCar(id: orderId, carNo: carNo, driverId: driverId)
                submitting = false
                toastMsg = "分配成功"
                PaicarFlags.dispatchDirty = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                submitting = false
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
