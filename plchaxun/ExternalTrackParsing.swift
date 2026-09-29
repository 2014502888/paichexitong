import Foundation

// MARK: - 输入解析 / 日期解析 / 轨迹整理
enum ExternalTrackParsing {

    static let dateFormats: [String] = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm",
        "yyyy.MM.dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss"
    ]

    // DateFormatter 非线程安全，5 并发查询会同时解析日期，用锁保护
    private static let parserLock = NSLock()
    private static let _parsers: [DateFormatter] = {
        dateFormats.map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = format
            return f
        }
    }()

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        parserLock.lock()
        defer { parserLock.unlock() }
        for parser in _parsers {
            if let date = parser.date(from: trimmed) { return date }
        }
        return nil
    }

    static func displayTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        if let date = parseDate(raw) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: date)
        }
        return raw
    }

    static func traceNode(from raw: MailTraceRaw) -> ExternalTraceNode {
        ExternalTraceNode(
            time: displayTime(raw.acceptTime ?? raw.operatingTime),
            info: raw.acceptInfo ?? raw.remark ?? "—",
            province: raw.acceptProvince ?? raw.provName ?? "",
            city: raw.acceptCity ?? raw.cityName ?? "",
            org: raw.acceptOrg ?? raw.orgName ?? raw.orgCode ?? ""
        )
    }

    // 单号有效规则：13 位，且以 1/8/9 开头（EMS/邮政单号特征）
    static func isValidMailNum(_ digits: String) -> Bool {
        guard digits.count == 13 else { return false }
        guard let first = digits.first else { return false }
        return first == "1" || first == "8" || first == "9"
    }

    /// 详细解析：返回（有效单号列表, 非正确单号计数）
    /// 规则：按空白/逗号/分号切分片段 → 每片段提取连续数字段 →
    ///   恰好13位且1/8/9开头 → 有效单号；
    ///   15位以上 → 取最后一个 1/8/9 开头的 13 位子串（兼容"重量/数量+单号"粘连）；
    ///   14位 → 多一位，判非正确单号（如"这是单号12311111111111"）；
    ///   其余（位数不对、开头不对）→ 计入非正确单号，不查询、不产生记录
    static func parseInputDetailed(_ text: String) -> (valid: [String], invalid: Int) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var valid: [String] = []
        var invalid = 0

        for token in tokens {
            // 提取该片段内的所有连续数字段（如 "单号9111111111111" → [9111111111111]；
            // "9444444444444重量800" → [9444444444444, 800]）
            var digits = ""
            var segments: [String] = []
            for ch in token {
                if let ascii = ch.asciiValue, (48...57).contains(ascii) {
                    digits.append(ch)
                } else if !digits.isEmpty {
                    segments.append(digits)
                    digits = ""
                }
            }
            if !digits.isEmpty { segments.append(digits) }

            for seg in segments {
                if seg.count == 13 {
                    if isValidMailNum(seg) {
                        valid.append(seg)
                    } else {
                        invalid += 1   // 13 位但非 1/8/9 开头
                    }
                } else if seg.count == 14 {
                    invalid += 1   // 14位：多一位，判非正确单号
                } else if seg.count > 14 {
                    // 超长（15位+）：找最后一个 1/8/9 开头的 13 位子串（兼容"数量+单号"粘连）
                    var found: String? = nil
                    for i in 0...(seg.count - 13) {
                        let start = seg.index(seg.startIndex, offsetBy: i)
                        let end = seg.index(start, offsetBy: 13)
                        let sub = String(seg[start..<end])
                        if let first = sub.first, first == "1" || first == "8" || first == "9" {
                            found = sub   // 覆盖式赋值，取最后一个
                        }
                    }
                    if let f = found {
                        valid.append(f)
                    } else {
                        invalid += 1
                    }
                } else {
                    invalid += 1   // 不足 13 位（如 1700、电话号码、800 等）
                }
            }
        }
        return (valid, invalid)
    }

    static func parseInput(_ text: String) -> [String] {
        parseInputDetailed(text).valid
    }
}
