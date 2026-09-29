import SwiftUI
import UIKit
import UniformTypeIdentifiers

class ImportDelegate: NSObject, UIDocumentPickerDelegate {
    static let shared = ImportDelegate()
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        InternalHarImporter.importHar(from: url)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }
}

struct InternalTraceNode: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let desc: String
    let province: String
    let city: String
    let orgName: String
    let orgCode: String
}

struct InternalMailResult: Identifiable {
    let id = UUID()
    let mailNum: String
    var traces: [InternalTraceNode]
    var weight: String
    var fee: String
    var destProvince: String
    var destCity: String
    var error: String?
    var isDuplicate: Bool = false
}

enum InternalResultTab: String, CaseIterable, Identifiable {
    case success, failed, duplicate
    var id: String { rawValue }
}

enum InternalTrackParsing {
    static func isValidMailNum(_ digits: String) -> Bool {
        guard digits.count == 13 else { return false }
        guard let first = digits.first else { return false }
        return first == "1" || first == "8" || first == "9"
    }
    static func parseInput(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var valid: [String] = []
        for token in tokens {
            var digits = ""; var segments: [String] = []
            for ch in token {
                if let ascii = ch.asciiValue, (48...57).contains(ascii) { digits.append(ch) }
                else if !digits.isEmpty { segments.append(digits); digits = "" }
            }
            if !digits.isEmpty { segments.append(digits) }
            for seg in segments {
                if seg.count == 13, isValidMailNum(seg) { valid.append(seg) }
                else if seg.count > 14 {
                    for i in 0...(seg.count - 13) {
                        let s = seg.index(seg.startIndex, offsetBy: i)
                        let e = seg.index(s, offsetBy: 13)
                        let sub = String(seg[s..<e])
                        if let first = sub.first, first == "1" || first == "8" || first == "9" { valid.append(sub); break }
                    }
                }
            }
        }
        return valid
    }
}

final class InternalAsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()
    init(value: Int) { self.count = value }
    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if count > 0 { count -= 1; lock.unlock(); cont.resume() }
            else { waiters.append(cont); lock.unlock() }
        }
    }
    func signal() {
        lock.lock()
        if !waiters.isEmpty { let w = waiters.removeFirst(); lock.unlock(); w.resume() }
        else { count += 1; lock.unlock() }
    }
}

private final class InternalTicker {
    private var task: Task<Void, Never>?
    func start(interval: TimeInterval = 0.1, _ block: @escaping () -> Void) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await MainActor.run { block() }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}

final class InternalQueryEngine: ObservableObject {
    @Published var inputText = ""
    @Published var isQuerying = false
    @Published var total = 0
    @Published var completed = 0
    @Published var elapsedSeconds: Double = 0
    @Published var results: [InternalMailResult] = []
    @Published var concurrency = 2
    // 🆕 服务端次数限制标记：触发后停止剩余查询，不再浪费请求
    @Published var rateLimited = false
    // 🆕 登录会话失效标记：HAR 过期（工号退出登录），触发后停止查询并弹窗提示
    @Published var sessionExpired = false
    private var currentTask: Task<Void, Never>?
    private let ticker = InternalTicker()

    var successResults: [InternalMailResult] { results.filter { $0.error == nil && !$0.isDuplicate } }
    var failedResults: [InternalMailResult] { results.filter { $0.error != nil } }
    var duplicateResults: [InternalMailResult] { results.filter { $0.isDuplicate } }

    func start() {
        guard !isQuerying else { return }
        // 🆕 每次查询前清除 token 缓存：导入新 HAR 后天然立即生效（不再依赖 resetToken 调用时机），
        // 同时避免复用过期 token；批次内仍由 tokenTask 合并为 1 个 xmGetToken 请求，不额外耗请求
        NetworkManager.shared.resetToken()
        let nums = InternalTrackParsing.parseInput(inputText)
        guard !nums.isEmpty else { return }
        let startDate = Date()
        total = nums.count; completed = 0; results = []; isQuerying = true
        rateLimited = false
        sessionExpired = false
        currentTask = Task { [weak self] in await self?.run(nums: nums, start: startDate) }
        ticker.start { [weak self] in self?.elapsedSeconds = Date().timeIntervalSince(startDate) }
    }
    func cancel() {
        currentTask?.cancel(); currentTask = nil; ticker.stop(); isQuerying = false; total = 0; elapsedSeconds = 0
        rateLimited = false
        sessionExpired = false
    }

    @MainActor
    private func run(nums: [String], start: Date) async {
        defer {
            if !Task.isCancelled { isQuerying = false; ticker.stop(); elapsedSeconds = Date().timeIntervalSince(start) }
        }
        let semaphore = InternalAsyncSemaphore(value: concurrency)
        var collected: [Int: InternalMailResult] = [:]
        await withTaskGroup(of: (Int, InternalMailResult).self) { group in
            for (index, num) in nums.enumerated() {
                if Task.isCancelled { break }
                group.addTask {
                    await semaphore.wait()
                    if Task.isCancelled {
                        await semaphore.signal()
                        return (index, InternalMailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "已取消"))
                    }
                    // 🆕 已触发服务端次数限制：剩余单号不再发请求，直接标记停止
                    if self.rateLimited {
                        await semaphore.signal()
                        return (index, InternalMailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "已停止（服务端次数限制）"))
                    }
                    // 🆕 登录会话已失效：剩余单号不再发请求
                    if self.sessionExpired {
                        await semaphore.signal()
                        return (index, InternalMailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "已停止（会话失效）"))
                    }
                    do {
                        let json = try await NetworkManager.shared.query(mailNo: num)
                        await semaphore.signal()
                        // 🆕 检测服务端限次：达到最大次数时标记，剩余查询立即停止
                        if let msg = json["msg"] as? String, msg.contains("次数") || msg.contains("限制") {
                            self.rateLimited = true
                        }
                        return (index, self.parseResult(num, json: json))
                    } catch let e as SessionExpiredError {
                        // 🆕 会话失效：标记并停止剩余查询，弹窗提示重新导入 HAR
                        await semaphore.signal()
                        self.sessionExpired = true
                        return (index, InternalMailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "会话失效：\(e.message)"))
                    } catch {
                        do {
                            let json = try await NetworkManager.shared.query(mailNo: num)
                            await semaphore.signal()
                            if let msg = json["msg"] as? String, msg.contains("次数") || msg.contains("限制") {
                                self.rateLimited = true
                            }
                            return (index, self.parseResult(num, json: json))
                        } catch let e2 as SessionExpiredError {
                            await semaphore.signal()
                            self.sessionExpired = true
                            return (index, InternalMailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "会话失效：\(e2.message)"))
                        } catch {
                            await semaphore.signal()
                            return (index, InternalMailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "查询失败"))
                        }
                    }
                }
            }
            for await (index, result) in group {
                collected[index] = result
                completed = collected.count
                var ordered = (0..<nums.count).compactMap { collected[$0] }
                var seen2 = Set<String>()
                for i in ordered.indices {
                    if seen2.contains(ordered[i].mailNum) { ordered[i].isDuplicate = true }
                    else { seen2.insert(ordered[i].mailNum) }
                }
                results = ordered
            }
        }
    }

    private func parseResult(_ mailNo: String, json: [String: Any]) -> InternalMailResult {
        var list: [[String: Any]]?
        if let data = json["data"] as? [String: Any], let l = data["data"] as? [[String: Any]] { list = l }
        else if let l = json["data"] as? [[String: Any]] { list = l }
        guard let l = list, !l.isEmpty else {
            // 🆕 显示服务端返回的 msg（如"已达到最大次数限制!"）；msg 为空时退回显示原始 JSON 诊断
            let serverMsg = (json["msg"] as? String) ?? ""
            var detail = serverMsg
            if detail.isEmpty {
                let raw = (try? JSONSerialization.data(withJSONObject: json, options: []))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                detail = String(raw.prefix(200))
            }
            let label = detail.isEmpty ? "" : "  [服务端] \(detail)"
            return InternalMailResult(mailNum: mailNo, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "无物流信息\(label)")
        }
        var items: [InternalTraceNode] = []; var weight = ""; var fee = ""
        for item in l { flatten(item, into: &items, weight: &weight, fee: &fee) }
        items.sort { $0.time > $1.time }
        var destCity = ""
        for t in items {
            var s = t.desc
            if let range = s.range(of: "发往:") { s = String(s[range.upperBound...]) }
            else if let range = s.range(of: "发往：") { s = String(s[range.upperBound...]) }
            else { continue }
            while s.first == " " || s.first == "　" { s.removeFirst() }
            if let end = s.firstIndex(of: " ") { s = String(s[..<end]) }
            destCity = s; break
        }
        let destProvince = InternalAreaUtil.shared.getProvinceByCity(destCity)
        return InternalMailResult(mailNum: mailNo, traces: items, weight: weight, fee: fee, destProvince: destProvince, destCity: destCity, error: nil)
    }

    private func flatten(_ node: [String: Any], into items: inout [InternalTraceNode], weight: inout String, fee: inout String) {
        let time = node["opTime"] as? String ?? ""
        let title = node["opName"] as? String ?? ""
        var desc = ""
        if let org = node["opOrgName"] as? String, !org.isEmpty { desc = org }
        if let opDesc = node["opDesc"] as? String, !opDesc.isEmpty { if !desc.isEmpty { desc += " - " }; desc += opDesc }
        if let operatorName = node["operatorName"] as? String, !operatorName.isEmpty { if !desc.isEmpty { desc += " - " }; desc += "操作员: \(operatorName)" }
        let province = node["opOrgProvName"] as? String ?? ""
        let city = node["opOrgCity"] as? String ?? ""
        let orgName = node["opOrgName"] as? String ?? ""
        let orgCode = node["opOrgCode"] as? String ?? ""
        if weight.isEmpty, let opDesc = node["opDesc"] as? String, let range = opDesc.range(of: "重量:") {
            let s = String(opDesc[range.upperBound...])
            if let match = s.range(of: #"\d+\.?\d*\s*[gGkKmM]+"#, options: .regularExpression) { weight = String(s[match]) }
        }
        if fee.isEmpty, let opDesc = node["opDesc"] as? String, let range = opDesc.range(of: "基本资费:") {
            let s = String(opDesc[range.upperBound...])
            if let match = s.range(of: #"\d+\.?\d*\s*元"#, options: .regularExpression) { fee = String(s[match]) }
        }
        if !time.isEmpty || !title.isEmpty {
            items.append(InternalTraceNode(time: time, title: title, desc: desc, province: province, city: city, orgName: orgName, orgCode: orgCode))
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children { flatten(child, into: &items, weight: &weight, fee: &fee) }
        }
    }
}

struct InternalView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var keyboardVisible = false
    @StateObject private var engine = InternalQueryEngine()
    @State private var selectedTab: InternalResultTab = .success
    @State private var selectedResult: InternalMailResult?
    // 🆕 会话失效弹窗
    @State private var showSessionExpiredAlert = false
    @State private var showNoHarAlert = false

    var body: some View {
        VStack(spacing: 0) {
            inputSection
            if engine.isQuerying { progressBar }
            if engine.isQuerying || !engine.results.isEmpty { statsAndTabs }
            resultContent
        }
        .navigationTitle("内网查询")
        .onAppear {
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in keyboardVisible = true }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in keyboardVisible = false }
            EdgeSwipeBack.disableSystemPop()
        }
        .navigationBarBackButtonHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .ignoresSafeArea(.keyboard)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 🆕 返回：导航栏左侧（状态栏正下方）
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if keyboardVisible {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } else {
                        presentationMode.wrappedValue.dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .foregroundColor(.blue)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
            // 🆕 清空：导航栏左侧
            ToolbarItem(placement: .navigationBarLeading) {
                Button { engine.inputText = ""; engine.results = []; engine.total = 0 } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.blue)
                }
                .disabled(engine.inputText.isEmpty)
            }
            // 🆕 导入：导航栏右侧（状态栏正下方、右上角）
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
                    picker.delegate = ImportDelegate.shared
                    picker.allowsMultipleSelection = false
                    UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
                } label: {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.body)
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(item: $selectedResult) { r in InternalDetailSheet(result: r) }
        // 🆕 会话失效：弹窗提示重新导入 HAR
        .onChange(of: engine.sessionExpired) { expired in
            if expired { showSessionExpiredAlert = true }
        }
        .alert("登录会话已失效", isPresented: $showSessionExpiredAlert) {
            Button("知道了", role: .cancel) {}
        }
        .alert("请先导入文件", isPresented: $showNoHarAlert) {
            Button("知道了", role: .cancel) {}
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 🆕 输入框放在最上面：顶部贴住导航栏下方
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                TextEditor(text: $engine.inputText)
                    .font(.system(size: 20))
                    .padding(8)
                    .disabled(engine.isQuerying)
            }
            .frame(height: 250)

            // 🆕 提示/状态文字：移到输入框下方
            HStack(spacing: 8) {
                if engine.rateLimited {
                    Text("已达服务端查询次数限制，剩余已停止").foregroundColor(.red).fontWeight(.medium)
                } else if engine.total > 0 {
                    if engine.isQuerying { Text("\(engine.total) 个正在查询") }
                    else { Text("已查询 \(engine.total) 个") }
                    Text("用时 \(formattedElapsed)")
                } else if engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("单号（每行一个，自动过滤中文）")
                } else {
                    let nums = InternalTrackParsing.parseInput(engine.inputText)
                    Text("\(nums.count) 个准备查询")
                }
            }
            .font(.subheadline).foregroundColor(.secondary)
            .padding(.top, 6)
            .padding(.bottom, 8)

            HStack(spacing: 12) {
                // 🆕 并发数调节（查询中锁定，1~20，默认 2），位置与外网查询一致
                HStack(spacing: 4) {
                    Button {
                        if engine.concurrency > 1 { engine.concurrency -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(engine.isQuerying ? Color.gray.opacity(0.4) : Color.blue)
                    }
                    .disabled(engine.isQuerying)

                    Text("\(engine.concurrency)并发")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 44)

                    Button {
                        if engine.concurrency < 20 { engine.concurrency += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(engine.isQuerying ? Color.gray.opacity(0.4) : Color.blue)
                    }
                    .disabled(engine.isQuerying)
                }

                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    if !InternalHarConfig.shared.isConfigured {
                        showNoHarAlert = true
                        return
                    }
                    engine.start()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("查询")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(engine.isQuerying ? Color.gray.opacity(0.3) : (engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue))
                    .foregroundColor(engine.isQuerying ? .gray : .white).cornerRadius(10)
                }
                .disabled(engine.isQuerying || engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if engine.isQuerying {
                    Button { engine.cancel() } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 12, height: 12)
                            Text("停止")
                        }
                        .font(.headline)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.red).cornerRadius(10)
                    }
                }
            }
        }
        .padding(.horizontal).padding(.top, 0).padding(.bottom, 12)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(engine.completed), total: Double(max(engine.total, 1))).tint(.blue)
            Text("\(engine.completed) / \(engine.total)").font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal).padding(.bottom, 6)
    }

    private var statsAndTabs: some View {
        VStack(spacing: 8) {
            HStack {
                Text("成功 \(engine.successResults.count)，失败 \(engine.failedResults.count)，重复 \(engine.duplicateResults.count)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button {
                    exportXLSX()
                } label: {
                    Text("导出数据").font(.caption).foregroundColor(.blue)
                }
                .disabled(engine.results.isEmpty)
            }.padding(.horizontal)
            Picker("结果", selection: $selectedTab) {
                Text("成功 (\(engine.successResults.count))").tag(InternalResultTab.success)
                Text("失败 (\(engine.failedResults.count))").tag(InternalResultTab.failed)
                Text("重复 (\(engine.duplicateResults.count))").tag(InternalResultTab.duplicate)
            }
            .pickerStyle(.segmented).padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private var currentList: [InternalMailResult] {
        switch selectedTab {
        case .success: return engine.successResults
        case .failed: return engine.failedResults
        case .duplicate: return engine.duplicateResults
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if currentList.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Spacer()
            }
        } else {
            List {
                ForEach(currentList) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.mailNum).font(.system(size: 16, weight: .medium))
                        if let err = r.error {
                            Text(err).font(.system(size: 14)).foregroundColor(.secondary)
                        } else if !r.traces.isEmpty {
                            Text(r.traces[0].time).font(.caption).foregroundColor(.blue)
                            Text(r.traces[0].title).font(.subheadline).fontWeight(.medium)
                            if !r.traces[0].desc.isEmpty {
                                Text(r.traces[0].desc).font(.system(size: 14)).foregroundColor(.primary).lineLimit(nil)
                            }
                            Text("\(r.traces.count)条")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 与外网一致：行内 onTapGesture 不与 List 的 simultaneousGesture 冲突，点击可进详情
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        selectedResult = r
                    }
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
        }
    }

    private func exportXLSX() {
        let valid = engine.results.filter { !$0.traces.isEmpty }
        guard !valid.isEmpty else { return }
        var rows: [[String]] = []
        for r in valid {
            let last = r.traces[0]
            var acceptTrace: InternalTraceNode? = nil
            for t in r.traces { if t.title.contains("收寄") { acceptTrace = t; break } }
            if acceptTrace == nil && r.traces.count > 1 { acceptTrace = r.traces[r.traces.count - 2] }
            rows.append([
                r.mailNum, last.time, last.title, r.weight, r.fee,
                last.province, last.city, last.orgName, last.orgCode,
                r.destCity, r.destProvince,
                acceptTrace?.province ?? "", acceptTrace?.city ?? "", acceptTrace?.orgName ?? ""
            ])
        }
        let data = InternalXLSXExporter.export(rows: rows)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(InternalXLSXExporter.defaultFileName() + ".xlsx")
        do {
            try data.write(to: url)
        } catch {
            return
        }
        DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = UIApplication.shared.windows.first
                    popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                UIApplication.shared.windows.first?.rootViewController?.present(activityVC, animated: true)
            }
    }

    private var formattedElapsed: String { String(format: "%.1f秒", engine.elapsedSeconds) }
}

struct InternalDetailSheet: View {
    let result: InternalMailResult
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(result.mailNum).font(.headline).frame(maxWidth: .infinity, alignment: .center)
                    if !result.destCity.isEmpty {
                        Text("寄达\(result.destProvince)\(result.destCity)").font(.subheadline).frame(maxWidth: .infinity, alignment: .center)
                    }
                    if !result.weight.isEmpty || !result.fee.isEmpty {
                        Text("重量\(result.weight)  资费\(result.fee)").font(.subheadline).frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                if !result.traces.isEmpty {
                    Section("全部轨迹（\(result.traces.count)条）") {
                        ForEach(result.traces) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.time).font(.caption).foregroundColor(.blue)
                                Text(item.title).font(.subheadline).fontWeight(.medium)
                                if !item.desc.isEmpty {
                                    Text(item.desc).font(.caption).foregroundColor(.primary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("物流详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { dismiss() }.foregroundColor(.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.foregroundColor(.blue)
                }
            }
        }
    }
}


extension UIApplication {
    var isKeyboardVisible: Bool {
        windows.first(where: { $0.isKeyWindow })?.subviews.contains(where: { $0.description.contains("UIRemoteKeyboardWindow") }) ?? false
    }
}
