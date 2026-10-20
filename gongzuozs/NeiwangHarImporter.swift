import Foundation
import UIKit

enum NeiwangHarImporter {

    static func importHar(from url: URL) {
        do {
            let data: Data
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                data = try Data(contentsOf: url)
            } else {
                data = try Data(contentsOf: url)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let log = json["log"] as? [String: Any],
                  let entries = log["entries"] as? [[String: Any]] else {
                showToast("HAR解析失败")
                return
            }

            var sessionId = ""
            var userAgent = ""
            var userId = ""
            var userName = ""

            for entry in entries {
                guard let request = entry["request"] as? [String: Any],
                      let headers = request["headers"] as? [[String: String]] else { continue }

                for h in headers {
                    let name = h["name"] ?? ""
                    let value = h["value"] ?? ""

                    if name == "Cookie", sessionId.isEmpty {
                        if let range = value.range(of: "sessionId=") {
                            var s = String(value[range.upperBound...])
                            if let end = s.firstIndex(of: ";") {
                                s = String(s[..<end])
                            }
                            sessionId = s
                        }
                    }

                    if name == "User-Agent", userAgent.isEmpty {
                        if value.contains("Mozilla/5.0") {
                            userAgent = value
                        }
                    }
                }

                // 🆕 userId：优先从 URL query 参数取（工单/查询接口均带 userId=）
                if userId.isEmpty, let urlStr = request["url"] as? String,
                   let comps = URLComponents(string: urlStr),
                   let items = comps.queryItems,
                   let uid = items.first(where: { $0.name == "userId" })?.value,
                   !uid.isEmpty {
                    userId = uid
                }

                // 🆕 userId/userName：包里没有 URL 参数时，从响应体提取
                // （登录/员工信息接口响应含 userId/employeeId/_id 与 employeeName/displayname/userName）
                if (userId.isEmpty || userName.isEmpty),
                   let response = entry["response"] as? [String: Any],
                   let content = response["content"] as? [String: Any],
                   let text = content["text"] as? String {
                    if userId.isEmpty {
                        userId = extract("\"(?:userId|employeeId|_id)\":\"(E[^\"]+)\"", from: text) ?? ""
                    }
                    // 名字：仅当本响应同时含该工号时提取（登录/员工信息响应），
                    // 避免抓到联系人/消息列表里的 displayname（如"调度指令消息"）
                    if userName.isEmpty, !userId.isEmpty, text.contains(userId) {
                        userName = extract("\"(?:userName|employeeName|displayname)\":\"([^\"]+)\"", from: text) ?? ""
                    }
                }

                if !sessionId.isEmpty && !userAgent.isEmpty && !userId.isEmpty && !userName.isEmpty { break }
            }

            if sessionId.isEmpty {
                showToast("HAR导入失败: 未找到sessionId")
                return
            }

            NeiwangHarConfig.shared.save(sessionId: sessionId, userAgent: userAgent, userId: userId, userName: userName)
            // 🆕 清除旧 token 缓存，新 sessionId 立即生效，无需重启 App
            Neiwang.shared.resetToken()
            showToast("导入成功，立即生效")
        } catch {
            showToast("HAR导入失败: \(error.localizedDescription)")
        }
    }

    /// 正则取第一个捕获组
    private static func extract(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func showToast(_ message: String) {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.windows.first }).first else { return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            window.rootViewController?.present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                alert.dismiss(animated: true)
            }
        }
    }
}
