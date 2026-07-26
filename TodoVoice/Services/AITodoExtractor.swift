import Foundation

actor AITodoExtractor {
    static let shared = AITodoExtractor()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func extract(
        transcript: String,
        apiKey: String,
        model: String = MiMoConfiguration.model,
        now: Date = Date()
    ) async throws -> [ParsedTodo] {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AITodoExtractionError.emptyTranscript }

        let requestBody = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt(now: now)),
                .init(role: "user", content: text)
            ],
            maxCompletionTokens: 1_024,
            temperature: 0.1,
            stream: false,
            responseFormat: .init(type: "json_object"),
            thinking: .init(type: "disabled")
        )

        let response: ChatResponse = try await perform(
            path: "chat/completions",
            method: "POST",
            apiKey: apiKey,
            body: requestBody
        )
        guard let content = response.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw AITodoExtractionError.invalidResponse
        }

        let payload: TodoPayload
        do {
            payload = try JSONDecoder().decode(TodoPayload.self, from: contentData)
        } catch {
            throw AITodoExtractionError.invalidStructuredOutput
        }

        var seenTitles = Set<String>()
        let items = payload.todos.prefix(12).compactMap { raw -> ParsedTodo? in
            let title = sanitizedTitle(raw.title)
            guard !title.isEmpty else { return nil }
            let normalized = title.lowercased()
            guard seenTitles.insert(normalized).inserted else { return nil }
            return ParsedTodo(title: title, dueDate: parseDate(raw.dueAt))
        }

        guard !items.isEmpty else { throw AITodoExtractionError.noTodoFound }
        return items
    }

    func validateConnection(
        apiKey: String,
        model: String = MiMoConfiguration.model
    ) async throws -> [String] {
        let response: ModelListResponse = try await perform(
            path: "models",
            method: "GET",
            apiKey: apiKey,
            body: Optional<EmptyBody>.none
        )
        let models = response.data.map(\.id)
        guard models.contains(model) else {
            throw AITodoExtractionError.modelUnavailable
        }
        return models
    }

    private func perform<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        apiKey: String,
        body: Body?
    ) async throws -> Response {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AITodoExtractionError.missingAPIKey }

        var request = URLRequest(url: MiMoConfiguration.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        var retryCount = 0
        while true {
            do {
                let (data, urlResponse) = try await session.data(for: request)
                guard let http = urlResponse as? HTTPURLResponse else {
                    throw AITodoExtractionError.invalidResponse
                }
                if (200..<300).contains(http.statusCode) {
                    do {
                        return try JSONDecoder().decode(Response.self, from: data)
                    } catch {
                        throw AITodoExtractionError.invalidResponse
                    }
                }

                if retryCount == 0 && (http.statusCode == 429 || (500...599).contains(http.statusCode)) {
                    retryCount += 1
                    try await Task.sleep(for: .milliseconds(650))
                    continue
                }

                let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
                throw AITodoExtractionError.http(status: http.statusCode, message: message)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AITodoExtractionError {
                throw error
            } catch {
                throw AITodoExtractionError.networkUnavailable
            }
        }
    }

    private func systemPrompt(now: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        let calendar = Calendar.current
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: now) - 1]

        return """
        你是 MiMo，也是“小豆语音待办”的待办意图提取器。
        当前日期时间：\(formatter.string(from: now))，\(weekday)。用户时区：\(TimeZone.current.identifier)。

        从用户口语转写中提取明确要做、要提醒或要跟进的事情。用户可能重复、改口、插入背景信息，句子也可能很碎。
        规则：
        1. 拆成互相独立、可以执行的待办，最多 12 项；不要把寒暄、解释、情绪或已完成的事情当待办。
        2. 标题简洁自然，保留必要的人名、地点、对象、数量和动作；去掉“我想、记得、然后、那个”等口头词和时间表达。
        3. 相对时间必须结合当前日期解析。明确时刻时按原意；只有日期没有时刻时使用当地时间 09:00；没有任何时间线索时 due_at 为 null；不要猜测含糊时间。
        4. 不要把前一项的时间机械复制给后一项。“做完 A 再做 B”只表示顺序，若 B 没有自己的明确时间，B 的 due_at 为 null。
        5. due_at 必须是带时区的 RFC 3339 字符串，例如 2026-07-27T15:00:00+08:00，或 null。
        6. 用户改口时采用最后一次明确表达；合并语义重复项；不得补充用户没有表达的任务。
        7. 只返回合法 JSON，不要解释、注释或 Markdown。

        返回结构：
        {"todos":[{"title":"string","due_at":"RFC3339 string or null"}]}

        示例输入：“2026年7月27日下午三点去拿快递，拿完给小王发合同。”
        示例输出：{"todos":[{"title":"去拿快递","due_at":"2026-07-27T15:00:00+08:00"},{"title":"给小王发合同","due_at":null}]}
        """
    }

    private func sanitizedTitle(_ value: String) -> String {
        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(collapsed.prefix(120))
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

enum AITodoExtractionError: LocalizedError {
    case missingAPIKey
    case emptyTranscript
    case networkUnavailable
    case invalidResponse
    case invalidStructuredOutput
    case noTodoFound
    case modelUnavailable
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "还没有配置 MiMo API Key"
        case .emptyTranscript:
            return "没有可整理的语音文字"
        case .networkUnavailable:
            return "网络暂时不可用"
        case .invalidResponse, .invalidStructuredOutput:
            return "AI 返回的内容暂时无法解析"
        case .noTodoFound:
            return "AI 没有识别到明确待办"
        case .modelUnavailable:
            return "当前套餐暂不支持 MiMo 2.5"
        case let .http(status, message):
            if status == 401 || status == 403 { return "API Key 无效或没有权限" }
            if status == 429 { return "AI 请求太频繁，请稍后再试" }
            if let message, !message.isEmpty { return "AI 服务错误（\(status)）：\(message)" }
            return "AI 服务暂时不可用（\(status)）"
        }
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable { let type: String }
    struct Thinking: Encodable { let type: String }

    let model: String
    let messages: [Message]
    let maxCompletionTokens: Int
    let temperature: Double
    let stream: Bool
    let responseFormat: ResponseFormat
    let thinking: Thinking

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, thinking
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct TodoPayload: Decodable {
    struct Todo: Decodable {
        let title: String
        let dueAt: String?

        enum CodingKeys: String, CodingKey {
            case title
            case dueAt = "due_at"
        }
    }
    let todos: [Todo]
}

private struct ModelListResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String? }
    let error: APIError
}

private struct EmptyBody: Encodable {}
