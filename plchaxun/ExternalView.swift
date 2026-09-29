import SwiftUI
import UIKit

// MARK: - 主界面（按照原应用设计）
struct ExternalView: View {

    @Environment(\.presentationMode) var presentationMode
    @State private var keyboardVisible = false
    @StateObject private var engine = ExternalQueryEngine()

    @State private var selectedTab: ExternalResultTab = .success
    @State private var showingDetail: ExternalMailResult?

    // 🆕 多选复制相关状态
    @State private var selectionMode = false
    @State private var selectedMailNums = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            inputSection
            if engine.isQuerying { progressBar }
            if !engine.results.isEmpty || engine.isQuerying {
                statsAndTabs
            }
            resultContent
        }
        .navigationTitle("外网查询")
        .onAppear {
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in keyboardVisible = true }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in keyboardVisible = false }
            EdgeSwipeBack.disableSystemPop()
        }
        .navigationBarBackButtonHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .ignoresSafeArea(.keyboard)
        .navigationBarTitleDisplayMode(.inline)
        .textSelection(.disabled)
        .toolbar {
            // 🆕 返回：导航栏左侧（状态栏正下方，与内网查询一致）
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
                Button {
                    engine.inputText = ""
                    engine.total = 0          // 重置查询计数，标题回到输入提示态
                    engine.elapsedSeconds = 0
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.blue)
                }
                .disabled(engine.inputText.isEmpty)
            }
            // 🆕 多选/导出：导航栏右侧（状态栏正下方、右上角，与内网查询一致）
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectionMode {
                    Button("取消") {
                        selectionMode = false
                        selectedMailNums.removeAll()
                    }
                    .font(.body)
                    .foregroundColor(.blue)
                } else {
                    HStack(spacing: 16) {
                        // 🆕 仅成功标签页且有结果时显示多选按钮
                        if selectedTab == .success && !engine.successResults.isEmpty {
                            Button {
                                selectionMode = true
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.body)
                                    .foregroundColor(.blue)
                            }
                        }
                        Button {
                            exportXLSX()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                        .disabled(engine.results.isEmpty)
                    }
                }
            }
        }
        .sheet(item: $showingDetail) { result in
            NavigationView { ExternalTraceDetailView(result: result) }
        }
        .onChange(of: selectedTab) { _ in
            selectionMode = false
            selectedMailNums.removeAll()
        }
    }

    // MARK: - 输入区

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 🆕 输入框放在最上面：顶部贴住导航栏下方
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                TextEditor(text: $engine.inputText)
                    .font(.system(size: 20, design: .default))
                    .padding(8)
                    .disabled(engine.isQuerying)
            }
            .frame(height: 250)

            // 🆕 提示/状态文字：移到输入框下方
            HStack(spacing: 8) {
                // 查询中：XX 个正在查询；查询后：已查询数量；输入中：实时有效单号数；空输入：提示文字
                if engine.total > 0 {
                    if engine.isQuerying {
                        Text("\(engine.total) 个正在查询")
                    } else {
                        Text("已查询 \(engine.total) 个")
                    }
                    Text("用时 \(formattedElapsed)")
                } else if engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("单号（每行一个，自动过滤中文）")
                } else {
                    let info = ExternalTrackParsing.parseInputDetailed(engine.inputText)
                    Text("\(info.valid.count) 个准备查询")
                    if info.invalid > 0 {
                        Text("（\(info.invalid) 个非正确单号）")
                    }
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            // 查询 + 停止按钮
            HStack(spacing: 12) {
                // 🆕 并发数调节（查询中锁定，1~20，默认 8）
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

                // 查询按钮
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    engine.start()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .imageScale(.small)
                        Text("查询")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(engine.isQuerying ? Color.gray.opacity(0.3) : (engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue))
                    .foregroundColor(engine.isQuerying ? .gray : .white)
                    .cornerRadius(10)
                }
                .disabled(engine.isQuerying || engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // 停止按钮（查询中才显示）
                if engine.isQuerying {
                    Button {
                        engine.cancel()
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                            Text("停止")
                        }
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 0)
        .padding(.bottom, 12)
    }

    // MARK: - 进度条

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(engine.completed), total: Double(max(engine.total, 1)))
                .tint(.blue)
            Text("\(engine.completed) / \(engine.total)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - 统计 + 标签页

    private var statsAndTabs: some View {
        VStack(spacing: 8) {
            HStack {
                Text("成功 \(engine.successCount) 条，异常 \(engine.abnormalCount) 条，失败 \(engine.failedCount) 条，重复 \(engine.duplicateCount) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                // 排序按钮只在成功标签页显示
                if selectedTab == .success {
                    Menu {
                        Button {
                            engine.successSort = .original
                        } label: {
                            Text("原始顺序")
                        }
                        Button {
                            engine.successSort = .traceCountDesc
                        } label: {
                            Text("记录数多")
                        }
                        Button {
                            engine.successSort = .traceCountAsc
                        } label: {
                            Text("记录数少")
                        }
                    } label: {
                        Text(engine.successSort.title)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                // 异常标签页：一键复制全部异常单号
                if selectedTab == .abnormal && !engine.abnormalResults.isEmpty {
                    Button {
                        copyAllAbnormalMailNums()
                    } label: {
                        Text("复制全部")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                // 复制全部按钮只在失败标签页显示
                if selectedTab == .failed && !engine.failedResults.isEmpty {
                    Button {
                        copyAllFailedMailNums()
                    } label: {
                        Text("复制全部")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                // 重复标签页也加复制全部按钮
                if selectedTab == .duplicate && !engine.duplicateResults.isEmpty {
                    Button {
                        copyAllDuplicateMailNums()
                    } label: {
                        Text("复制全部")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal)

            Picker("结果", selection: $selectedTab) {
                ForEach(ExternalResultTab.allCases) { tab in
                    Text("\(tab.title) (\(countFor(tab)))")
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    // MARK: - 结果内容

    @ViewBuilder
    private var resultContent: some View {
        if currentList.isEmpty {
            emptyPlaceholder
        } else {
            resultList
                .id(engine.renderToken)   // 查询完成时整体重建，避免首帧显示旧行内容
            if selectionMode && selectedTab == .success {
                copyButtonBar
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        List {
            ForEach(currentList) { result in
                HStack(spacing: 12) {
                    // 🆕 多选模式：勾选圆圈（仅成功标签页）
                    if selectionMode && selectedTab == .success {
                        Image(systemName: selectedMailNums.contains(result.mailNum)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(selectedMailNums.contains(result.mailNum)
                                             ? Color.blue : Color.secondary)
                    }
                    ExternalResultRow(result: result)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    handleRowTap(result)
                }
                .onLongPressGesture {
                    // 长按复制：单号 + 最后一条轨迹
                    var textToCopy = result.mailNum
                    if let node = result.lastNode, !node.info.isEmpty {
                        textToCopy += "\n" + node.info
                    }
                    UIPasteboard.general.string = textToCopy
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .padding(.vertical, 0)
            }
        }
        .listStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }

    // 🆕 底部复制按钮栏
    private var copyButtonBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                copySelectedMailNums()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("复制选中的 \(selectedMailNums.count) 个单号")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedMailNums.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding()
            }
            .disabled(selectedMailNums.isEmpty)
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - 列表数据

    private var currentList: [ExternalMailResult] {
        switch selectedTab {
        case .success:   return engine.successResults
        case .abnormal:  return engine.abnormalResults
        case .failed:    return engine.failedResults
        case .duplicate: return engine.duplicateResults
        }
    }

    private func countFor(_ tab: ExternalResultTab) -> Int {
        switch tab {
        case .success:   return engine.successCount
        case .abnormal:  return engine.abnormalCount
        case .failed:    return engine.failedCount
        case .duplicate: return engine.duplicateCount
        }
    }

    // MARK: - 耗时格式化（X分X秒）

    private var formattedElapsed: String {
        let seconds = engine.elapsedSeconds
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)分\(s)秒"
    }

    // MARK: - 交互

    private func handleRowTap(_ result: ExternalMailResult) {
        if selectionMode && selectedTab == .success {
            // 🆕 多选模式：勾选/取消
            if selectedMailNums.contains(result.mailNum) {
                selectedMailNums.remove(result.mailNum)
            } else {
                selectedMailNums.insert(result.mailNum)
            }
        } else {
            showingDetail = result
        }
    }

    // MARK: - 复制（iOS 剪贴板）

    /// 🆕 复制选中的成功单号（每行一个，换行分隔）
    private func copySelectedMailNums() {
        let nums = engine.successResults
            .filter { selectedMailNums.contains($0.mailNum) }
            .map(\.mailNum)
        guard !nums.isEmpty else { return }
        UIPasteboard.general.string = nums.joined(separator: "\n")
        // 复制后退出多选模式
        selectionMode = false
        selectedMailNums.removeAll()
    }

    // 🆕 复制全部异常的单号（每行一个）
    private func copyAllAbnormalMailNums() {
        let nums = engine.abnormalResults.map(\.mailNum)
        guard !nums.isEmpty else { return }
        UIPasteboard.general.string = nums.joined(separator: "\n")
    }

    // 🆕 复制全部失败的单号（每行一个）
    private func copyAllFailedMailNums() {
        let nums = engine.failedResults.map(\.mailNum)
        guard !nums.isEmpty else { return }
        UIPasteboard.general.string = nums.joined(separator: "\n")
    }

    // 🆕 复制全部重复的单号（每行一个）
    private func copyAllDuplicateMailNums() {
        let nums = engine.duplicateResults.map(\.mailNum)
        guard !nums.isEmpty else { return }
        UIPasteboard.general.string = nums.joined(separator: "\n")
    }

    // MARK: - 导出 XLSX

    private func exportXLSX() {
        let data = ExternalXLSXExporter.export(engine.results)
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = ExternalXLSXExporter.defaultFileName() + ".xlsx"
        let url = tempDir.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            // 直接从窗口弹出分享面板，不用 sheet
            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                // 适配 iPad
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = UIApplication.shared.windows.first
                    popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                UIApplication.shared.windows.first?.rootViewController?.present(activityVC, animated: true)
            }
        } catch {
            print("导出失败: \(error)")
        }
    }
}

// MARK: - 结果行（按照原应用设计）
struct ExternalResultRow: View {
    let result: ExternalMailResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 第一行：单号
            HStack {
                Text(result.mailNum)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                // 成功和重复的显示蓝色状态代码（只显示中文，带框）
                if result.status == .success || result.status == .duplicate {
                    Text(formatStatusCode(result.statusCode, lastRemark: result.statusText))
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                // 失败的单号后面显示实际错误信息
                if result.status.isFailed {
                    Text(result.error ?? "无物流信息")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }

            // 成功和重复的都显示完整信息
            if result.status == .success || result.status == .duplicate {
                // 第二行：最后一条物流信息（自动换行，不限制行数）
                if let node = result.lastNode, !node.info.isEmpty {
                    Text(node.info)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                }

                // 第三行：轨迹条数 + 最早最晚时间差 + 标签（标签靠右固定位置）
                HStack(spacing: 8) {
                    // 轨迹条数：蓝色带框标签样式（不支持文本选择）
                    Text("\(result.traces.count)条")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)

                    if let durationBetween = traceDurationBetween {
                        Text(durationBetween)
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                            .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)
                    }

                    Spacer()

                    // 标签：拒收橙/撤单绿/改址紫/取消红/重复黄/异常红（靠右排列，可多标识并排）（不支持文本选择）
                    if result.isAbnormal {
                        tagLabel("异常", color: .red)
                            .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)
                    }
                    if result.status == .duplicate || result.isDuplicate {
                        tagLabel("重复", color: .yellow)
                            .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)
                    }
                    if result.isRejected {
                        tagLabel("拒收", color: .orange)
                            .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)
                    }
                    if result.isCancelled {
                        tagLabel("撤单", color: .green)
                            .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)
                    }
                    if result.isChangedAddr {
                        tagLabel("改址", color: .purple)
                            .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)
                    }
                    if result.isIntercepted {
                        tagLabel("取消", color: .red)
                            .textSelection(.disabled)
            .ignoresSafeArea(.keyboard)
                    }
                }
            }

            // 浅灰色分割线，便于区分每一行
            Divider()
                .background(Color.gray.opacity(0.2))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 0)
    }

    // 标签样式
    private func tagLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundColor(color)
    }

    // 计算最早和最晚轨迹之间的时间差：X分 / X小时 / X天
    private var traceDurationBetween: String? {
        guard result.traces.count >= 2 else { return nil }
        guard let firstDate = ExternalTrackParsing.parseDate(result.traces.first?.time ?? ""),
              let lastDate = ExternalTrackParsing.parseDate(result.traces.last?.time ?? "") else { return nil }
        let interval = abs(lastDate.timeIntervalSince(firstDate))
        if interval < 60 {
            return "\(Int(interval))秒"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分"
        } else if interval < 86400 {
            let h = Int(interval / 3600)
            let m = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "\(h)小时\(m)分" : "\(h)小时"
        } else {
            let d = Int(interval / 86400)
            let h = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
            return h > 0 ? "\(d)天\(h)小时" : "\(d)天"
        }
    }
}

