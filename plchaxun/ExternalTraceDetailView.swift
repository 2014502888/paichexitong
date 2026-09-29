import SwiftUI
import UIKit

// MARK: - 单号轨迹详情（iOS 版）
struct ExternalTraceDetailView: View {

    let result: ExternalMailResult
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // 固定在顶部的关闭按钮栏（不随内容滚动）
            HStack {
                Button("返回") {
                    dismiss()
                }
                .foregroundColor(.blue)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
            VStack(spacing: 16) {
                // 标题：物流详情（居中）
                Text("物流详情")
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 0)

                // 状态标签：跟标题一样大，居中，紧贴标题（拒收橙/撤单绿/改址紫/取消红/重复黄/异常红）
                VStack(spacing: 4) {
                    if result.isAbnormal {
                        Text("异常")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.red)
                    }
                    if result.status == .duplicate || result.isDuplicate {
                        Text("重复")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    if result.isRejected {
                        Text("拒收")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    if result.isCancelled {
                        Text("撤单")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.green)
                    }
                    if result.isChangedAddr {
                        Text("改址")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.purple)
                    }
                    if result.isIntercepted {
                        Text("取消")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

                // 概要卡片（去掉"概要"小标题）
                VStack(spacing: 0) {
                    // 单号行（带复制按钮）
                    HStack {
                        Text("单号")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(result.mailNum)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Button {
                            copyMailNum()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                    divider

                    infoRow("状态代码", result.status.isFailed ? "" : formatStatusCode(result.statusCode, lastRemark: result.statusText))
                    divider

                    // 当前状态：与最后一条物流轨迹一致（时间/轨迹/所在省·市·机构）
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前状态")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let node = result.lastNode, !result.status.isFailed {
                            Text(node.time)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.blue)
                            Text(formatTraceText(node.info))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !node.province.isEmpty || !node.city.isEmpty || !node.org.isEmpty {
                                Text([node.province, node.city, node.org].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    divider

                    infoRow("物流行数", result.status.isFailed ? "" : "\(result.traceLen)")
                    divider

                    infoRow("历时", result.status.isFailed ? "" : result.durationText)
                    divider

                    infoRow("耗时", result.status.isFailed ? "" : result.durationToDeliverText)
                    divider

                    infoRow("投递员", result.status.isFailed ? "" : result.sender)
                }
                .padding(.horizontal, 16)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

                // 全部节点小标题 + 轨迹卡片（失败的时候不显示）
                if !result.status.isFailed {
                    HStack(spacing: 4) {
                        Text("全部节点")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("（\(result.traceLen)）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                    // 轨迹节点卡片：最新的在最上面
                    VStack(spacing: 0) {
                        ForEach(Array(result.traces.reversed().enumerated()), id: \.offset) { index, node in
                            VStack(alignment: .leading, spacing: 4) {
                                // 时间：蓝色字体，加粗，跟查询按钮一样
                                Text(node.time)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.blue)

                                // 轨迹信息：白色字体，遇到"〗"符号换行（去掉后面的逗号），字号跟概要一样
                                Text(formatTraceText(node.info))
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if !node.province.isEmpty || !node.city.isEmpty || !node.org.isEmpty {
                                    Text([node.province, node.city, node.org].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)

                            // 节点之间的分隔线（除了最后一个）
                            if index < result.traces.count - 1 {
                                divider
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }

                if result.traces.isEmpty {
                    Text(result.error?.isEmpty == false ? result.error! : "暂无轨迹数据")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding(.horizontal, 16)
            }
        }
        .textSelection(.disabled)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveEdgeSwipeBack { dismiss() }
        .background(
            Group {
                if colorScheme == .dark {
                    Color.black
                } else {
                    Color(UIColor.systemGroupedBackground)
                }
            }
            .ignoresSafeArea()
        )
    }

    private var divider: some View {
        Divider()
            .background(Color.secondary.opacity(0.3))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .textSelection(.disabled)
        }
        .padding(.vertical, 12)
    }

    private func copyMailNum() {
        UIPasteboard.general.string = result.mailNum
    }

    // 轨迹文本格式化：遇到"〗"符号换行，符号后面的逗号去掉
    private func formatTraceText(_ text: String) -> String {
        var result = text
        // 把"〗，"替换成"〗\n"（去掉逗号，换行）
        result = result.replacingOccurrences(of: "〗，", with: "〗\n")
        return result
    }
}
