import SwiftUI

struct AISettingsView: View {
    @ObservedObject var settings: AISettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var status: TestStatus?

    var body: some View {
        NavigationStack {
            ZStack {
                XDBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        introCard
                        configurationCard
                        privacyCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("AI 智能整理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(XD.primaryYellowDeep)
                }
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [XD.primaryYellow, XD.primaryYellowDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("听懂碎话，再拆成待办")
                        .font(XD.headline)
                        .foregroundStyle(XD.textPrimary)
                    Text("由 Xiaomi MiMo 2.5 提供意图提取")
                        .font(XD.caption)
                        .foregroundStyle(XD.textSecondary)
                }
            }

            Text("比如“明天下午先拿快递，回来把合同发给小王，周五前报销”，会自动拆成三项并识别时间。")
                .font(XD.subhead)
                .foregroundStyle(XD.textSecondary)
                .lineSpacing(4)
        }
        .padding(18)
        .xdCard()
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settings.isEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("启用 AI 智能整理")
                        .font(XD.headline)
                        .foregroundStyle(XD.textPrimary)
                    Text(settings.hasAPIKey ? "接口异常时会自动使用本地整理" : "先在下方安全保存 API Key")
                        .font(XD.caption)
                        .foregroundStyle(XD.textSecondary)
                }
            }
            .tint(XD.primaryYellowDeep)
            .disabled(!settings.hasAPIKey)

            Divider().overlay(XD.softDivider)

            VStack(alignment: .leading, spacing: 8) {
                Text("MiMo API Key")
                    .font(XD.subhead)
                    .foregroundStyle(XD.textPrimary)

                SecureField(settings.hasAPIKey ? "已保存；输入新密钥可替换" : "tp-…", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, design: .monospaced))
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(XD.cardBorder, lineWidth: 1)
                    }

                if settings.hasAPIKey {
                    Label("已保存在本机钥匙串", systemImage: "lock.fill")
                        .font(XD.caption)
                        .foregroundStyle(XD.success)
                }
            }

            HStack(spacing: 10) {
                Button {
                    saveKey()
                } label: {
                    Text(settings.hasAPIKey ? "更新密钥" : "保存密钥")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(XDOutlineButton())
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    testAI()
                } label: {
                    Group {
                        if isTesting {
                            ProgressView().tint(XD.textPrimary)
                        } else {
                            Text("测试 AI")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(XDYellowButton())
                .disabled(isTesting || (!settings.hasAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }

            if let status {
                Label(status.message, systemImage: status.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(XD.caption)
                    .foregroundStyle(status.isSuccess ? XD.success : XD.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.hasAPIKey {
                Button(role: .destructive) {
                    settings.removeAPIKey()
                    apiKey = ""
                    status = nil
                } label: {
                    Text("移除本机密钥")
                        .font(XD.caption)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .xdCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("隐私说明", systemImage: "hand.raised.fill")
                .font(XD.headline)
                .foregroundStyle(XD.textPrimary)

            Text("开启后，仅将 Apple 语音识别得到的文字发送给 Xiaomi MiMo；原始录音不会上传。密钥只保存在这台设备的钥匙串中。")
                .font(XD.caption)
                .foregroundStyle(XD.textSecondary)
                .lineSpacing(4)

            Text("接口：token-plan-cn.xiaomimimo.com · 模型：mimo-v2.5")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(XD.textTertiary)
        }
        .padding(18)
        .xdCard()
    }

    private func saveKey() {
        do {
            try settings.saveAPIKey(apiKey)
            apiKey = ""
            status = TestStatus(isSuccess: true, message: "密钥已安全保存，AI 整理已开启")
        } catch {
            status = TestStatus(isSuccess: false, message: error.localizedDescription)
        }
    }

    private func testAI() {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try settings.saveAPIKey(apiKey)
                apiKey = ""
            } catch {
                status = TestStatus(isSuccess: false, message: error.localizedDescription)
                return
            }
        }

        guard let key = settings.apiKey() else {
            status = TestStatus(isSuccess: false, message: "请先保存 API Key")
            return
        }

        isTesting = true
        status = nil
        Task {
            do {
                _ = try await AITodoExtractor.shared.validateConnection(apiKey: key)
                let sample = try await AITodoExtractor.shared.extract(
                    transcript: "明天下午三点去拿快递，拿完以后把合同发给小王，周五之前记得报销差旅费",
                    apiKey: key
                )
                let titles = sample.map(\.title).joined(separator: "、")
                status = TestStatus(isSuccess: true, message: "连接成功，示例识别为：\(titles)")
            } catch {
                status = TestStatus(isSuccess: false, message: error.localizedDescription)
            }
            isTesting = false
        }
    }
}

private struct TestStatus {
    let isSuccess: Bool
    let message: String
}
