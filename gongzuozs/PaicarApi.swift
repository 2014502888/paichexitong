import Foundation

// MARK: - 寄递派车 API 客户端（对应 PaicarApi.kt，PhalApi sign 签名）
// 签名/参数顺序与安卓、Flutter 完全一致：keys 用「插入顺序」（s→业务参数→token→user_id→timestamp→sign→keys），
// 登录 platform 固定 android（服务端仅接受该值）。此前的 sorted() 导致 keys 顺序不同、接口被服务端拒绝。

enum PaicarApi {
    static let base = "http://119.91.30.146/a/car/phalapi/public/"
    private static let salt = "*#&FD)#f34"
    private static let authExpiredCode = 410

    // 每个请求使用独立的 ephemeral 会话（iOS 上共享 URLSession 与 Swift 并发并发请求存在已知死锁，
    // 表现为请求永久挂起且不触发超时；独立会话=独立连接池，彻底绕开该问题）
    private static func makeSession(timeout: TimeInterval = 15) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 10
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }

    // 登录态
    static var token = ""
    static var userId = ""

    // 登录失效回调（token 被其他端顶掉时触发，UI 层注册跳登录确认）
    static var onAuthExpired: (() -> Void)?
    // 写操作(撤回/提交/结单等)期间静默:不弹顶号框,只静默退出
    static var silentAuthExpired = false
    // 重新登录期间忽略新的失效回调(防并发死循环)
    static var relogining = false
    // 切换瞬间没弹成,下个页面补弹
    static var authExpiredPending = false
    // 已成功加载过一次数据: 只有真正进过系统后, 被顶号才弹框;
    // 首次登录/加载期间的400(空token竞态)不弹, 避免刚点登录就误弹。
    static var hasLoadedOnce = false
    // 用户主动退出登录后不自动登录
    static var justLoggedOut = false

    // MARK: 签名

    static func makePwd(_ plain: String) -> String { paicarMD5(salt + plain) }

    /// 与安卓 signed() 完全一致：
    /// 1) 参数按「插入顺序」追加：s → 业务参数 → token → user_id → timestamp
    /// 2) sign = MD5(按 key 字母序拼接的 value)
    /// 3) keys = 「插入顺序」的全部 key 用 & 连接（含 sign、keys），末尾加 &
    private static func signed(service: String, params: [(String, String)]) -> [String: String] {
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        var ordered: [(String, String)] = [("s", service)]
        ordered.append(contentsOf: params)
        ordered.append(("token", token))
        ordered.append(("user_id", userId))
        ordered.append(("timestamp", ts))
        let sortedKeys = ordered.map { $0.0 }.sorted()
        let concat = sortedKeys.map { k in ordered.first(where: { $0.0 == k })?.1 ?? "" }.joined()
        ordered.append(("sign", paicarMD5(concat)))
        ordered.append(("keys", ordered.map { $0.0 }.joined(separator: "&") + "&"))
        var dict: [String: String] = [:]
        for (k, v) in ordered { dict[k] = v }
        return dict
    }

    private static func parseBody(_ body: String, service: String) throws -> PaicarResult {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaicarError.api("响应解析失败")
        }
        let r = PaicarResult.fromJson(obj)
        // 对齐安卓: 只有真被顶号(410)或鉴权类400(msg含登录失效字样)才弹重登框;
        // 普通业务错误(ret<0/普通400/404)不弹, 否则新装登录后第一个业务请求就误弹。
        let authMsg = r.msg
        let isAuth400 = r.ret == 400 && (
            authMsg.contains("未登录") || authMsg.contains("登录token") ||
            authMsg.contains("请重新登录") || authMsg.contains("token已过期") ||
            authMsg.contains("账号未登录")
        )
        if service != "App.User_user.login" && r.ret == 200 {
            hasLoadedOnce = true
        }
        if service != "App.User_user.login" && (r.ret == authExpiredCode || isAuth400) {
            // 只有真有登录态、且已经成功进过系统(hasLoadedOnce)才弹顶号框;
            // 首次登录/加载期的空token竞态400不弹, 避免刚点登录就误弹。
            if !silentAuthExpired && !token.isEmpty && hasLoadedOnce { onAuthExpired?() }
            throw PaicarError.authExpired
        }
        return r
    }

    /// 网络请求统一入口（NSURLConnection 同步请求 + 任务级硬超时）。
    /// 为什么弃用 URLSession：iOS 18 上 URLSession 请求可能永久挂起且 timeoutInterval、
    /// cancel、invalidateAndCancel 均不触发 completion（回调版与 async 版都存在），表现为无限转圈；
    /// NSURLConnection 同步请求是阻塞式老 API，timeoutInterval 是硬性约束，15 秒内必定返回
    /// （数据 / 超时 / 错误），彻底绕开 URLSession 的挂起问题，不再无限转圈。
    private static func perform(_ req: URLRequest, timeout: TimeInterval = 15, service: String) async throws -> Data {
        var r = req
        r.timeoutInterval = timeout
        return try await withCheckedThrowingContinuation { cont in
            let box = OnceBox()
            DispatchQueue.global().async {
                var response: URLResponse?
                do {
                    let data = try NSURLConnection.sendSynchronousRequest(r, returning: &response)
                    box.once { cont.resume(returning: data) }
                } catch let err {
                    box.once { cont.resume(throwing: PaicarError.api("网络错误(\(service))：\(describe(err))")) }
                }
            }
            // 兜底：正常时同步请求已被 timeoutInterval 截断；极端情况仍无返回时强制抛错
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 3) {
                box.once {
                    cont.resume(throwing: PaicarError.api("请求超时(\(service))：请求已发出但无响应，token\(token.isEmpty ? "为空" : "正常")、user_id\(userId.isEmpty ? "为空" : userId)。请检查网络后重试"))
                }
            }
        }
    }

    /// 防重复 resume 的闭包盒（URLSession/同步请求与兜底定时器可能竞争）
    private final class OnceBox {
        private let lock = NSLock()
        private var done = false
        func once(_ op: () -> Void) {
            lock.lock()
            if !done { done = true; op() }
            lock.unlock()
        }
    }

    /// 网络错误转中文描述（便于界面直接展示可读信息）
    private static func describe(_ err: Error) -> String {
        if let u = err as? URLError {
            switch u.code {
            case .timedOut: return "请求超时，请检查网络后重试"
            case .notConnectedToInternet: return "网络不可用，请检查连接"
            case .cannotConnectToHost, .cannotFindHost: return "无法连接服务器，请检查网络"
            case .dnsLookupFailed: return "域名解析失败"
            default: return u.localizedDescription
            }
        }
        return err.localizedDescription
    }

    static func get(_ service: String, params: [(String, String)]) async throws -> PaicarResult {
        let signed = signed(service: service, params: params)
        var comps = URLComponents(string: base)!
        var items: [URLQueryItem] = []
        for (k, v) in signed.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw PaicarError.api("URL 错误") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let data = try await perform(req, service: service)
        guard let body = String(data: data, encoding: .utf8) else { throw PaicarError.api("空响应") }
        return try parseBody(body, service: service)
    }

    static func post(_ service: String, params: [(String, String)]) async throws -> PaicarResult {
        let signed = signed(service: service, params: params)
        // 表单编码必须转义 & + =（keys 参数值含 &，若不转义会被服务端拆断成独立字段）
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+;/")
        let enc = { (s: String) -> String in s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let bodyString = signed.map { "\(enc($0.key))=\(enc($0.value))" }.joined(separator: "&")
        var req = URLRequest(url: URL(string: base)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = bodyString.data(using: .utf8)
        let data = try await perform(req, service: service)
        guard let body = String(data: data, encoding: .utf8) else { throw PaicarError.api("空响应") }
        return try parseBody(body, service: service)
    }

    /// multipart 上传图片（对应 PaicarApi.uploadImage，字段 file）
    static func uploadImage(fileData: Data, fileName: String, extra: [(String, String)]) async throws -> [String: Any] {
        let signed = signed(service: "App.Upload_uploadImage.go", params: extra)
        let boundary = "paicar-\(Int(Date().timeIntervalSince1970 * 1000))"
        var req = URLRequest(url: URL(string: base)!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        var body = Data()
        for (k, v) in signed {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".data(using: .utf8)!)
            body.append(v.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let data = try await perform(req, timeout: 60, service: "App.Upload_uploadImage.go")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaicarError.api("上传失败")
        }
        // 手动检查登录失效:上传接口返回格式可能不同,只检查410
        let ret = (obj["ret"] as? NSNumber)?.intValue ?? 200
        if ret == 410 {
            if !silentAuthExpired && !token.isEmpty && hasLoadedOnce { onAuthExpired?() }
            throw PaicarError.authExpired
        }
        return obj
    }

    // MARK: 登录 / 账号

    static func login(userNo: String, plainPassword: String) async throws -> PaicarLoginInfo {
        let r = try await get("App.User_user.login", params: [
            ("user_no", userNo),
            ("password", makePwd(plainPassword)),
            ("version", "1.1.4"),
            ("platform", "android"),
        ])
        if !r.ok { throw PaicarError.api(r.msg.isEmpty ? "登录失败" : r.msg) }
        let info = PaicarLoginInfo.fromJson(r.dataMap)
        if !info.success {
            let msg = (r.dataMap["message"] as? String) ?? "账号或密码错误"
            throw PaicarError.api(msg)
        }
        token = info.token
        userId = info.userId
        hasLoadedOnce = false
        return info
    }

    static func profile() async throws -> [String: Any] {
        let r = try await get("App.User_user.profile", params: [])
        if !r.ok {
            // parseBody 已处理真顶号(410/鉴权400); 这里只是普通业务错误,
            // 仅在真有登录态且已进过系统时才视为顶号, 避免首次加载误弹。
            if !silentAuthExpired && !token.isEmpty && hasLoadedOnce { onAuthExpired?() }
            throw PaicarError.authExpired
        }
        return (r.dataMap["profile"] as? [String: Any]) ?? [:]
    }

    static func changePwd(orgPwd: String, newPwd: String) async throws -> [String: Any] {
        let r = try await get("App.User_user.changePwd", params: [
            ("orgPassword", makePwd(orgPwd)),
            ("newPassword", makePwd(newPwd)),
        ])
        if !r.ok { throw PaicarError.api(r.msg.isEmpty ? "修改失败" : r.msg) }
        return r.dataMap
    }

    // MARK: 申请单

    static func applyOrderList(organId: String, rolesId: String) async throws -> [[String: Any]] {
        let r = try await get("App.DispatchCar_applyOrder.getList", params: [("organ_id", organId), ("roles_id", rolesId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func applyOrderDetail(id: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_applyOrder.getDetail", params: [("id", id)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return (r.dataMap["order"] as? [String: Any]) ?? [:]
    }

    static func applyOrderSave(id: String?, organId: String, customerListJson: String,
                               arrivalTime: String, number: String, liaisonId: String,
                               routeId: String, carSpecs: String, remarks: String) async throws -> PaicarResult {
        var p: [(String, String)] = [
            ("organ_id", organId),
            ("customerList", customerListJson),
            ("arrivalTime", arrivalTime),
            ("number", number),
            ("liaison_id", liaisonId),
            ("route_id", routeId),
            ("carSpecs", carSpecs),
            ("remarks", remarks),
        ]
        if let id = id, !id.isEmpty { p.append(("id", id)) }
        let service = (id != nil && !id!.isEmpty) ? "App.DispatchCar_applyOrder.update" : "App.DispatchCar_applyOrder.insert"
        return try await post(service, params: p)
    }

    static func applyOrderAction(id: String, action: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_applyOrder.\(action)", params: [("id", id)])
    }

    static func applyOrderCheckNotFinishBill(organId: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_applyOrder.checkNotFinishBill", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataMap
    }

    // MARK: 派车单

    static func dispatchOrderList(organId: String, rolesId: String, page: Int, perpage: Int) async throws -> [[String: Any]] {
        let r = try await get("App.DispatchCar_dispatchOrder.getList", params: [
            ("organ_id", organId), ("roles_id", rolesId),
            ("page", "\(page)"), ("perpage", "\(perpage)"),
        ])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func dispatchOrderDetail(id: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_dispatchOrder.getDetail", params: [("id", id)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataMap
    }

    static func dispatch(organId: String, carOrganId: String, carSpecsId: String, orderIdList: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.dispatch", params: [
            ("organ_id", organId), ("carOrgan_id", carOrganId),
            ("carSpecs_id", carSpecsId), ("order_id_list", orderIdList),
        ])
    }

    static func arrangeCar(id: String, carNo: String, driverId: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.arrangeCar", params: [
            ("id", id), ("carNo", carNo), ("driver_id", driverId),
        ])
    }

    static func finish(id: String, leaveTime: String, finishDesc: String, loadingNum: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.finish", params: [
            ("id", id), ("leaveTime", leaveTime), ("finishDesc", finishDesc), ("loadingNum", loadingNum),
        ])
    }

    static func dispatchAction(id: String, action: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.\(action)", params: [("id", id)])
    }

    static func deleteImage(id: String, file: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.deleteImage", params: [("id", id), ("file", file)])
    }

    // MARK: 基础数据

    static func getCarSpecs() async throws -> [[String: Any]] {
        let r = try await get("App.Base_data.getCarSpecs", params: [])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getDriver(organId: String, name: String = "") async throws -> [[String: Any]] {
        var p: [(String, String)] = [("organ_id", organId)]
        if !name.isEmpty { p.append(("name", name)) }
        let r = try await get("App.Base_data.getDriver", params: p)
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getLiaison(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_data.getLiaison", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getFleetList(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_organ.getFleetList", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getFleetCarList(organId: String, specsId: String, carNo: String = "") async throws -> [[String: Any]] {
        var p: [(String, String)] = [("organ_id", organId), ("specs_id", specsId)]
        if !carNo.isEmpty { p.append(("carNo", carNo)) }
        let r = try await get("App.Base_fleetCar.getList", params: p)
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getRouteList(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_drivieRoute.getList", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getCustomer(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_customer.getCustomer", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    // MARK: 看板

    static func applyOrderGather(organId: String, rolesId: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_applyOrder.getGather", params: [("organ_id", organId), ("roles_id", rolesId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList.first ?? [:]
    }

    static func dispatchOrderGather(organId: String, rolesId: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_dispatchOrder.getGather", params: [("organ_id", organId), ("roles_id", rolesId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList.first ?? [:]
    }

    static func imageUrl(_ file: String) -> String { base + "uploads/" + file }

    // MARK: 快捷申请配置（UserDefaults 对应 SharedPreferences）

    static func defaultQuickCars() -> [[String: String]] {
        []
    }

    private static let quickCarsKey = "paicar_quick_cars"
    static func loadQuickCars() -> [[String: String]] {
        guard let raw = UserDefaults.standard.string(forKey: quickCarsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return defaultQuickCars()
        }
        return arr.map { row in
            var m: [String: String] = [:]
            for (k, v) in row { m[k] = (v as? String) ?? "\(v)" }
            return m
        }
    }

    static func saveQuickCars(_ cars: [[String: String]]) {
        let arr = cars.map { $0 }
        if let data = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8) ?? "", forKey: quickCarsKey)
        }
    }

    private static func quickArrival(hour: String) -> String {
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: now) + " " + hour
    }

    /// 一键创建一条快捷申请单，返回新单 id
    static func quickApplyCar(_ spec: [String: String]) async throws -> String {
        let profile = try await PaicarProfileHolder.load()
        let cust: [[String: Any]] = [[
            "id": spec["customerId"] ?? "",
            "customer_id": spec["customerId"] ?? "",
            "customerName": spec["customerName"] ?? "",
            "number": spec["number"] ?? "",
            "shipment": 1,
        ]]
        let jsonData = try JSONSerialization.data(withJSONObject: cust)
        let json = String(data: jsonData, encoding: .utf8) ?? ""
        let r = try await post("App.DispatchCar_applyOrder.insert", params: [
            ("organ_id", profile.organId),
            ("customerList", json),
            ("arrivalTime", quickArrival(hour: spec["hour"] ?? "20:00")),
            ("number", spec["number"] ?? "1000"),
            ("liaison_id", spec["liaisonId"] ?? ""),
            ("route_id", spec["routeId"] ?? ""),
            ("carSpecs", spec["carSpecs"] ?? ""),
            ("remarks", ""),
        ])
        if !r.ok { throw PaicarError.api(r.msg.isEmpty ? "申请失败" : r.msg) }
        let id = (r.dataMap["id"] as? String) ?? ""
        if id.isEmpty { throw PaicarError.api("申请失败：未返回单号") }
        return id
    }

    /// 一键撤回并删除：001 先撤回成 000 再删；000 直接删
    static func quickRecall(id: String) async throws {
        silentAuthExpired = true
        try? await post("App.DispatchCar_applyOrder.recall", params: [("id", id)])
        let r2 = try await post("App.DispatchCar_applyOrder.delete", params: [("id", id)])
        silentAuthExpired = false
        if !r2.ok { throw PaicarError.api(r2.msg.isEmpty ? "删除失败" : r2.msg) }
    }

    private static let quickIdsKey = "paicar_quick_ids"
    static func loadQuickIds() -> [String] {
        guard let raw = UserDefaults.standard.string(forKey: quickIdsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
    }

    static func saveQuickIds(_ ids: [String]) {
        if let data = try? JSONSerialization.data(withJSONObject: ids) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8) ?? "", forKey: quickIdsKey)
        }
    }
}

// MARK: - 登录态存储（对应 PaicarSession）

enum PaicarSession {
    private static let kToken = "paicar_token"
    private static let kUser = "paicar_user_id"
    private static let kUserNo = "paicar_user_no"
    private static let kUserPwd = "paicar_user_pwd"

    static var loggedIn: Bool { PaicarApi.token.isEmpty == false }

    static var savedUserNo: String {
        UserDefaults.standard.string(forKey: kUserNo) ?? ""
    }
    static var savedUserPwd: String {
        UserDefaults.standard.string(forKey: kUserPwd) ?? ""
    }

    static func load() {
        PaicarApi.token = UserDefaults.standard.string(forKey: kToken) ?? ""
        PaicarApi.userId = UserDefaults.standard.string(forKey: kUser) ?? ""
    }

    static func save(token: String, userId: String, userNo: String, userPwd: String = "") {
        let d = UserDefaults.standard
        d.set(token, forKey: kToken)
        d.set(userId, forKey: kUser)
        d.set(userNo, forKey: kUserNo)
        if !userPwd.isEmpty { d.set(userPwd, forKey: kUserPwd) }
        PaicarApi.token = token
        PaicarApi.userId = userId
        // 登录态变了，旧的 profile（organId/rolesId）可能属于上一个账号，必须清缓存重新拉，
        // 否则换账号/重登后所有列表接口都用旧参数拉出空数据
        PaicarProfileHolder.reset()
    }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: kToken)
        d.removeObject(forKey: kUser)
        PaicarApi.token = ""
        PaicarApi.userId = ""
        PaicarApi.hasLoadedOnce = false
        PaicarProfileHolder.reset()
    }
}

// MARK: - 全局 Profile 缓存（对应 PaicarProfileHolder）

enum PaicarProfileHolder {
    static var profile: PaicarProfile?
    static var loading = false

    static func reset() {
        profile = nil
        loading = false
    }

    static func load() async throws -> PaicarProfile {
        if let p = profile { return p }
        let j = try await PaicarApi.profile()
        let p = PaicarProfile.fromJson(j)
        profile = p
        return p
    }
}

// MARK: - 全局脏标记（对应 PaicarApp.finishedDirty / dispatchDirty）

enum PaicarFlags {
    static var finishedDirty = false
    static var dispatchDirty = false
    // 详情页观察到的最新状态（orderId -> statusCode）：详情加载成功才写入，
    // 返回列表时与列表当前状态对比，不一致才静默刷新（外部改状态也能追到，状态没变零请求）
    static var detailSeenState: [String: String] = [:]
}
