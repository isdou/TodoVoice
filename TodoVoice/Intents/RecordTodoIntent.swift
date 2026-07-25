import AppIntents

struct RecordTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "录音创建待办"
    static let description = IntentDescription("打开 TodoVoice 并立即开始录音，将语音转换成待办。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: "startRecordingFromShortcut")
        return .result(dialog: "正在打开 TodoVoice 录音")
    }
}

struct TodoVoiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordTodoIntent(),
            phrases: [
                "用 \(.applicationName) 记个待办",
                "用 \(.applicationName) 录音",
                "在 \(.applicationName) 添加待办"
            ],
            shortTitle: "录音创建待办",
            systemImageName: "waveform.badge.mic"
        )
    }
}
