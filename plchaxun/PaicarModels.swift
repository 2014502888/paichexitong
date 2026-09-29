import Foundation
import CommonCrypto

// MARK: - 数据模型（对应 PaicarModels.kt）

struct PaicarProfile {
    let id: String
    let name: String
    let rolesId: String
    let roles: String
    let organId: String
    let organName: String
    let pwdChanged: Bool

    static func fromJson(_ j: [String: Any]) -> PaicarProfile {
        PaicarProfile(
            id: s(j, "id"),
            name: s(j, "name"),
            rolesId: s(j, "roles_id"),
            roles: s(j, "roles"),
            organId: s(j, "organ_id"),
            organName: s(j, "organName"),
            pwdChanged: ((j["pwdChanged"] as? NSNumber)?.intValue ?? 0) == 1
        )
    }
}

struct PaicarApplyOrder: Identifiable, Hashable {
    let id: String
    let orderNumber: String
    let statusCode: String
    let statusName: String
    let customerName: String
    let liaisonName: String
    let liaisonPhone: String
    let routeName: String
    let routeShortName: String
    let number: String
    let volume: String
    let carSpecs: String
    let arrivalTime: String
    let createTime: String
    let createName: String
    let organName: String
    let remarks: String

    static func fromJson(_ j: [String: Any]) -> PaicarApplyOrder {
        PaicarApplyOrder(
            id: s(j, "id"),
            orderNumber: s(j, "orderNumber"),
            statusCode: s(j, "statusCode"),
            statusName: s(j, "statusName"),
            customerName: s(j, "customerName"),
            liaisonName: s(j, "liaisonName"),
            liaisonPhone: s(j, "liaisonPhone"),
            routeName: s(j, "routeName"),
            routeShortName: s(j, "routeShortName"),
            number: s(j, "number"),
            volume: s(j, "volume"),
            carSpecs: s(j, "carSpecs"),
            arrivalTime: s(j, "arrivalTime"),
            createTime: s(j, "createTime"),
            createName: s(j, "createName"),
            organName: s(j, "organName"),
            remarks: s(j, "remarks")
        )
    }
}

struct PaicarImage: Identifiable, Hashable {
    let id: String
    let imageFile: String
    static func fromJson(_ j: [String: Any]) -> PaicarImage {
        PaicarImage(id: s(j, "id"), imageFile: s(j, "imageFile"))
    }
}

struct PaicarDispatchOrder: Identifiable, Hashable {
    let id: String
    let orderNumber: String
    let statusCode: String
    let statusName: String
    let carNo: String
    let driverId: String
    let driverName: String
    let driverPhone: String
    let carOrganName: String
    let specs: String
    let volume: String
    let pieceFreight: String
    let loadingNum: String
    let createTime: String
    let createId: String
    let createName: String
    let receiveName: String
    let receiveTime: String
    let leaveTime: String
    let finishDesc: String
    let organId: String
    let applyList: [PaicarApplyOrder]
    let images: [PaicarImage]

    static func fromJson(_ j: [String: Any]) -> PaicarDispatchOrder {
        var applies: [PaicarApplyOrder] = []
        if let list = j["applyList"] as? [[String: Any]] {
            applies = list.map { PaicarApplyOrder.fromJson($0) }
        }
        var imgs: [PaicarImage] = []
        if let list = j["images"] as? [[String: Any]] {
            imgs = list.map { PaicarImage.fromJson($0) }
        }
        return PaicarDispatchOrder(
            id: s(j, "id"),
            orderNumber: s(j, "orderNumber"),
            statusCode: s(j, "statusCode"),
            statusName: s(j, "statusName"),
            carNo: s(j, "carNo"),
            driverId: s(j, "driver_id"),
            driverName: s(j, "driverName"),
            driverPhone: s(j, "driverPhone"),
            carOrganName: s(j, "carOrganName"),
            specs: s(j, "specs"),
            volume: s(j, "volume"),
            pieceFreight: s(j, "pieceFreight"),
            loadingNum: s(j, "loadingNum"),
            createTime: s(j, "createTime"),
            createId: s(j, "create_id"),
            createName: s(j, "createName"),
            receiveName: s(j, "receiveName"),
            receiveTime: s(j, "receiveTime"),
            leaveTime: s(j, "leaveTime"),
            finishDesc: s(j, "finishDesc"),
            organId: s(j, "organ_id"),
            applyList: applies,
            images: imgs
        )
    }
}

struct PaicarCustomer: Identifiable {
    let id: String
    let name: String
    static func fromJson(_ j: [String: Any]) -> PaicarCustomer {
        PaicarCustomer(id: s(j, "id"), name: s(j, "customerName"))
    }
}

struct PaicarDriver: Identifiable {
    let id: String
    let name: String
    let phone: String
    static func fromJson(_ j: [String: Any]) -> PaicarDriver {
        PaicarDriver(id: s(j, "id"), name: s(j, "name"), phone: s(j, "phone"))
    }
}

struct PaicarLiaison: Identifiable {
    let id: String
    let name: String
    static func fromJson(_ j: [String: Any]) -> PaicarLiaison {
        PaicarLiaison(id: s(j, "id"), name: s(j, "name"))
    }
}

struct PaicarRoute: Identifiable {
    let id: String
    let name: String
    static func fromJson(_ j: [String: Any]) -> PaicarRoute {
        PaicarRoute(id: s(j, "id"), name: s(j, "routeName"))
    }
}

struct PaicarCarSpec: Identifiable {
    let id: String
    let specs: String
    let volume: String
    static func fromJson(_ j: [String: Any]) -> PaicarCarSpec {
        PaicarCarSpec(id: s(j, "id"), specs: s(j, "specs"), volume: s(j, "volume"))
    }
}

struct PaicarFleetCar: Identifiable {
    let id: String
    let carNo: String
    static func fromJson(_ j: [String: Any]) -> PaicarFleetCar {
        PaicarFleetCar(id: s(j, "id"), carNo: s(j, "carNo"))
    }
}

/// 后端部分字段把空值序列化成字符串 "null"，统一转空串（对应安卓 s()）
private func s(_ j: [String: Any], _ key: String) -> String {
    let v = j[key]
    let t = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? (v as? NSNumber)?.stringValue
        ?? ""
    return t.lowercased() == "null" ? "" : t
}

// MARK: - API 结果包装（对应 PaicarResult）

struct PaicarResult {
    let ret: Int
    let data: Any?
    let msg: String
    var ok: Bool { ret == 200 }
    var dataMap: [String: Any] { (data as? [String: Any]) ?? [:] }
    var dataList: [[String: Any]] {
        if let arr = data as? [[String: Any]] { return arr }
        if let arr = data as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        return []
    }
    static func fromJson(_ j: [String: Any]) -> PaicarResult {
        PaicarResult(
            ret: (j["ret"] as? NSNumber)?.intValue ?? -1,
            data: j["data"],
            msg: (j["msg"] as? String) ?? ""
        )
    }
}

struct PaicarLoginInfo {
    let code: Int
    let token: String
    let userId: String
    let userNo: String
    var success: Bool { code == 200 }
    static func fromJson(_ d: [String: Any]) -> PaicarLoginInfo {
        PaicarLoginInfo(
            code: (d["code"] as? NSNumber)?.intValue ?? -1,
            token: (d["token"] as? String) ?? "",
            // 服务端 user_id/user_no 可能为整数（如 42），s() 兼容 Int 与空值"null"
            userId: s(d, "user_id"),
            userNo: s(d, "user_no")
        )
    }
}

enum PaicarError: LocalizedError {
    case api(String)
    case authExpired
    var errorDescription: String? {
        switch self {
        case .api(let m): return m
        case .authExpired: return "登录已过期"
        }
    }
}

// MARK: - MD5

func paicarMD5(_ input: String) -> String {
    let data = Data(input.utf8)
    var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
    data.withUnsafeBytes { buf in
        _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}
