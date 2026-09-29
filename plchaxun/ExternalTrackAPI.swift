import Foundation

// MARK: - 轨迹查询接口
// 完全按照原应用抓包结果：GET 请求，单号直接拼接到 URL 路径末尾
enum ExternalTrackAPI {

    // 共享 URLSession，避免每次都创建新的
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 3
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "KDApp/1.0",
            "version": "ems_track_cn_3.0",
            "authenticate": "8766D5A09F2B55E8E053D2C2020A96A1"
        ]
        return URLSession(configuration: config)
    }()

    /// 单次查询：GET 请求，单号拼接到 URL 路径
    static func fetch(_ mailNum: String) async -> FetchResult {
        do {
            let url = URL(string: "http://211.156.193.140:8000/cotrackapi/api/track/mail/\(mailNum)")!

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 3

            let (data, response) = try await sharedSession.data(for: request)
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
        } catch let error as URLError {
            return .error(message(for: error))
        } catch {
            return .error(error.localizedDescription)
        }
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
}
