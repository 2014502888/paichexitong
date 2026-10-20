import Foundation

class NeiwangHarConfig {
    static let shared = NeiwangHarConfig()

    var sessionId: String = ""
    var userAgent: String = ""
    var userId: String = ""   // 🆕 HAR 解析出的工号（查询与工单同工号两用）

    private let defaults = UserDefaults.standard

    func load() {
        sessionId = defaults.string(forKey: "sessionId") ?? ""
        userAgent = defaults.string(forKey: "userAgent") ?? ""
        userId = defaults.string(forKey: "userId") ?? ""
    }

    func save(sessionId: String, userAgent: String, userId: String = "") {
        self.sessionId = sessionId
        self.userAgent = userAgent
        self.userId = userId
        defaults.set(sessionId, forKey: "sessionId")
        defaults.set(userAgent, forKey: "userAgent")
        defaults.set(userId, forKey: "userId")
    }

    var isConfigured: Bool {
        !sessionId.isEmpty
    }

    var isIOS: Bool {
        userAgent.contains("iPhone")
    }
}
