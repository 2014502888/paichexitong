import Foundation

// MARK: - 查询结果分类
enum QueryOutcome: Hashable {
    case success
    case failed(String)
    case duplicate

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - 单个单号的查询结果
struct ExternalMailResult: Identifiable, Equatable {
    var mailNum: String
    var status: QueryOutcome
    var error: String?
    var traces: [ExternalTraceNode]

    // 导出用字段
    var lastTime: String = ""
    var statusText: String = ""
    var statusCode: String = ""
    var traceLen: Int = 0
    var durationText: String = ""
    var durationToDeliverText: String = ""
    var isCancelled: Bool = false
    var isChangedAddr: Bool = false
    var isRejected: Bool = false
    var isIntercepted: Bool = false
    var isDuplicate: Bool = false
    var sender: String = ""
    var province: String = ""
    var city: String = ""
    var orgName: String = ""
    var orgCode: String = ""
    var acceptTime: String = ""
    var acceptInfo: String = ""
    var acceptProvince: String = ""
    var acceptCity: String = ""
    var acceptOrg: String = ""

    // 行的唯一标识：由引擎在收集结果时分配（mailNum-序号），
    // 保证同一单号在成功页/重复页的不同条目 id 不同，避免 SwiftUI 行视图跨标签复用
    var id: String = ""

    var lastNode: ExternalTraceNode? { traces.last }

    // 异常判断：最后一条轨迹不属派送/妥投/验收/计划类收尾状态，
    // 且最后一条轨迹时间超过 48 小时（2 天）未更新 → 异常
    var isAbnormal: Bool {
        if status.isFailed || status == .duplicate { return false }
        guard let last = lastNode else { return false }
        for kw in closingKeywords where last.info.contains(kw) { return false }
        guard let t = ExternalTrackParsing.parseDate(last.time) else { return false }
        return Date() > t.addingTimeInterval(48 * 3600)
    }

    static func == (lhs: ExternalMailResult, rhs: ExternalMailResult) -> Bool {
        lhs.mailNum == rhs.mailNum
    }
}

// MARK: - 轨迹节点（界面展示用）
struct ExternalTraceNode: Identifiable {
    let id = UUID()
    let time: String
    let info: String
    let province: String
    let city: String
    let org: String
}

// MARK: - 接口返回的原始轨迹记录
struct MailTraceRaw: Decodable, Sendable {
    var operatingTime: String?
    var code: String?
    var remark: String?
    var provName: String?
    var cityName: String?
    var orgCode: String?
    var orgName: String?

    var acceptTime: String?
    var acceptInfo: String?
    var acceptOrg: String?
    var acceptCity: String?
    var acceptProvince: String?
}

// MARK: - 接口响应外壳
struct MailResponse: Decodable {
    var code: String?
    var result: String?
    var message: String?
    var error: String?
    var data: [MailTraceRaw]?
    var traces: [MailTraceRaw]?
    var mailTrace: [MailTraceRaw]?

    var traceList: [MailTraceRaw]? {
        data ?? traces ?? mailTrace
    }
}

// MARK: - 网络层查询结果
enum FetchResult: Sendable {
    case success([MailTraceRaw])
    case notFound
    case error(String)
}

// MARK: - 异常判断用收尾关键词
// 最后一条物流信息命中任一关键词（派送中/妥投/验收/计划投递等收尾状态）则不算异常
let closingKeywords: [String] = [
    "如有疑问请电联快递员",
    "快件正在派送中",
    "计划投递时间",
    "仓库正在验收中",
    "您的快件已由包裹柜",
    "您的快件已妥收",
    "您的快件已派送至",
    "您的快件已取走",
    "您的快件已代收",
    "您的快件已代签收",
    "已按面单地址投送",
    "为您提供送货上门",
    "已妥投"
]

// MARK: - 结果标签页
enum ExternalResultTab: String, CaseIterable, Hashable, Identifiable {
    case success
    case abnormal
    case failed
    case duplicate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .success:   return "成功"
        case .abnormal:  return "异常"
        case .failed:    return "失败"
        case .duplicate: return "重复"
        }
    }
}

// MARK: - 成功结果排序方式
enum SuccessSort: String, CaseIterable, Hashable, Identifiable {
    case original = "原始顺序"
    case traceCountAsc = "记录数少"
    case traceCountDesc = "记录数多"

    var id: String { rawValue }

    var title: String { rawValue }
}

// MARK: - 全局工具函数
func formatStatusCode(_ code: String, lastRemark: String = "") -> String {
    // 如果轨迹里出现这些关键词，就判断为妥投
    if lastRemark.contains("为您提供送货上门") ||
       lastRemark.contains("您的快件已由包裹柜") ||
       lastRemark.contains("您的快件已派送至") ||
       lastRemark.contains("您的快件已妥收") ||
       lastRemark.contains("如有疑问请联系中转仓") ||
       lastRemark.contains("即将由中转仓换单发往目的地") ||
       lastRemark.contains("您的快件已取走") ||
       lastRemark.contains("您的快件已代收") ||
       lastRemark.contains("已按面单地址投送") {
        return "已妥投"
    }
    // 如果轨迹里出现"计划投递时间"，就显示"计划投递"
    if lastRemark.contains("计划投递时间") {
        return "计划投递"
    }
    // 如果轨迹里出现"快件正在派送中"，就显示"正在派送"
    if lastRemark.contains("快件正在派送中") {
        return "正在派送"
    }
    // 如果状态代码是空的或者是"-"、"--"，就显示"运输中"
    if code.isEmpty || code == "-" || code == "--" {
        return "运输中"
    }
    // 如果格式是 "数字-中文"，就去掉前面的数字和横线
    if let range = code.range(of: "-") {
        return String(code[range.upperBound...])
    }
    // 如果是纯数字，就映射成中文
    let codeMap: [String: String] = [
        "00": "收寄",
        "10": "已妥投",
        "11": "已妥投（自提柜）",
        "20": "运输中",
        "30": "投递中",
        "40": "运输中",
        "50": "离开",
        "99": "异常"
    ]
    return codeMap[code] ?? code
}
