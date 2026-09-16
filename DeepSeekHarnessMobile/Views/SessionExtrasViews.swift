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
        .presentationBackground(.regularMaterial)
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
        .presentationBackground(.regularMaterial)
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

// MARK: - 任务 / 目标面板（输入框上方占位，对齐安卓 TaskGoalUi）

// 输入框上方的任务/目标面板：直接占位把对话顶上去（高度计入 composerHeight），
// 而不是盖在正在执行的对话上。complete 的目标只留作历史，不再占位。
struct TaskGoalPanels: View {
    @EnvironmentObject private var store: AppStore
    @State private var tasksExpanded = false
    @State private var showGoalEditor = false
    @State private var confirmGoalClear = false
    @State private var goalDraft = ""

    private var tasks: [GatewayTask]? {
        store.selectedSessionId.flatMap { store.taskSnapshots[$0]?.tasks }
    }

    private var goal: GatewayGoalDefinition? {
        guard let definition = store.selectedSessionId.flatMap({ store.goalSnapshots[$0]?.goal?.goal }),
              definition.phase.lowercased() != "complete" else { return nil }
        return definition
    }

    var body: some View {
        if tasks != nil || goal != nil {
            VStack(spacing: 8) {
                if let tasks {
                    TaskPanel(tasks: tasks, expanded: $tasksExpanded)
                }
                if let goal {
                    GoalPanel(
                        phase: goal.phase,
                        objective: goal.objective,
                        mutationKind: store.goalMutationKind,
                        onPauseResume: {
                            if goal.phase == "active" { store.pauseGoal() }
                            else { store.resumeGoal() }
                        },
                        onEdit: {
                            goalDraft = goal.objective
                            showGoalEditor = true
                        },
                        onClear: { confirmGoalClear = true }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .id(store.selectedSessionId)
            .alert("编辑目标", isPresented: $showGoalEditor) {
                TextField("目标", text: $goalDraft, axis: .vertical)
                    .lineLimit(3...6)
                Button("保存") {
                    store.editGoal(goalDraft)
                    showGoalEditor = false
                }
                Button("取消", role: .cancel) { showGoalEditor = false }
            }
            .alert("删除当前目标？", isPresented: $confirmGoalClear) {
                Button("删除", role: .destructive) {
                    confirmGoalClear = false
                    store.clearGoal()
                }
                Button("取消", role: .cancel) { confirmGoalClear = false }
            } message: {
                Text("删除后，智能体不再持有这个持续目标。")
            }
        }
    }
}

private struct TaskPanel: View {
    let tasks: [GatewayTask]
    @Binding var expanded: Bool

    private var completed: Int { tasks.filter { $0.status == "completed" }.count }
    private var active: Int { tasks.filter { $0.status == "in_progress" }.count }

    private var summary: String {
        var parts: [String] = []
        if completed > 0 { parts.append("\(completed) 已完成") }
        if active > 0 { parts.append("\(active) 进行中") }
        let pending = tasks.count - completed - active
        if pending > 0 { parts.append("\(pending) 待处理") }
        return parts.joined(separator: " · ").isEmpty ? "暂无任务" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("任务")
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 0 : 180))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "收起任务" : "展开任务")

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tasks.indices, id: \.self) { index in
                        TaskRow(task: tasks[index])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct TaskRow: View {
    let task: GatewayTask

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch task.status {
                case "completed":
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case "in_progress":
                    ProgressView()
                        .controlSize(.small)
                        .tint(DSHColor.ocean)
                default:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 18))
            .frame(width: 24, height: 24)
            Text(task.content)
                .font(.body)
                .foregroundStyle(task.status == "completed" ? .secondary : .primary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GoalPanel: View {
    let phase: String
    let objective: String
    let mutationKind: String?
    let onPauseResume: () -> Void
    let onEdit: () -> Void
    let onClear: () -> Void

    private var isActive: Bool { phase == "active" }

    private var phaseLabel: String {
        switch phase {
        case "active": "进行中的目标"
        case "paused": "已暂停的目标"
        case "blocked": "受阻的目标"
        default: "当前目标"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(phaseLabel)
                .font(.headline)
            Text(objective)
                .font(.body)
                .lineLimit(2)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if mutationKind != nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(DSHColor.ocean)
                    .frame(width: 36, height: 36)
            } else {
                goalButton(systemName: isActive ? "pause.circle" : "play.circle", label: isActive ? "暂停目标" : "继续目标", action: onPauseResume)
                goalButton(systemName: "pencil.line", label: "编辑目标", action: onEdit)
                goalButton(systemName: "trash", label: "删除目标", action: onClear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func goalButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 协议通知中心（protocolNotices 展示）

struct NoticeListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
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
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(store.protocolNotices.reversed()) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Image(systemName: item.isError ? "exclamationmark.triangle.fill" : "bell.fill")
                                                .font(.caption)
                                                .foregroundStyle(item.isError ? Color.red : DSHColor.ocean)
                                            Text(item.title)
                                                .font(.subheadline.weight(.medium))
                                                // 绝对颜色：.primary/.secondary 是相对层级样式，
                                                // 会被 presenting 方的 .white 污染漂白。
                                                .foregroundStyle(Color(uiColor: .label))
                                                .lineLimit(1)
                                            Spacer()
                                            Text(item.date, style: .time)
                                                .font(.caption2)
                                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                        }
                                        Text(item.text)
                                            .font(.caption)
                                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                                            .lineLimit(3)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
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
        .presentationBackground(.regularMaterial)
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
