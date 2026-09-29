import Foundation

class InternalAreaUtil {
    static let shared = InternalAreaUtil()

    private var cityToProvince: [String: String] = [:]

    private init() {
        load()
    }

    private func load() {
        guard let path = Bundle.main.path(forResource: "area", ofType: "json") else {
            print("area.json not found")
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            // area.json 不是标准 JSON（键名无引号、用单引号），需要转换
            var text = String(data: data, encoding: .utf8) ?? ""
            // 给顶层键名加引号: area0: -> "area0":
            text = text.replacingOccurrences(of: "area0:", with: "\"area0\":")
            text = text.replacingOccurrences(of: "area1:", with: "\"area1\":")
            text = text.replacingOccurrences(of: "area2:", with: "\"area2\":")
            // 替换单引号为双引号
            text = text.replacingOccurrences(of: "'", with: "\"")
            guard let jsonData = text.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let area0 = json["area0"] as? [String: String],
                  let area1 = json["area1"] as? [String: [Any]] else {
                print("parse area.json failed")
                return
            }
            // area1: 省编码 -> [[城市名, 城市编码], ...]
            for (provCode, cities) in area1 {
                guard let provName = area0[provCode] else { continue }
                for city in cities {
                    if let arr = city as? [String], arr.count >= 2 {
                        cityToProvince[arr[0]] = provName
                    }
                }
            }
            print("InternalAreaUtil loaded \(cityToProvince.count) cities")
        } catch {
            print("InternalAreaUtil error: \(error)")
        }
    }

    func getProvinceByCity(_ city: String) -> String {
        guard !city.isEmpty else { return "" }
        // 直接匹配
        if let prov = cityToProvince[city] {
            return prov
        }
        // 模糊匹配：去掉"市"字再试
        let trimmed = city.replacingOccurrences(of: "市", with: "")
        for (c, p) in cityToProvince {
            if c.hasPrefix(trimmed) || trimmed.hasPrefix(c.replacingOccurrences(of: "市", with: "")) {
                return p
            }
        }
        return ""
    }
}
