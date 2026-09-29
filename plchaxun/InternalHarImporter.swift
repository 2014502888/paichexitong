import Foundation
import UIKit

enum InternalHarImporter {

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

                if !sessionId.isEmpty && !userAgent.isEmpty { break }
            }

            if sessionId.isEmpty {
                showToast("HAR导入失败: 未找到sessionId")
                return
            }

            InternalHarConfig.shared.save(sessionId: sessionId, userAgent: userAgent)
            // 🆕 清除旧 token 缓存，新 sessionId 立即生效，无需重启 App
            NetworkManager.shared.resetToken()
            showToast("导入成功，立即生效")
        } catch {
            showToast("HAR导入失败: \(error.localizedDescription)")
        }
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
