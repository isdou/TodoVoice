import SwiftUI
import SwiftData

struct TodoEditView: View {
    @Bindable var todo: TodoItem
    var onSave: () -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasDate: Bool = false
    @State private var selectedDate: Date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                XDBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("待办内容")
                                .font(XD.headline)
                                .foregroundStyle(XD.textPrimary)
                            TextField("待办内容", text: $todo.title, axis: .vertical)
                                .font(XD.body)
                                .foregroundStyle(XD.textPrimary)
                                .lineLimit(3...6)
                                .padding(16)
                                .background(XD.cardBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: XD.cornerMedium, style: .continuous)
                                        .stroke(XD.cardBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: XD.cornerMedium, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("提醒")
                                .font(XD.headline)
                                .foregroundStyle(XD.textPrimary)

                            VStack(spacing: 0) {
                                Toggle("设置提醒时间", isOn: $hasDate)
                                    .font(XD.body)
                                    .foregroundStyle(XD.textPrimary)
                                    .tint(XD.primaryYellowDeep)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)

                                if hasDate {
                                    Divider().overlay(XD.softDivider).padding(.leading, 16)
                                    DatePicker(
                                        "提醒时间",
                                        selection: $selectedDate,
                                        in: Date()...,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .datePickerStyle(.graphical)
                                    .tint(XD.primaryYellowDeep)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                            }
                            .xdCard()
                        }

                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("删除待办", systemImage: "trash")
                        }
                        .buttonStyle(XDOutlineButton())
                        .padding(.top, 8)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(XD.textPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(XD.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(XD.primaryYellowDeep)
                    .disabled(todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
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
        let trimmed = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todo.title = trimmed
        todo.dueDate = hasDate ? selectedDate : nil
        onSave()
    }
}
