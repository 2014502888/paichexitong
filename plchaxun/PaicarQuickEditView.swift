import SwiftUI
import UIKit

// MARK: - 快捷申请配置（对应 PaicarQuickEditActivity）

struct PaicarQuickEditView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    @State private var rows: [[String: String]] = []
    @State private var customerList: [PaicarCustomer] = []
    @State private var liaisonList: [PaicarLiaison] = []
    @State private var routeList: [PaicarRoute] = []
    @State private var specList: [PaicarCarSpec] = []
    @State private var loading = true
    @State private var saved = false
    @State private var toastMsg: String?
    @State private var toastError = false
    @State private var expanded: [Bool] = []

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var inputBg: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.17) : Color(white: 0.96) }
    private var border: Color { isDark ? Color(white: 0.33) : Color(white: 0.8) }
    private var tileBg: Color { Color(white: 0.5).opacity(isDark ? 0.12 : 0.06) }
    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }
    private var hintColor: Color { isDark ? Color(white: 0.6) : Color(white: 0.45) }

    var body: some View {
        VStack(spacing: 0) {
            // 抬头：两行（标题 + 括号副标题），扣除左右占位符后居中
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                VStack(spacing: 1) {
                    Text("申请配置")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(fg)
                    Text("（按配置批量创建派车单设置）")
                        .font(.system(size: 11))
                        .foregroundColor(hintColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Button("添加") { addRow() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(blue)
                    .padding(.trailing, 12)
                Button("保存") { save() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(blue)
                    .padding(.trailing, 16)
            }
            .frame(height: 56)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 0) {
                    if loading {
                        ProgressView().padding(.top, 120)
                    } else {
                        ForEach(rows.indices, id: \.self) { i in
                            rowCard(rows[i], index: i)
                        }
                        .padding(.horizontal, 16)

                        Color.clear.frame(height: 40)
                    }
                }
            }
            .background(pageBg)
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            if rows.isEmpty { load() }
        }
        .overlay(
            Group {
                if let msg = toastMsg {
                    PaicarToast(text: msg, dark: isDark, isError: toastError)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.toastMsg = nil
                            }
                        }
                }
            }
        )
    }

    // MARK: 行卡片

    private func rowCard(_ r: [String: String], index: Int) -> some View {
        let enabled = r["enabled"] == "1"
        let isExpanded = expanded.indices.contains(index) ? expanded[index] : true
        let showBody = enabled && isExpanded
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    toggleEnabled(index)
                } label: {
                    Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(enabled ? blue : Color(white: 0.55))
                }
                Text("第 \(index + 1) 部")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(fg)
                if !showBody {
                    // 折叠时：中间空白显示邮路，方便识别是哪个配置
                    Text(r["routeName"] ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(hintColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button {
                    toggleExpand(index)
                } label: {
                    Image(systemName: showBody ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(hintColor)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                Button {
                    confirmDelete(index)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundColor(.red)
                }
            }

            if showBody {
                pickRow("客户", value: r["customerName"] ?? "", hint: "选择客户") {
                    showPicker((index, "customer"))
                }
                HStack(spacing: 8) {
                    Text("件数").font(.system(size: 13)).foregroundColor(fg).frame(width: 56, alignment: .leading)
                    TextField("件数", text: Binding(
                        get: { rows[index]["number"] ?? "" },
                        set: { rows[index]["number"] = $0 }
                    ))
                    .keyboardType(.numberPad)
                    .font(.system(size: 13))
                    .foregroundColor(fg)
                    .accentColor(fg)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(inputBg)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
                    pickRow("车型", value: r["carSpecs"] ?? "", hint: "选择", compact: true) {
                        showPicker((index, "spec"))
                    }
                }
                pickRow("到达时间", value: r["hour"] ?? "", hint: "选择时间") {
                    showPicker((index, "hour"))
                }
                pickRow("联系人", value: r["liaisonName"] ?? "", hint: "选择联系人") {
                    showPicker((index, "liaison"))
                }
                pickRow("邮路", value: r["routeName"] ?? "", hint: "选择邮路") {
                    showPicker((index, "route"))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tileBg))
        .padding(.vertical, 4)
    }

    private func pickRow(_ label: String, value: String, hint: String, compact: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13)).foregroundColor(fg).frame(width: 56, alignment: .leading)
            Button(action: action) {
                Text(value.isEmpty ? hint + " ▼" : value)
                    .font(.system(size: 13))
                    .foregroundColor(value.isEmpty ? hintColor : fg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(inputBg)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            }
        }
    }

    private func field(_ hint: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(hint, text: text)
            .keyboardType(keyboard)
            .font(.system(size: 13))
            .foregroundColor(fg)
            .accentColor(fg)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .background(inputBg)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
    }

    // MARK: 动作

    private func toggleEnabled(_ idx: Int) {
        rows[idx]["enabled"] = rows[idx]["enabled"] == "1" ? "0" : "1"
        // 勾上启用时自动展开，避免刚启用的配置看不到内容
        if rows[idx]["enabled"] == "1", expanded.indices.contains(idx) {
            expanded[idx] = true
            rows[idx]["expanded"] = "1"
        }
    }

    private func toggleExpand(_ idx: Int) {
        guard expanded.indices.contains(idx) else { return }
        expanded[idx].toggle()
        // 同步折叠状态到行数据，保存后持久化
        rows[idx]["expanded"] = expanded[idx] ? "1" : "0"
    }

    private func confirmDelete(_ idx: Int) {
        let name = rows[idx]["customerName"]?.isEmpty == false ? rows[idx]["customerName"]! : "第 \(idx + 1) 部"
        let alert = UIAlertController(title: "删除该配置", message: "确认删除「\(name)」？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            rows.remove(at: idx)
            if expanded.indices.contains(idx) { expanded.remove(at: idx) }
        })
        present(alert)
    }

    private func addRow() {
        rows.append([
            "enabled": "1", "expanded": "1",
            "customerId": "", "customerName": "", "number": "", "carSpecs": "",
            "hour": "", "liaisonId": "", "liaisonName": "",
            "routeId": "", "routeName": "", "shipment": "0",
        ])
        expanded.append(true)
    }

    private func showPicker(_ target: (idx: Int, kind: String)) {
        let title: String
        var items: [(String, String)] = []
        var isTime = false
        switch target.kind {
        case "customer":
            title = "选择客户"
            items = customerList.map { ($0.name, $0.id) }
        case "spec":
            title = "选择车型"
            items = specList.map { ($0.specs, $0.specs) }
        case "liaison":
            title = "选择联系人"
            items = liaisonList.map { ($0.name, $0.id) }
        case "route":
            title = "选择邮路"
            items = routeList.map { ($0.name, $0.id) }
        case "hour":
            title = "到达时间"
            items = ["08:00", "10:00", "16:00", "17:00", "18:00", "19:00", "20:00", "23:00"].map { ($0, $0) }
            isTime = true
        default:
            return
        }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (name, id) in items {
            alert.addAction(UIAlertAction(title: name, style: .default) { _ in
                applyPick(target, kind: target.kind, name: name, id: id, isTime: isTime)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert)
    }

    private func applyPick(_ target: (idx: Int, kind: String), kind: String, name: String, id: String, isTime: Bool) {
        let i = target.idx
        guard rows.indices.contains(i) else { return }
        switch kind {
        case "customer":
            rows[i]["customerId"] = id
            rows[i]["customerName"] = name
        case "spec":
            rows[i]["carSpecs"] = name
            if name.contains("5.3") { rows[i]["number"] = "1000" }
            else if name.contains("7.6") { rows[i]["number"] = "2500" }
            else if name.contains("9.6") { rows[i]["number"] = "3000" }
        case "liaison":
            rows[i]["liaisonId"] = id
            rows[i]["liaisonName"] = name
        case "route":
            rows[i]["routeId"] = id
            rows[i]["routeName"] = name
        case "hour":
            rows[i]["hour"] = name
        default: break
        }
    }

    private func load() {
        loading = true
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
                let saved = PaicarApi.loadQuickCars()
                var loaded = saved.isEmpty ? defaultRows() : saved
                for i in loaded.indices {
                    if (loaded[i]["customerId"] ?? "").isEmpty,
                       let cname = loaded[i]["customerName"], !cname.isEmpty,
                       let c = customerList.first(where: { $0.name == cname }) {
                        loaded[i]["customerId"] = c.id
                    }
                }
                rows = loaded
                // 折叠状态持久化：有 expanded 字段按保存的恢复；旧数据无字段则按 enabled 推断（启用展开、未启用折叠）
                expanded = loaded.map { row in
                    if let e = row["expanded"] { return e == "1" }
                    return row["enabled"] == "1"
                }
            } catch PaicarError.authExpired {
                loading = false
            } catch {
                loading = false
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func defaultRows() -> [[String: String]] {
        return []
    }

    private func save() {
        // 校验启用行：必填项缺失则红色提示并阻止保存（未启用的行跳过）
        var incomplete: [String] = []
        for i in rows.indices {
            guard rows[i]["enabled"] == "1" else { continue }
            var missing: [String] = []
            if (rows[i]["customerName"] ?? "").isEmpty { missing.append("客户") }
            if (rows[i]["number"] ?? "").isEmpty { missing.append("件数") }
            if (rows[i]["carSpecs"] ?? "").isEmpty { missing.append("车型") }
            if (rows[i]["liaisonName"] ?? "").isEmpty { missing.append("联系人") }
            if (rows[i]["routeName"] ?? "").isEmpty { missing.append("邮路") }
            if (rows[i]["hour"] ?? "").isEmpty { missing.append("到达时间") }
            if !missing.isEmpty {
                incomplete.append("第 \(i + 1) 部缺：\(missing.joined(separator: "、"))")
            }
        }
        if !incomplete.isEmpty {
            toastError = true
            toastMsg = incomplete.joined(separator: "；")
            return
        }
        var cleaned = rows
        // 保存前同步折叠状态，重新进入时按保存的状态恢复
        for i in cleaned.indices where expanded.indices.contains(i) {
            cleaned[i]["expanded"] = expanded[i] ? "1" : "0"
        }
        for i in cleaned.indices {
            if cleaned[i]["enabled"] == "1" {
                let cname = cleaned[i]["customerName"] ?? ""
                if (cleaned[i]["customerId"] ?? "").isEmpty, !cname.isEmpty,
                   let c = customerList.first(where: { $0.name == cname }) {
                    cleaned[i]["customerId"] = c.id
                }
                let liaName = cleaned[i]["liaisonName"] ?? ""
                if let l = liaisonList.first(where: { $0.name == liaName }) {
                    cleaned[i]["liaisonId"] = l.id
                }
                let routeName = cleaned[i]["routeName"] ?? ""
                if let r = routeList.first(where: { $0.name == routeName }) {
                    cleaned[i]["routeId"] = r.id
                }
            }
        }
        PaicarApi.saveQuickCars(cleaned)
        saved = true
        toastError = false
        toastMsg = "配置已保存"
    }

    private func present(_ alert: UIAlertController) {
        guard let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first?.rootViewController else { return }
        var top = host
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
}
