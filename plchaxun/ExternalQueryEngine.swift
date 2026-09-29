import Foundation
import Combine
import UIKit

// MARK: - 查询引擎
final class ExternalQueryEngine: ObservableObject {

    @Published var inputText = ""
    @Published var isQuerying = false
    @Published var total = 0
    @Published var completed = 0
    @Published var elapsedSeconds: Double = 0
    @Published var successSort: SuccessSort = .traceCountAsc
    // 🆕 并发查询数：可调 1~20，默认 8（实测服务器吞吐约4~5单/秒，8并发性价比最高）
    @Published var concurrency = 8

    @Published private(set) var results: [ExternalMailResult] = []
    // 查询完成时递增，强制结果列表整体重建一次（保证首帧渲染就是最新数据）
    @Published var renderToken = 0

    private var currentTask: Task<Void, Never>?
    private let ticker = Ticker()

    var successResults: [ExternalMailResult] {
        // 成功界面每个单号只保留一条（真正查询成功的），本批重复过的打上"重复"标记
        var list = results.filter { $0.status.isSuccess }
        let dupNums = Set(results.filter { $0.status == .duplicate }.map(\.mailNum))
        if !dupNums.isEmpty {
            list = list.map { r in
                var r = r
                if dupNums.contains(r.mailNum) { r.isDuplicate = true }
                return r
            }
        }
        switch successSort {
        case .original:
            // 原始顺序（按 results 数组顺序，也就是用户输入顺序）
            return list
        case .traceCountAsc:
            // 轨迹最少到最多
            return list.sorted { $0.traces.count < $1.traces.count }
        case .traceCountDesc:
            // 轨迹最多到最少
            return list.sorted { $0.traces.count > $1.traces.count }
        }
    }

    var abnormalResults: [ExternalMailResult] {
        results.filter(\.isAbnormal)
    }

    var failedResults: [ExternalMailResult] {
        // 本批重复过的失败单号也打上重复标记（显示黄色胶囊）
        let dupNums = Set(results.filter { $0.status == .duplicate }.map(\.mailNum))
        guard !dupNums.isEmpty else { return results.filter { $0.status.isFailed } }
        return results.filter { $0.status.isFailed }.map { r in
            var r = r
            if dupNums.contains(r.mailNum) { r.isDuplicate = true }
            return r
        }
    }

    var duplicateResults: [ExternalMailResult] {
        results.filter { $0.status == .duplicate }
    }

    var successCount: Int { results.filter { $0.status.isSuccess }.count }
    var abnormalCount: Int { abnormalResults.count }
    var failedCount: Int { failedResults.count }
    var duplicateCount: Int { duplicateResults.count }

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func start() {
        // 防止重复点击
        guard !isQuerying else { return }

        let nums = ExternalTrackParsing.parseInput(inputText)
        guard !nums.isEmpty else { return }

        let startDate = Date()

        // 申请后台任务时间，让应用切到后台也能继续查询
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "KDAppQuery") {
            // 后台时间快用完了，结束任务
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }

        total = nums.count
        completed = 0
        results = []
        isQuerying = true

        currentTask = Task { [weak self] in
            await self?.run(nums: nums, start: startDate)
        }
        ticker.start { [weak self] in
            self?.elapsedSeconds = Date().timeIntervalSince(startDate)
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        ticker.stop()
        isQuerying = false
        // 结束后台任务
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    @MainActor
    private func run(nums: [String], start: Date) async {
        defer {
            // 结束后台任务
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
            // 只有当前任务还在运行时才更新状态（防止旧任务覆盖新任务）
            if !Task.isCancelled {
                isQuerying = false
                ticker.stop()
                elapsedSeconds = Date().timeIntervalSince(start)
                renderToken += 1   // 强制结果列表重建，确保成功页首帧就带胶囊
            }
        }

        // 🆕 并发数改为可配置（1~20，界面可调），默认 8
        let semaphore = AsyncSemaphore(value: max(1, concurrency))

        // 用 task group 收集结果
        var collected: [Int: ExternalMailResult] = [:]

        await withTaskGroup(of: (index: Int, result: ExternalMailResult).self) { group in
            for (index, num) in nums.enumerated() {
                if Task.isCancelled { break }

                group.addTask {
                    await semaphore.wait()
                    defer { semaphore.signal() }

                    if Task.isCancelled {
                        return (index, ExternalMailResult(
                            mailNum: num,
                            status: .failed("已取消"), error: "已取消",
                            traces: []
                        ))
                    }

                    // 先判断单号长度，必须正好13位，不是的直接失败，标签"非正确单号"
                    if num.count != 13 {
                        return (index, ExternalMailResult(
                            mailNum: num,
                            status: .failed("非正确单号"), error: "非正确单号",
                            traces: []
                        ))
                    }

                    // 重试逻辑：失败自动重试2次
                    var outcome: FetchResult
                    outcome = await ExternalTrackAPI.fetch(num)
                    var retryCount = 0
                    func shouldRetry() -> Bool {
                        switch outcome {
                        case .success: return false
                        case .notFound, .error: return true
                        }
                    }
                    while retryCount < 2 && shouldRetry() {
                        retryCount += 1
                        // 稍微等一下再重试
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        outcome = await ExternalTrackAPI.fetch(num)
                    }

                    var result = ExternalMailResult(
                        mailNum: num,
                        status: .failed("Unknown error"),
                        error: nil,
                        traces: []
                    )

                    switch outcome {
                    case .success(let raws):
                        result.traces = raws.map(ExternalTrackParsing.traceNode)
                        result.status = .success
                        result.isDuplicate = false

                        // 填充导出字段
                        if let first = raws.first, let last = raws.last {
                            result.lastTime = last.operatingTime ?? ""
                            result.statusText = last.remark ?? ""
                            result.statusCode = last.code ?? ""
                            result.traceLen = raws.count
                            result.province = last.provName ?? ""
                            result.city = last.cityName ?? ""
                            result.orgName = last.orgName ?? ""
                            result.orgCode = last.orgCode ?? ""
                            result.acceptTime = first.operatingTime ?? ""
                            result.acceptInfo = first.remark ?? ""
                            result.acceptProvince = first.provName ?? ""
                            result.acceptCity = first.cityName ?? ""
                            result.acceptOrg = first.orgName ?? ""
                            // 计算历时：最早一条 - 最晚一条（不管顺序，同时取 operatingTime 和 acceptTime）
                            let times = raws.compactMap { trace -> Date? in
                                if let t = trace.operatingTime, let d = ExternalTrackParsing.parseDate(t) { return d }
                                if let t = trace.acceptTime, let d = ExternalTrackParsing.parseDate(t) { return d }
                                return nil
                            }
                            if let earliest = times.min(), let latest = times.max() {
                                let interval = latest.timeIntervalSince(earliest)
                                result.durationText = formatInterval(interval)
                            } else {
                                result.durationText = "-"
                            }
                            // 计算耗时：第一条到妥投时间（没妥投就到最后一条）
                            result.durationToDeliverText = calculateDurationToDeliver(raws: raws)
                            result.isCancelled = raws.contains { $0.remark?.contains("按寄件人指定地址投递") ?? false }
                            result.isChangedAddr = raws.contains { $0.remark?.contains("按修改后收件人地址投递") ?? false }
                            result.isRejected = raws.contains { $0.remark?.contains("退件封发，拒收") ?? false }
                            result.isIntercepted = raws.contains { $0.remark?.contains("寄件人取消寄件") ?? false }
                            // 投递员：取最后一条派送信息里的快递员（拒收退回后再派送时取最终派送员，与电脑端一致）
                            for t in raws {
                                if let remark = t.remark, remark.contains("快递员") {
                                    if let range = remark.range(of: "快递员【") {
                                        let start = range.upperBound
                                        let end = remark[start...].firstIndex(of: "，") ?? remark.endIndex
                                        let name = String(remark[start..<end])
                                        if name.hasPrefix("电话") { continue }   // 跳过"快递员【电话:…】"这类无姓名记录
                                        result.sender = name
                                    }
                                }
                            }
                        }
                    case .notFound:
                        result.status = .failed("无物流信息")
                        result.error = "无物流信息"
                    case .error(let message):
                        result.status = .failed(message)
                        result.error = message
                    }

                    return (index, result)
                }
            }

            // 收集结果，更新 UI
            for await (index, result) in group {
                collected[index] = result
                completed = collected.count
                let ordered = (0..<nums.count).compactMap { collected[$0] }
                results = Self.markDuplicates(ordered)
            }
        }
    }

    // 按输入顺序识别重复：第一个出现的单号保留原结果，后续重复的单号
    // 复制第一个的结果并标记 status = .duplicate / isDuplicate = true（不依赖网络等待，稳定可靠）
    private static func markDuplicates(_ list: [ExternalMailResult]) -> [ExternalMailResult] {
        var seen = Set<String>()
        var out: [ExternalMailResult] = []
        for r in list {
            if seen.contains(r.mailNum) {
                if let first = out.first(where: { $0.mailNum == r.mailNum }) {
                    var dup = first
                    dup.mailNum = r.mailNum
                    dup.status = .duplicate
                    dup.isDuplicate = true
                    dup.id = "\(r.mailNum)-d-\(out.count)"   // 独立 id，避免与首条共用行身份
                    out.append(dup)
                }
            } else {
                var kept = r
                kept.id = "\(r.mailNum)-\(out.count)"         // 稳定唯一 id，增量更新不闪
                seen.insert(r.mailNum)
                out.append(kept)
            }
        }
        return out
    }
}

// MARK: - 查询耗时刷新器
private final class Ticker {
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

    func stop() {
        task?.cancel()
        task = nil
    }
}

// MARK: - 异步信号量（控制并发数，用 NSLock 保证线程安全）
private final class AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    init(value: Int) {
        self.count = value
    }

    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if count > 0 {
                count -= 1
                lock.unlock()
                cont.resume()
            } else {
                waiters.append(cont)
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        } else {
            count += 1
            lock.unlock()
        }
    }
}
// MARK: - 时间间隔格式化
private func formatInterval(_ interval: TimeInterval) -> String {
    let absInterval = abs(interval)
    if absInterval < 60 {
        return "\(Int(absInterval))秒"
    } else if absInterval < 3600 {
        return "\(Int(absInterval / 60))分"
    } else if absInterval < 86400 {
        let h = Int(absInterval / 3600)
        let m = Int(absInterval.truncatingRemainder(dividingBy: 3600) / 60)
        return m > 0 ? "\(h)小时\(m)分" : "\(h)小时"
    } else {
        let d = Int(absInterval / 86400)
        let h = Int(absInterval.truncatingRemainder(dividingBy: 86400) / 3600)
        let m = Int(absInterval.truncatingRemainder(dividingBy: 3600) / 60)
        if h > 0 && m > 0 {
            return "\(d)天\(h)小时\(m)分"
        } else if h > 0 {
            return "\(d)天\(h)小时"
        } else if m > 0 {
            return "\(d)天\(m)分"
        } else {
            return "\(d)天"
        }
    }
}

// MARK: - 耗时计算：第一条到妥投时间（只显示天数）
private func calculateDurationToDeliver(raws: [MailTraceRaw]) -> String {
    // 取第一条时间（同时考虑 operatingTime 和 acceptTime）
    var firstDate: Date? = nil
    for raw in raws {
        if let t = raw.operatingTime, let d = ExternalTrackParsing.parseDate(t) {
            firstDate = d
            break
        }
        if let t = raw.acceptTime, let d = ExternalTrackParsing.parseDate(t) {
            firstDate = d
            break
        }
    }
    guard let first = firstDate else { return "-" }

    // 妥投关键词
    let deliveredKeywords = [
        "为您提供送货上门",
        "您的快件已派送至",
        "您的快件已妥收",
        "如有疑问请联系中转仓",
        "即将由中转仓换单发往目的地",
        "您的快件已取走",
        "您的快件已代收",
        "您的快件已由包裹柜",
        "已按面单地址投送"
    ]

    // 找第一条出现妥投关键词的轨迹的时间
    var deliveredDate: Date? = nil
    for raw in raws {
        if let remark = raw.remark {
            for keyword in deliveredKeywords {
                if remark.contains(keyword) {
                    if let t = raw.operatingTime, let d = ExternalTrackParsing.parseDate(t) {
                        deliveredDate = d
                        break
                    }
                    if let t = raw.acceptTime, let d = ExternalTrackParsing.parseDate(t) {
                        deliveredDate = d
                        break
                    }
                }
            }
            if deliveredDate != nil { break }
        }
    }

    // 找最后一条轨迹的时间（如果妥投后还有新轨迹，就用最后一条时间）
    var lastDate: Date? = nil
    for raw in raws.reversed() {
        if let t = raw.operatingTime, let d = ExternalTrackParsing.parseDate(t) {
            lastDate = d
            break
        }
        if let t = raw.acceptTime, let d = ExternalTrackParsing.parseDate(t) {
            lastDate = d
            break
        }
    }
    guard let last = lastDate else { return "-" }

    // 结束时间：如果有妥投时间，就取 max(妥投时间, 最后一条时间)
    let endDate: Date
    if let delivered = deliveredDate {
        endDate = max(delivered, last)
    } else {
        endDate = last
    }

    // 计算天数：过了当天24点就算1天
    let calendar = Calendar.current
    let startOfDay1 = calendar.startOfDay(for: first)
    let startOfDay2 = calendar.startOfDay(for: endDate)
    let days = calendar.dateComponents([.day], from: startOfDay1, to: startOfDay2).day ?? 0

    if days <= 0 {
        return "1天"
    } else {
        return "\(days)天"
    }
}
