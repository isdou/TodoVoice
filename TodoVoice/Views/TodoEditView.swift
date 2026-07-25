import SwiftUI
import SwiftData

struct TodoEditView: View {
    @Bindable var todo: TodoItem
    var onSave: () -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var hasDate: Bool = false
    @State private var selectedDate: Date = Date()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("待办内容", text: $title, axis: .vertical)
                        .font(.body)
                        .lineLimit(3...6)
                } header: {
                    Text("待办内容")
                }

                Section {
                    Toggle("设置提醒时间", isOn: $hasDate)
                        .tint(.accentColor)
                    if hasDate {
                        DatePicker(
                            "提醒时间",
                            selection: $selectedDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                    }
                } header: {
                    Text("提醒")
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("删除待办", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                title = todo.title
                if let due = todo.dueDate {
                    hasDate = true
                    selectedDate = max(due, Date())
                } else {
                    hasDate = false
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todo.title = trimmed
        todo.dueDate = hasDate ? selectedDate : nil
        onSave()
    }
}
