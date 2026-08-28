import SwiftUI
import UIKit

// MARK: - 排队收件箱（session/queue 快照 + session.updateQueue）

struct ConversationQueueSheet: View {
    let items: [GatewayQueueItem]
    let onAction: (String, DshQueueAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingItem: GatewayQueueItem?
    @State private var editText = ""

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("没有排队中的消息")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(placementTitle(item.placement))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(item.placement == "steering" ? DSHColor.orange : DSHColor.ocean)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background((item.placement == "steering" ? DSHColor.orange : DSHColor.ocean).opacity(0.14), in: Capsule())
                                    Spacer()
                                }
                                Text(item.text.isEmpty ? "（图片消息）" : item.text)
                                    .font(.subheadline)
                                    .lineLimit(4)
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    onAction(item.id, .remove)
                                } label: {
                                    Label("移除", systemImage: "trash")
                                }
                                Button {
                                    onAction(item.id, .steer)
                                } label: {
                                    Label("插队", systemImage: "arrow.up.circle")
                                }
                                .tint(DSHColor.orange)
                            }
                            .contextMenu {
                                Button {
                                    editText = item.text
                                    editingItem = item
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Button {
                                    onAction(item.id, .steer)
                                } label: {
                                    Label("插队发送", systemImage: "arrow.up.circle")
                                }
                                Button(role: .destructive) {
                                    onAction(item.id, .remove)
                                } label: {
                                    Label("移除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("排队消息 · \(items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("编辑排队消息", isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            TextField("消息内容", text: $editText, axis: .vertical)
                .lineLimit(3...8)
            Button("保存") {
                if let item = editingItem {
                    onAction(item.id, .edit(text: editText))
                }
                editingItem = nil
            }
            Button("取消", role: .cancel) { editingItem = nil }
        }
    }

    private func placementTitle(_ placement: String?) -> String {
        switch placement {
        case "steering": return "插队中"
        case "context": return "上下文"
        default: return "排队中"
        }
    }
}

// MARK: - 子代理面板（subagent.*）

struct SubagentSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let parentId = store.selectedSessionId {
                    let entries = (store.subagentEntries[parentId] ?? [])
                        .compactMap { $0.decode(GatewaySubagentEntry.self) }
                    if entries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text("该会话暂无子代理")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(entries) { entry in
                                NavigationLink {
                                    SubagentDetailView(parentId: parentId, entry: entry)
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(entry.activity == "running" ? DSHColor.success : Color.secondary.opacity(0.5))
                                            .frame(width: 7, height: 7)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.label ?? String(entry.id.prefix(16)))
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)
                                            Text(subtitle(for: entry))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("子代理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let id = store.selectedSessionId { store.loadSubagents(for: id) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if let id = store.selectedSessionId { store.loadSubagents(for: id) }
        }
    }

    private func subtitle(for entry: GatewaySubagentEntry) -> String {
        if entry.kind == "diagnostic" {
            switch entry.reason {
            case "corrupt": return "记录损坏"
            case "unsupported": return "不支持"
            default: return "不可用"
            }
        }
        let mode = entry.mode == "continuable" ? "可持续" : "一次性"
        let activity = entry.activity == "running" ? "运行中" : "空闲"
        return "\(mode) · \(activity)"
    }
}

private struct SubagentDetailView: View {
    @EnvironmentObject private var store: AppStore
    let parentId: String
    let entry: GatewaySubagentEntry
    @State private var lines: [SubagentTranscriptLine] = []
    @State private var isLoading = false
    @State private var draft = ""
    @State private var isSending = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if isLoading && lines.isEmpty {
                        ProgressView("正在加载子代理记录…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(lines) { line in
                        VStack(alignment: line.isMine ? .trailing : .leading, spacing: 3) {
                            Text(line.role)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(line.isMine ? DSHColor.ocean.opacity(0.16) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .frame(maxWidth: .infinity, alignment: line.isMine ? .trailing : .leading)
                        .id(line.id)
                    }
                }
                .padding(14)
            }
            .onAppear { proxy.scrollTo(lines.last?.id, anchor: .bottom) }
        }
        .navigationTitle(entry.label ?? "子代理")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if entry.mode == "continuable" {
                HStack(spacing: 8) {
                    TextField("发送给子代理…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : DSHColor.ocean, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .toolbar {
            if entry.mode == "continuable" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        Task { await store.interruptSubagent(childSessionId: entry.id, mode: entry.mode ?? "continuable") }
                    } label: {
                        Label("中断", systemImage: "stop.circle")
                    }
                }
            }
        }
        .task { await loadHistory() }
    }

    private func loadHistory() async {
        guard lines.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let events = await store.loadSubagentHistory(
            parentSessionId: parentId,
            childSessionId: entry.id,
            mode: entry.mode ?? "one-shot"
        )
        lines = events.compactMap { event in
            guard let text = Self.text(of: event), !text.isEmpty else { return nil }
            let isMine = event.type == "user/message"
            return SubagentTranscriptLine(
                id: "\(event.seq)",
                role: isMine ? "我" : "子代理",
                text: text,
                isMine: isMine
            )
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        Task {
            let ok = await store.promptSubagent(childSessionId: entry.id, mode: entry.mode ?? "continuable", text: text)
            await MainActor.run {
                isSending = false
                if ok {
                    draft = ""
                    lines.append(SubagentTranscriptLine(id: UUID().uuidString, role: "我", text: text, isMine: true))
                }
            }
        }
    }

    private static func text(of event: RawSessionEvent) -> String? {
        if let direct = event.data["text"]?.stringValue { return direct }
        let parts = event.data["content"]?.arrayValue ?? []
        let joined = parts.compactMap { $0["text"]?.stringValue }.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}

private struct SubagentTranscriptLine: Identifiable, Hashable {
    let id: String
    let role: String
    let text: String
    let isMine: Bool
}

// MARK: - 协议通知中心（protocolNotices 展示）

struct NoticeListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.protocolNotices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("暂无通知")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.protocolNotices.reversed()) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: item.isError ? "exclamationmark.triangle.fill" : "bell.fill")
                                        .font(.caption)
                                        .foregroundStyle(item.isError ? Color.red : DSHColor.ocean)
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("通知中心 · \(store.protocolNotices.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { store.markNoticesSeen() }
    }
}

// MARK: - 系统分享面板（会话导出 ZIP）

struct ActivityViewRepresentable: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
