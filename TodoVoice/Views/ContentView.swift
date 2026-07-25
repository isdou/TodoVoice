import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var todos: [TodoItem]
    @StateObject private var recorder = SpeechRecorder()
    @State private var showSheet = false
    @State private var autoStartFromShortcut = false
    @State private var editingItem: TodoItem? = nil

    private var activeTodos: [TodoItem] { todos.filter { !$0.isCompleted } }
    private var completedTodos: [TodoItem] { todos.filter(\.isCompleted) }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好 ☀️"
        case 12..<14: return "中午好 🍜"
        case 14..<18: return "下午好 ☕️"
        case 18..<22: return "晚上好 🌙"
        default: return "夜深了 ✨"
        }
    }
    
    private var todayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                XDBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        
                        if todos.isEmpty {
                            emptyState
                                .padding(.top, 20)
                        } else {
                            VStack(spacing: 28) {
                                if !activeTodos.isEmpty {
                                    TodoSection(
                                        title: "待完成",
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
                                        onTap: { editingItem = $0 }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 120)
                        }
                    }
                }
                
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [XD.bgBottom.opacity(0), XD.bgBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)
                    
                    Button {
                        autoStartFromShortcut = false
                        showSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 17, weight: .semibold))
                            Text("说话添加待办")
                                .font(XD.button)
                        }
                        .foregroundStyle(XD.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [XD.primaryYellow, XD.primaryYellowDeep],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: XD.primaryYellowDeep.opacity(0.25), radius: 12, x: 0, y: 6)
                                .overlay {
                                    Capsule()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                        .padding(0.5)
                                }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    
                    Rectangle()
                        .fill(XD.bgBottom)
                        .frame(height: 0)
                }
                .ignoresSafeArea(.keyboard)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
                .presentationDetents([.height(500), .large])
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
                if case .idle = new {} else { return }
            }
            .onChange(of: showSheet) { _, shown in
                if !shown {
                    recorder.cancelRecording()
                }
            }
        }
    }

    private func checkShortcutFlag() {
        if UserDefaults.standard.bool(forKey: "startRecordingFromShortcut") {
            UserDefaults.standard.set(false, forKey: "startRecordingFromShortcut")
            autoStartFromShortcut = true
            showSheet = true
        }
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(XD.textPrimary)
                Text(todayText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(XD.textSecondary)
            }
            Spacer()
            
            if !activeTodos.isEmpty {
                VStack(spacing: 2) {
                    Text("\(activeTodos.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(XD.primaryYellowDeep)
                    Text("待办")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(XD.textSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(XD.softYellow.opacity(0.5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(XD.primaryYellow.opacity(0.2), lineWidth: 1)
                        }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [XD.softYellow.opacity(0.6), XD.softYellow.opacity(0.2)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                Image(systemName: "checklist.checked")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [XD.primaryYellow, XD.primaryYellowDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 10) {
                Text("今天没有待办")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(XD.textPrimary)
                Text("按住下方麦克风按钮\n说话就能快速添加待办事项")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(XD.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct TodoSection: View {
    let title: String
    let count: Int
    let todos: [TodoItem]
    let onTap: (TodoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(XD.textPrimary)
                Text("\(count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(XD.primaryYellowDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(XD.softYellow.opacity(0.7), in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                ForEach(todos) { t in
                    TodoCardRow(todo: t) { onTap(t) }
                    if t.id != todos.last?.id {
                        Divider()
                            .overlay(XD.softDivider.opacity(0.6))
                            .padding(.leading, 60)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(XD.cardBg)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(XD.cardBorder.opacity(0.5), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: XD.warmShadow.opacity(0.8), radius: 16, x: 0, y: 6)
        }
    }
}

private struct TodoCardRow: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext
    var onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        todo.isCompleted.toggle()
                        if todo.isCompleted {
                            NotificationManager.shared.cancel(notificationId: todo.notificationId)
                        } else if let d = todo.dueDate {
                            Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
                            NotificationManager.shared.schedule(title: todo.title, dueDate: d, notificationId: todo.notificationId)
                        }
                    }
                } label: {
                    ZStack {
                        if todo.isCompleted {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [XD.success.opacity(0.8), XD.success],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 26, height: 26)
                                .shadow(color: XD.success.opacity(0.3), radius: 4, x: 0, y: 2)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .strokeBorder(XD.textTertiary.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.white.opacity(0.5)))
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(todo.title)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(todo.isCompleted ? XD.textTertiary : XD.textPrimary)
                        .strikethrough(todo.isCompleted, color: XD.textTertiary.opacity(0.6))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let d = todo.dueDate {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text(dueText(d))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle((isOverdue(d) && !todo.isCompleted) ? XD.danger : XD.textSecondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(XD.textTertiary.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
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
            .tint(XD.danger)
        }
        .swipeActions(edge: .leading) {
            Button { onTap() } label: { Label("编辑", systemImage: "pencil") }
                .tint(XD.primaryYellowDeep)
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
    private var isProcessing: Bool {
        if case .processing = recorder.state { return true }
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
        if isProcessing { return "处理中" }
        if isConfirm { return "确认待办" }
        if failedMessage != nil { return "录音失败" }
        return "新待办"
    }
    private var validCount: Int {
        items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                XDBackground()
                Group {
                    if isRecording { recordingBody }
                    else if isProcessing { processingBody }
                    else if isConfirm { confirmBody }
                    else if failedMessage != nil { errorBody }
                    else { idleBody }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(XD.textPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isProcessing {
                        Button("取消") {
                            recorder.cancelRecording()
                            items = []; didParse = false
                            onCancel(); dismiss()
                        }
                        .foregroundStyle(XD.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRecording {
                        Button("结束") { Task { await recorder.stopRecording() } }
                            .foregroundStyle(XD.danger)
                            .fontWeight(.semibold)
                    } else if isConfirm {
                        Button("保存") {
                            let valid = items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            onSave(valid); items = []; didParse = false; dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(XD.primaryYellowDeep)
                        .disabled(validCount == 0)
                    }
                }
            }
            .interactiveDismissDisabled(isProcessing)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    await recorder.startRecording()
                }
            }
            .onChange(of: recorder.state) { _, _ in parseFromRecorderIfNeeded() }
        }
    }

    private func parseFromRecorderIfNeeded() {
        guard isConfirm, !didParse else { return }
        let text = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items = TodoParser.parseMultiple(text)
        didParse = true
    }

    private var recordingBody: some View {
        VStack(spacing: 32) {
            Spacer().frame(height: 20)
            waveform.frame(height: 70).padding(.horizontal, 32)
            let live = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !live.isEmpty {
                Text(live)
                    .font(XD.body)
                    .foregroundStyle(XD.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .lineLimit(4)
            } else {
                Text("正在听你说话…")
                    .font(XD.subhead)
                    .foregroundStyle(XD.textSecondary)
            }
            Spacer()
            pushToTalkButton
            Text("按住说话，松开发送")
                .font(XD.caption)
                .foregroundStyle(XD.textTertiary)
            Spacer().frame(height: 10)
        }
    }
    
    private var processingBody: some View {
        VStack(spacing: 28) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(XD.softYellow.opacity(0.4))
                    .frame(width: 100, height: 100)
                
                ProgressView()
                    .controlSize(.large)
                    .tint(XD.primaryYellowDeep)
                    .scaleEffect(1.3)
            }
            
            VStack(spacing: 8) {
                Text("正在处理录音...")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(XD.textPrimary)
                Text("正在识别语音并拆分待办")
                    .font(XD.subhead)
                    .foregroundStyle(XD.textSecondary)
            }
            
            Spacer()
        }
        .padding(.bottom, 60)
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 4) {
            let levels = recorder.audioLevels.isEmpty ? Array(repeating: CGFloat(0.15), count: 28) : recorder.audioLevels
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                let height = (isRecording || isProcessing) ? max(8, level * 60) : 10
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [XD.primaryYellow, XD.primaryYellowDeep], startPoint: .bottom, endPoint: .top))
                    .frame(width: 4, height: height)
                    .animation(.spring(response: 0.12, dampingFraction: 0.7), value: height)
            }
        }
    }

    private var pushToTalkButton: some View {
        ZStack {
            Circle()
                .fill(XD.primaryYellow.opacity(holding ? 0.25 : 0.15))
                .scaleEffect(holding ? 1.5 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: holding)
                .frame(width: 130, height: 130)

            Image(systemName: holding ? "waveform" : "mic.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(XD.primaryYellowDeep)
                .frame(width: 88, height: 88)
                .background(
                    LinearGradient(colors: [XD.primaryYellow, XD.primaryYellowDeep], startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .shadow(color: XD.warmShadow, radius: 12, x: 0, y: 6)
                .scaleEffect(holding ? 0.92 : 1.0)
        }
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true
                    if !isRecording { Task { await recorder.startRecording() } }
                }
                .onEnded { _ in
                    guard holding else { return }
                    holding = false
                    if isRecording { Task { await recorder.stopRecording() } }
                }
        )
    }

    private var confirmBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("已自动拆分，点条目可编辑，左滑删除")
                    .font(XD.caption)
                    .foregroundStyle(XD.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ConfirmItemRow(
                            item: $items[index],
                            onDelete: { items.removeAll { $0.id == item.id } }
                        )
                        if item.id != items.last?.id {
                            Divider().overlay(XD.softDivider).padding(.leading, 52)
                        }
                    }
                }
                .xdCard()
                .padding(.horizontal, 16)

                Button {
                    items.append(ParsedTodo(title: "", dueDate: nil))
                } label: {
                    Label("添加待办", systemImage: "plus.circle")
                }
                .buttonStyle(XDOutlineButton())
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

    private var errorBody: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(XD.danger)
            Text("录音失败")
                .font(XD.title)
                .foregroundStyle(XD.textPrimary)
            Text(failedMessage ?? "请检查麦克风权限后重试")
                .font(XD.body)
                .foregroundStyle(XD.textSecondary)
                .multilineTextAlignment(.center)
            Button("重新录音") {
                didParse = false
                Task { await recorder.startRecording() }
            }
            .buttonStyle(XDYellowButton())
            .padding(.horizontal, 40)
            .padding(.top, 12)
            Spacer()
        }
        .padding(32)
    }

    private var idleBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("按住麦克风按钮开始说话")
                .font(XD.subhead)
                .foregroundStyle(XD.textSecondary)
            pushToTalkButton
            Spacer()
        }
    }
}

private struct ConfirmItemRow: View {
    @Binding var item: ParsedTodo
    var onDelete: () -> Void

    private var dateText: String? {
        guard let d = item.dueDate else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(d) { f.dateFormat = "HH:mm"; return "今天 " + f.string(from: d) }
        if Calendar.current.isDateInTomorrow(d) { f.dateFormat = "HH:mm"; return "明天 " + f.string(from: d) }
        f.dateFormat = "M/d HH:mm"; return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(XD.primaryYellow)
                .frame(width: 8, height: 8)

            TextField("待办内容", text: $item.title)
                .font(XD.body)
                .foregroundStyle(XD.textPrimary)

            if let text = dateText {
                Text(text)
                    .font(XD.caption)
                    .foregroundStyle(XD.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(XD.paleYellow, in: Capsule())
                Button {
                    item.dueDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(XD.textTertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
                .tint(XD.danger)
        }
    }
}
