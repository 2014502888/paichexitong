import Foundation

// MARK: - 轨迹查询接口
// 完全按照原应用抓包结果：GET 请求，单号直接拼接到 URL 路径末尾
enum WaiwangTrackAPI {

    /// 单次查询：GET 请求，单号拼接到 URL 路径
    /// 为什么弃用 URLSession：iOS 18 上 URLSession 请求可能永久挂起（timeout/cancel/invalidateAndCancel
    /// 均不触发 completion，回调版与 async 版都存在），且 Task 取消时 URLSession 内部取消竞态
    /// 在注入/插件环境下可能引发间歇性崩溃；改用 NSURLConnection 同步请求 + 硬超时，与派车/内网模块
    /// 一致，请求必定在超时时间内返回，Task 取消时子任务最多等一个超时周期后自然结束，不再有取消竞态。
    static func fetch(_ mailNum: String) async -> FetchResult {
        guard let url = URL(string: "http://211.156.193.140:8000/cotrackapi/api/track/mail/\(mailNum)") else {
            return .error("无效URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KDApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("ems_track_cn_3.0", forHTTPHeaderField: "version")
        request.setValue("8766D5A09F2B55E8E053D2C2020A96A1", forHTTPHeaderField: "authenticate")

        return await withCheckedContinuation { cont in
            let box = OnceBox()
            DispatchQueue.global().async {
                var response: URLResponse?
                do {
                    let data = try NSURLConnection.sendSynchronousRequest(request, returning: &response)
                    box.once { cont.resume(returning: handle(data: data, response: response)) }
                } catch let err {
                    box.once { cont.resume(returning: .error(describe(err))) }
                }
            }
            // 兜底：正常时同步请求已被 timeoutInterval 截断；极端情况仍无返回时强制返回超时
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
                box.once { cont.resume(returning: .error("请求超时")) }
            }
        }
    }

    // MARK: - 响应处理

    private static func handle(data: Data, response: URLResponse?) -> FetchResult {
        guard let http = response as? HTTPURLResponse else {
            return .error("非HTTP响应")
        }
        if !(200..<300).contains(http.statusCode) {
            return .error("HTTP \(http.statusCode)")
        }
        if data.isEmpty {
            return .error("响应数据为空 (状态码: \(http.statusCode), Content-Length: \(http.allHeaderFields["Content-Length"] ?? "未知"))")
        }
        return parse(data: data)
    }

    // MARK: - 解析

    private static func parse(data: Data) -> FetchResult {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let traces = try? decoder.decode([MailTraceRaw].self, from: data) {
            // 空轨迹算失败
            return traces.isEmpty ? .notFound : .success(traces)
        }

        if let response = try? decoder.decode(MailResponse.self, from: data) {
            if let traces = response.traceList {
                // 空轨迹算失败
                return traces.isEmpty ? .notFound : .success(traces)
            }
            if let msg = response.error ?? response.message, !msg.isEmpty {
                return .error(msg)
            }
            if let code = response.code, code != "0", code != "200" {
                return .error("\(code): \(response.result ?? "")")
            }
            // 都没匹配到，算失败
            return .notFound
        }

        let preview = String(data: data.prefix(500), encoding: .utf8) ?? "(无法解码为UTF-8，数据长度: \(data.count)字节)"
        return .error("Unexpected response: \(preview)")
    }

    // MARK: - 错误描述

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return message(for: urlError)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:
                return "请求超时"
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost:
                return "无法连接服务器 (\(ns.code))"
            case NSURLErrorNotConnectedToInternet:
                return "无网络连接"
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "请求超时"
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
            return "无法连接服务器 (\(error.code.rawValue))"
        case .notConnectedToInternet:
            return "无网络连接"
        default:
            return error.localizedDescription
        }
    }

    /// 防重复 resume 的闭包盒（同步请求与兜底定时器可能竞争）
    private final class OnceBox {
        private let lock = NSLock()
        private var done = false
        func once(_ op: () -> Void) {
            lock.lock()
            if !done { done = true; op() }
            lock.unlock()
        }
    }
}
