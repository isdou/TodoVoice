import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var todos: [TodoItem]
    @StateObject private var recorder = SpeechRecorder()
    @State private var showSheet = false
    @State private var sheetMode: SheetMode = .idle

    @State private var autoStartFromShortcut = false
    @State private var editingItem: TodoItem? = nil

    private var activeTodos: [TodoItem] { todos.filter { !$0.isCompleted } }
    private var completedTodos: [TodoItem] { todos.filter(\.isCompleted) }

    enum SheetMode { case idle, recording, confirm }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    if todos.isEmpty {
                        emptyState.frame(maxHeight: .infinity)
                    } else {
                        todoList
                    }
                }
            }
            .navigationTitle("我的待办")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                recordEntryButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Color(.systemGroupedBackground))
            }
            .sheet(isPresented: $showSheet) {
                RecordingSheet(
                    recorder: recorder,
                    isAutoStarted: autoStartFromShortcut,
                    onCancel: {
                        recorder.cancelRecording()
                        autoStartFromShortcut = false
                    },
                    onSave: { items in
                        Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
                        for it in items {
                            let t = it.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { continue }
                            let item = TodoItem(title: t, dueDate: it.dueDate, transcript: t)
                            modelContext.insert(item)
                            if let date = it.dueDate {
                                NotificationManager.shared.schedule(
                                    title: t, dueDate: date, notificationId: item.notificationId
                                )
                            }
                        }
                        autoStartFromShortcut = false
                    }
                )
                .presentationDetents([.height(480), .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
            }
            .sheet(item: $editingItem) { item in
                TodoEditView(
                    todo: item,
                    onSave: {
                        if let due = item.dueDate {
                            NotificationManager.shared.schedule(
                                title: item.title, dueDate: due, notificationId: item.notificationId
                            )
                        } else {
                            NotificationManager.shared.cancel(notificationId: item.notificationId)
                        }
                    },
                    onDelete: {
                        NotificationManager.shared.cancel(notificationId: item.notificationId)
                        modelContext.delete(item)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task { checkShortcutFlag() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                checkShortcutFlag()
            }
            .onChange(of: recorder.state) { _, new in
                handleState(new)
            }
            .onChange(of: showSheet) { _, shown in
                if !shown {
                    recorder.cancelRecording()
                    sheetMode = .idle
                }
            }
        }
    }

    private func handleState(_ new: SpeechRecorder.State) {
        switch new {
        case .recording:
            sheetMode = .recording
        case .processing:
            break
        case .readyToConfirm, .failed:
            let hasText = !recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasText {
                sheetMode = .confirm
            }
        case .idle:
            break
        }
    }

    private func checkShortcutFlag() {
        if UserDefaults.standard.bool(forKey: "startRecordingFromShortcut") {
            UserDefaults.standard.set(false, forKey: "startRecordingFromShortcut")
            autoStartFromShortcut = true
            showSheet = true
        }
    }

    private var recordEntryButton: some View {
        Button {
            autoStartFromShortcut = false
            showSheet = true
        } label: {
            Label("轻点说话添加待办", systemImage: "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无待办", systemImage: "checklist")
        } description: {
            Text("轻点下方按钮开始语音添加待办")
        }
    }

    private var todoList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                if !activeTodos.isEmpty {
                    TodoSection(
                        title: "进行中",
                        count: activeTodos.count,
                        todos: activeTodos,
                        onTap: { editingItem = $0 }
                    )
                }
                if !completedTodos.isEmpty {
                    TodoSection(
                        title: "已完成",
                        count: completedTodos.count,
                        todos: completedTodos,
                        onTap: { editingItem = $0 },
                        topPadding: activeTodos.isEmpty ? 0 : 20
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Todo Section

private struct TodoSection: View {
    let title: String
    let count: Int
    let todos: [TodoItem]
    let onTap: (TodoItem) -> Void
    var topPadding: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if topPadding > 0 { Spacer().frame(height: topPadding) }
            HStack(spacing: 6) {
                Text(title).font(.headline).fontWeight(.semibold)
                Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(todos) { t in
                    TodoCardRow(todo: t) { onTap(t) }
                    if t.id != todos.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Todo Card Row (native list style)

private struct TodoCardRow: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    var onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        todo.isCompleted.toggle()
                        if todo.isCompleted {
                            NotificationManager.shared.cancel(notificationId: todo.notificationId)
                        } else if let d = todo.dueDate {
                            Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
                            NotificationManager.shared.schedule(title: todo.title, dueDate: d, notificationId: todo.notificationId)
                        }
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(todo.isCompleted ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title)
                        .font(.body)
                        .foregroundStyle(todo.isCompleted ? Color.secondary.opacity(0.6) : Color.primary)
                        .strikethrough(todo.isCompleted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let d = todo.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(dueText(d))
                                .font(.caption)
                        }
                        .foregroundStyle((isOverdue(d) && !todo.isCompleted) ? Color.red : Color.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onTap() } label: { Label("编辑", systemImage: "pencil") }
            Button(role: .destructive) {
                NotificationManager.shared.cancel(notificationId: todo.notificationId)
                withAnimation { modelContext.delete(todo) }
            } label: { Label("删除", systemImage: "trash") }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                NotificationManager.shared.cancel(notificationId: todo.notificationId)
                withAnimation { modelContext.delete(todo) }
            } label: { Label("删除", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { onTap() } label: { Label("编辑", systemImage: "pencil") }
                .tint(.accentColor)
        }
    }

    private func dueText(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(d) { f.dateFormat = "今天 HH:mm" }
        else if Calendar.current.isDateInTomorrow(d) { f.dateFormat = "明天 HH:mm" }
        else { f.dateFormat = "M月d日 HH:mm" }
        return f.string(from: d)
    }
    private func isOverdue(_ d: Date) -> Bool { d < Date() }
}

// MARK: - Recording Sheet

private struct RecordingSheet: View {
    @ObservedObject var recorder: SpeechRecorder
    let isAutoStarted: Bool
    let onCancel: () -> Void
    let onSave: ([ParsedTodo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ParsedTodo] = []
    @State private var holding = false
    @State private var didParse = false

    private var isRecording: Bool {
        if case .recording = recorder.state { return true }
        return false
    }
    private var isConfirm: Bool {
        if case .readyToConfirm = recorder.state { return true }
        if case .failed = recorder.state {
            return !recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
    private var failedMessage: String? {
        if case let .failed(msg) = recorder.state,
           recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return msg
        }
        return nil
    }

    private var navigationTitle: String {
        if isRecording { return "正在聆听" }
        if isConfirm { return "确认待办" }
        if failedMessage != nil { return "录音失败" }
        return "新待办"
    }

    private var validCount: Int {
        items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isRecording {
                    recordingBody
                } else if isConfirm {
                    confirmBody
                } else if failedMessage != nil {
                    errorBody
                } else {
                    idleBody
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        recorder.cancelRecording()
                        items = []
                        didParse = false
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRecording {
                        Button("结束") {
                            Task { await recorder.stopRecording() }
                        }
                        .foregroundStyle(.red)
                    } else if isConfirm {
                        Button("保存") {
                            let valid = items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            onSave(valid)
                            items = []
                            didParse = false
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(validCount == 0)
                    }
                }
            }
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    await recorder.startRecording()
                }
            }
            .onChange(of: recorder.state) { _, new in
                parseFromRecorderIfNeeded()
            }
        }
    }

    private func parseFromRecorderIfNeeded() {
        guard isConfirm, !didParse else { return }
        let text = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items = TodoParser.parseMultiple(text)
        didParse = true
    }

    // MARK: Recording body

    private var recordingBody: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 40)

            waveform.frame(height: 60).padding(.horizontal, 32)

            let live = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !live.isEmpty {
                Text(live)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineLimit(4)
            } else {
                Text("正在听你说话…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            pushToTalkButton
            Spacer().frame(height: 20)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            let levels = recorder.audioLevels.isEmpty ? Array(repeating: CGFloat(0.15), count: 28) : recorder.audioLevels
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                let height = isRecording ? max(6, level * 52) : 8
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tint)
                    .frame(width: 3, height: height)
                    .animation(.spring(response: 0.12, dampingFraction: 0.7), value: height)
            }
        }
    }

    private var pushToTalkButton: some View {
        ZStack {
            Circle()
                .fill(.tint.opacity(holding ? 0.18 : 0.1))
                .scaleEffect(holding ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: holding)
                .frame(width: 120, height: 120)

            Image(systemName: holding ? "waveform" : "mic.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: holding)
                .frame(width: 80, height: 80)
                .background(.tint.opacity(0.12), in: Circle())
                .scaleEffect(holding ? 0.9 : 1.0)
        }
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true
                    if !isRecording {
                        Task { await recorder.startRecording() }
                    }
                }
                .onEnded { _ in
                    guard holding else { return }
                    holding = false
                    if isRecording {
                        Task { await recorder.stopRecording() }
                    }
                }
        )
    }

    // MARK: Confirm body - 修复闪退：使用 ScrollView + 手动卡片，不用 List/ForEach 绑定

    private var confirmBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("已自动拆分，点条目可编辑，左滑删除")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ConfirmItemRow(
                            item: $items[index],
                            onDelete: {
                                items.removeAll { $0.id == item.id }
                            }
                        )
                        if item.id != items.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)

                Button {
                    items.append(ParsedTodo(title: "", dueDate: nil))
                } label: {
                    Label("添加待办", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(d) { f.dateFormat = "HH:mm"; return "今天 " + f.string(from: d) }
        if Calendar.current.isDateInTomorrow(d) { f.dateFormat = "HH:mm"; return "明天 " + f.string(from: d) }
        f.dateFormat = "M/d HH:mm"; return f.string(from: d)
    }

    // MARK: Error body

    private var errorBody: some View {
        ContentUnavailableView {
            Label("录音失败", systemImage: "mic.slash")
        } description: {
            Text(failedMessage ?? "请检查麦克风权限后重试")
        } actions: {
            Button("重新录音") {
                didParse = false
                Task { await recorder.startRecording() }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    // MARK: Idle body

    private var idleBody: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("按住麦克风按钮开始说话").font(.body).foregroundStyle(.secondary)
            pushToTalkButton
            Spacer()
        }
    }
}

// MARK: - 确认页单行（稳定实现，避免绑定崩溃）

private struct ConfirmItemRow: View {
    @Binding var item: ParsedTodo
    var onDelete: () -> Void

    private var dateText: String? {
        guard let d = item.dueDate else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(d) { f.dateFormat = "HH:mm"; return "今天 " + f.string(from: d) }
        if Calendar.current.isDateInTomorrow(d) { f.dateFormat = "HH:mm"; return "明天 " + f.string(from: d) }
        f.dateFormat = "M/d HH:mm"; return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 8, height: 8)

            TextField("待办内容", text: $item.title)
                .font(.body)

            if let text = dateText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule())

                Button {
                    item.dueDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: { Label("删除", systemImage: "trash") }
        }
    }
}
