import Foundation

// 🆕 登录会话失效错误：HAR 过期（工号退出登录等），触发后停止查询并提示重新导入
struct SessionExpiredError: Error {
    let message: String
}

class NetworkManager: NSObject, URLSessionDelegate {

    static let shared = NetworkManager()

    private let baseURL = "http://211.156.201.20:8012"
    private let userId = "E00000097801"
    private let from = "xm"

    private var token: String?
    private let tokenLock = NSLock()
    private var tokenTask: Task<String, Error>?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func query(mailNo: String) async throws -> [String: Any] {
        let t = try await fetchToken()

        guard let url = URL(string: "\(baseURL)/so-novel-biz/mail/getMailTraceByMailNo?userId=\(userId)&from=\(from)&mailNo=\(mailNo)") else {
            throw NSError(domain: "Network", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL错误"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request)
        request.setValue("sessionId=\(InternalHarConfig.shared.sessionId); xmToken=\(t)", forHTTPHeaderField: "Cookie")
        request.httpBody = "{\"mailNo\":\"\(mailNo)\"}".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP错误"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "解析失败"])
        }
        // 🆕 会话失效检测：服务端返回登录/会话/过期相关提示时，抛会话失效错误
        if let msg = json["msg"] as? String,
           msg.contains("登录") || msg.contains("会话") || msg.contains("失效") || msg.contains("过期") || msg.contains("未登录") {
            throw SessionExpiredError(message: msg)
        }
        return json
    }

    /// 🆕 清除 token 缓存：导入新 HAR 后调用，使新 sessionId 立即生效（无需重启 App）
    func resetToken() {
        tokenLock.lock()
        token = nil
        tokenTask?.cancel()
        tokenTask = nil
        tokenLock.unlock()
    }

    private func fetchToken() async throws -> String {        tokenLock.lock()
        if let t = token, !t.isEmpty {
            tokenLock.unlock()
            return t
        }
        // 已有正在获取的任务，等它完成
        if let existing = tokenTask {
            tokenLock.unlock()
            return try await existing.value
        }
        let task = Task { () -> String in
            defer {
                tokenLock.lock()
                tokenTask = nil
                tokenLock.unlock()
            }
            return try await self.doFetchToken()
        }
        tokenTask = task
        tokenLock.unlock()
        return try await task.value
    }

    private func doFetchToken() async throws -> String {
        guard let url = URL(string: "\(baseURL)/so-novel-biz/common/xmGetToken?userId=\(userId)&from=\(from)") else {
            throw NSError(domain: "Network", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL错误"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("sessionId=\(InternalHarConfig.shared.sessionId)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取token失败"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first,
              let inner = first["data"] as? [String: Any],
              let newToken = inner["token"] as? String, !newToken.isEmpty else {
            // 🆕 拿不到 token = 会话失效（HAR 过期/工号已退出登录），抛会话失效错误
            throw SessionExpiredError(message: "登录会话已失效")
        }
        tokenLock.lock()
        token = newToken
        tokenLock.unlock()
        return newToken
    }

    private func applyHeaders(to request: inout URLRequest) {
        let cfg = InternalHarConfig.shared
        if !cfg.userAgent.isEmpty {
            request.setValue(cfg.userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("http://211.156.201.20:8012", forHTTPHeaderField: "Origin")
        if cfg.isIOS {
            request.setValue("http://211.156.201.20:8012/so-novel-xm/", forHTTPHeaderField: "Referer")
            request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        } else {
            request.setValue("http://211.156.201.20:8012/sowebx/", forHTTPHeaderField: "Referer")
            request.setValue("com.holly.android.holly.uc_test", forHTTPHeaderField: "X-Requested-With")
            request.setValue("zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        }
    }
}
