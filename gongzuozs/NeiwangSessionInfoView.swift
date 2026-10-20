import SwiftUI
import UIKit

/// 伪装参数查看页：当前使用的工号 / 会话 / UA / 请求形态（支持浅深模式）
struct NeiwangSessionInfoView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    // 🆕 导入完成后强制刷新显示
    @State private var refreshTick = 0

    private var cfg: NeiwangHarConfig { NeiwangHarConfig.shared }

    /// 已知工号-姓名映射（新增工号在此补充）
    private let knownUsers: [String: String] = [
        "E00000097801": "陈水星",
        "E00000531360": "吴安乐"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 抬头：居中（关闭按钮）
            ZStack {
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.black : Color.white)

            ScrollView {
                VStack(spacing: 12) {
                    // 🆕 导入：当前工号上面一行，蓝字 导入，功能与原右上角导入一致
                    Button {
                        presentImporter()
                    } label: {
                        Text("导入")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                            .cornerRadius(8)
                    }
                    .id(refreshTick)
                    if cfg.isConfigured {
                        row("当前工号", value: userIdText)
                        row("会话 sessionId", value: cfg.sessionId.isEmpty ? "未导入" : cfg.sessionId)
                        row("User-Agent", value: cfg.userAgent.isEmpty ? "未导入" : cfg.userAgent)
                        row("请求形态", value: cfg.isIOS ? "iOS" : "安卓")
                        row("Referer", value: cfg.isIOS ? "/so-novel-xm/" : "/sowebx/")
                    } else {
                        Text("未导入会话，暂无参数")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.top, 80)
                    }
                }
                .padding(16)
            }
            .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
        }
        // 🆕 设置页打开时接管导入回调；导入完成后强制刷新参数显示
        .onAppear {
            NeiwangImportDelegate.shared.onImported = { refreshTick += 1 }
            refreshTick += 1
        }
    }

    // 🆕 从设置页弹导入：用最顶层已呈现的控制器，避免 sheet 内 present 无效
    private func presentImporter() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = NeiwangImportDelegate.shared
        picker.allowsMultipleSelection = false
        guard let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first?.rootViewController else { return }
        var top = host
        while let presented = top.presentedViewController { top = presented }
        top.present(picker, animated: true)
    }

    private var userIdText: String {
        let id = cfg.userId
        if id.isEmpty { return "未导入" }
        // 🆕 优先包里解析出的真实姓名，其次已知映射表
        let name = cfg.userName.isEmpty ? (knownUsers[id] ?? "") : cfg.userName
        return name.isEmpty ? id : "\(name)（\(id)）"
    }

    private func row(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
