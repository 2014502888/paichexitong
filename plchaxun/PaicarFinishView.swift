import SwiftUI
import PhotosUI
import UIKit

// MARK: - 拍照结单（对应 PaicarFinishActivity）

struct PaicarFinishView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    let orderId: String
    var mode = ""   // "photos" = 只上传照片

    @State private var order: PaicarDispatchOrder?
    @State private var draftImages: [DraftImage] = []
    @State private var leaveTime = ""
    @State private var loadingNum = ""
    @State private var finishDesc = ""
    @State private var saving = false
    @State private var toastMsg: String?
    @State private var showPhotoPicker = false
    @State private var showCamera = false

    private let minImages = 4
    private let maxImages = 4

    private var pendingDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_photos/\(orderId)", isDirectory: true)
    }
    private func savePhotoToDisk(_ data: Data, fileName: String) {
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        try? data.write(to: pendingDir.appendingPathComponent(fileName))
    }
    private func loadPendingPhotos() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "jpg" {
            if let data = try? Data(contentsOf: f) {
                draftImages.append(DraftImage(fileName: f.lastPathComponent, data: data, uploaded: false))
            }
        }
    }

    private var photoOnly: Bool { mode == "photos" }
    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }
    private var inputBg: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.17) : Color(white: 0.96) }
    private var border: Color { isDark ? Color(white: 0.33) : Color(white: 0.8) }
    private var hintColor: Color { isDark ? Color(white: 0.67) : Color(white: 0.53) }
    private var orange: Color { Color(red: 1.0, green: 0.60, blue: 0.0) }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：← + 居中标题
            HStack(spacing: 0) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.blue).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                Text(photoOnly ? "上传照片" : "拍照结单")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 44)
            }
            .foregroundColor(fg)
            .background(pageBg)

            ScrollView {
                VStack(spacing: 0) {
                    if let o = order {
                        // 顶部行：车牌(前) + 邮路（邮路只取"-"后面的内容）
                        Text(routeLine(o))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(fg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                        // 相册(左) | 标题(中) | 拍照(右)
                        HStack(spacing: 0) {
                            iconBtn("photo.on.rectangle", "相册") {
                                showPhotoPicker = true
                            }
                            Text(photoOnly ? "装车照片" : "装车照片·共需要 \(minImages) 张")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(fg)
                                .frame(maxWidth: .infinity)
                            iconBtn("camera.fill", "拍照") {
                                showCamera = true
                            }
                        }
                        .padding(.horizontal, 16)

                        imagesGrid

                        if !photoOnly {
                            section("装车件数")
                            TextField("填写装载件数", text: $loadingNum)
                                .keyboardType(.numberPad)
                                .font(.system(size: 14))
                                .foregroundColor(fg)
                                .accentColor(fg)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(inputBg)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                                .padding(.horizontal, 16)

                            section("发车时间")
                            Button {
                                pickLeaveTime()
                            } label: {
                                Text(leaveTime)
                                    .font(.system(size: 14))
                                    .foregroundColor(fg)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(inputBg)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                            }
                            .padding(.horizontal, 16)

                            section("备注")
                            TextField("选填", text: $finishDesc)
                                .font(.system(size: 14))
                                .foregroundColor(fg)
                                .accentColor(fg)
                                .multilineTextAlignment(.center)
                                .padding(12)
                                .frame(minHeight: 88, alignment: .top)
                                .background(inputBg)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                                .padding(.horizontal, 16)
                        }

                        Button {
                            submit()
                        } label: {
                            Text(saving ? "提交中…" : (photoOnly ? "保存照片" : "提交结单"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(orange)
                                .cornerRadius(10)
                        }
                        .disabled(saving)
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                        .padding(.bottom, 32)
                    } else {
                        ProgressView().padding(.top, 160)
                    }
                }
            }
            .background(pageBg)
        }
        .background(pageBg)
        .navigationBarHidden(true)
        .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            if order == nil { load() }
            loadPendingPhotos()
        }
        .overlay(
            Group {
                if let msg = toastMsg {
                    PaicarToast(text: msg, dark: isDark)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.toastMsg = nil
                            }
                        }
                }
            }
        )
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(maxCount: maxImages - draftImages.count) { images in
                for img in images {
                    if draftImages.count >= maxImages { break }
                    if let data = img.jpegData(compressionQuality: 0.85) {
                        let fileName = "img_\(Int(Date().timeIntervalSince1970 * 1000))_\(draftImages.count).jpg"
                        savePhotoToDisk(data, fileName: fileName)
                        draftImages.append(DraftImage(fileName: fileName, data: data, uploaded: false))
                    }
                }
                if draftImages.count >= maxImages { toastMsg = "最多 \(maxImages) 张" }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                if draftImages.count >= maxImages {
                    toastMsg = "最多 \(maxImages) 张"
                    return
                }
                if let data = image.jpegData(compressionQuality: 0.85) {
                    let fileName = "img_\(Int(Date().timeIntervalSince1970 * 1000))_\(draftImages.count).jpg"
                    savePhotoToDisk(data, fileName: fileName)
                    draftImages.append(DraftImage(fileName: fileName, data: data, uploaded: false))
                }
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func iconBtn(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 14))
            }
            .foregroundColor(fg)
            .padding(.vertical, 6)
        }
    }

    /// 车牌排最前，邮路只取"-"后面的内容（对应安卓 render 的 route 逻辑）
    private func routeLine(_ o: PaicarDispatchOrder) -> String {
        let tail = o.applyList.first.map { a -> String in
            var t = a.routeName
            if let idx = t.firstIndex(of: "-") {
                t = String(t[t.index(after: idx)...])
            }
            if !a.routeShortName.isEmpty { t += "(\(a.routeShortName))" }
            return t
        } ?? ""
        return (o.carNo.isEmpty ? "" : o.carNo + " ") + tail
    }

    private var imagesGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Array(draftImages.enumerated()), id: \.offset) { idx, d in
                VStack(spacing: 2) {
                    if let img = UIImage(data: d.data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 80)
                            .clipped()
                            .cornerRadius(4)
                    }
                    Button {
                        if !d.uploaded {
                            draftImages.remove(at: idx)
                        }
                    } label: {
                        Text(d.uploaded ? "已传 ✓" : "✕")
                            .font(.system(size: 10))
                            .foregroundColor(d.uploaded ? Color.green : Color.red)
                    }
                    .disabled(d.uploaded)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func load() {
        Task {
            do {
                let d = try await PaicarApi.dispatchOrderDetail(id: orderId)
                var orderMap: [String: Any] = [:]
                if let o = d["order"] as? [String: Any] { orderMap = o }
                if orderMap["applyList"] == nil, let l = d["applyList"] as? [Any] { orderMap["applyList"] = l }
                if orderMap["images"] == nil, let l = d["imageList"] as? [Any] { orderMap["images"] = l }
                order = PaicarDispatchOrder.fromJson(orderMap)
                randomLoadingNum()
                leaveTime = nowTime()
                loadDraft()
            } catch PaicarError.authExpired {
                // 被顶号：不自动退页，停在原地等全局弹窗（AuthDialog）的 取消/重新登录 决定下一步。
                // 本页无 loading 状态，全局弹窗负责后续导航，这里什么都不用做。
            } catch {
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    /// 随机装载件数（对应安卓：按车型）
    private func randomLoadingNum() {
        let specsText = [order?.specs ?? ""] + (order?.applyList.map { $0.carSpecs } ?? [])
        if specsText.contains(where: { $0.contains("9.6") }) {
            loadingNum = "\(Int.random(in: 2789...2946))"
        } else if specsText.contains(where: { $0.contains("7.6") }) {
            loadingNum = "\(Int.random(in: 1755...1888))"
        } else if specsText.contains(where: { $0.contains("5.3") }) {
            loadingNum = "\(Int.random(in: 823...987))"
        }
    }

    private func nowTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func pickLeaveTime() {
        let datePicker = UIAlertController(title: "发车时间", message: nil, preferredStyle: .actionSheet)
        let quick = ["现在", "15 分钟后", "30 分钟后", "1 小时后"]
        for q in quick {
            datePicker.addAction(UIAlertAction(title: q, style: .default) { _ in
                var interval: TimeInterval = 0
                if q == "15 分钟后" { interval = 900 }
                if q == "30 分钟后" { interval = 1800 }
                if q == "1 小时后" { interval = 3600 }
                leaveTime = formatTime(Date().addingTimeInterval(interval))
            })
        }
        datePicker.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(datePicker)
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    // MARK: 草稿（UserDefaults + Documents）

    private func draftKey() -> String { "paicar_finish_draft_\(orderId)" }
    private func draftDir() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("finish_drafts/\(orderId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadDraft() {
        guard let raw = UserDefaults.standard.string(forKey: draftKey()),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for o in arr {
            let fn = (o["f"] as? String) ?? ""
            let up = (o["u"] as? Bool) ?? false
            let fileURL = draftDir().appendingPathComponent(fn)
            if let d = try? Data(contentsOf: fileURL) {
                draftImages.append(DraftImage(fileName: fn, data: d, uploaded: up))
            }
        }
    }

    private func saveDraft() {
        var arr: [[String: Any]] = []
        for d in draftImages {
            arr.append(["f": d.fileName, "u": d.uploaded])
            try? d.data.write(to: draftDir().appendingPathComponent(d.fileName))
        }
        if let data = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8) ?? "", forKey: draftKey())
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey())
        try? FileManager.default.removeItem(at: draftDir())
    }

    // MARK: 提交

    private func submit() {
        if saving { return }
        if photoOnly {
            submitPhotosOnly()
            return
        }
        let p = PaicarProfileHolder.profile
        let needMin = p?.rolesId != "4"
        if needMin && draftImages.count < minImages {
            toastMsg = "照片不能少于 \(minImages) 张"
            return
        }
        if (Int(loadingNum) ?? 0) < 1 {
            toastMsg = "请填写装车件数"
            return
        }
        if leaveTime.isEmpty {
            toastMsg = "请选择发车时间"
            return
        }
        saving = true
        Task {
            do {
                // 1) 上传未传照片
                for i in draftImages.indices where !draftImages[i].uploaded {
                    let d = draftImages[i]
                    let r = try await PaicarApi.uploadImage(fileData: d.data, fileName: d.fileName, extra: [("id", orderId)])
                    let code = ((r["data"] as? [String: Any])?["code"])
                    let codeInt = (code as? NSNumber)?.intValue ?? ((code as? String) == "1" ? 1 : 0)
                    if codeInt != 1 {
                        throw PaicarError.api("照片上传失败")
                    }
                    draftImages[i] = DraftImage(fileName: d.fileName, data: d.data, uploaded: true)
                    saveDraft()
                }
                // 2) 提交结单
                let fr = try await PaicarApi.finish(id: orderId, leaveTime: leaveTime,
                                                    finishDesc: finishDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    loadingNum: loadingNum)
                saving = false
                if fr.ok {
                    clearDraft()
                    PaicarFlags.finishedDirty = true
                    PaicarFlags.dispatchDirty = true
                    toastMsg = "结单成功"
                    // 通知列表: 切回"全部"并刷新, 刚结的单归入已结单、从全部消失
                    NotificationCenter.default.post(name: .paicarBackToAllList, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        presentationMode.wrappedValue.dismiss()
                    }
                } else {
                    toastMsg = (fr.dataMap["msg"] as? String) ?? "结单失败"
                }
            } catch PaicarError.authExpired {
                saving = false
            } catch {
                saving = false
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func submitPhotosOnly() {
        if saving { return }
        saving = true
        Task {
            do {
                for i in draftImages.indices where !draftImages[i].uploaded {
                    let d = draftImages[i]
                    let r = try await PaicarApi.uploadImage(fileData: d.data, fileName: d.fileName, extra: [("id", orderId)])
                    let code = ((r["data"] as? [String: Any])?["code"])
                    let codeInt = (code as? NSNumber)?.intValue ?? ((code as? String) == "1" ? 1 : 0)
                    if codeInt != 1 {
                        throw PaicarError.api("照片上传失败")
                    }
                    draftImages[i] = DraftImage(fileName: d.fileName, data: d.data, uploaded: true)
                    saveDraft()
                }
                saving = false
                clearDraft()
                toastMsg = "照片已保存"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    presentationMode.wrappedValue.dismiss()
                }
            } catch PaicarError.authExpired {
                saving = false
            } catch {
                saving = false
                toastMsg = (error as? PaicarError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func present(_ alert: UIAlertController) {
        guard let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first?.rootViewController else { return }
        var top = host
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
}

struct DraftImage {
    let fileName: String
    let data: Data
    let uploaded: Bool
}

// MARK: - 相册多选（PHPicker）

struct PhotoPicker: UIViewControllerRepresentable {
    let maxCount: Int
    let onPick: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = max(maxCount, 1)
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            var images: [UIImage] = []
            let group = DispatchGroup()
            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { images.append(img) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.parent.onPick(images)
            }
        }
    }
}

// MARK: - 相机拍照

struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage {
                parent.onCapture(img)
            }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
