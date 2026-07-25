//
//  TodoParser.swift
//  TodoVoice
//
//  待办解析器：结构化提取 + 意图分类
//

import Foundation
import NaturalLanguage

struct ParsedTodo: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var dueDate: Date?
}

final class TodoParser {

    private static let strongConnectors: Set<String> = [
        "然后", "接着", "之后", "完了", "还有", "另外", "此外",
        "并且", "同时", "顺便", "对了", "再就是", "接下来",
        "第一", "第二", "第三", "首先", "其次", "最后",
        "哦对", "还得", "还要", "也得", "也要", "别忘了",
        "还有一个", "还有件事"
    ]

    static func parseMultiple(_ transcript: String) -> [ParsedTodo] {
        let normalized = preprocess(transcript)
        guard !normalized.isEmpty else { return [] }

        // 1. 切分片段
        var segments = splitSegments(normalized)

        // 2. 每个片段里提取时间，清理标题
        segments = segments.map { seg in
            var s = seg
            let (clean, date) = extractAndRemoveDate(from: s.text)
            s.text = cleanTitle(clean)
            s.date = date
            return s
        }

        // 3. 日期传播：前一个的日期向后传递
        segments = propagateDateContext(segments)

        // 4. 过滤空结果
        let result = segments
            .filter { !$0.text.isEmpty }
            .map { ParsedTodo(title: $0.text, dueDate: $0.date) }

        return result.isEmpty ? [ParsedTodo(title: normalized, dueDate: nil)] : result
    }

    // MARK: - 预处理

    private static func preprocess(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "\n", with: " ")
        let fillers = ["嗯", "呃", "啊", "哦", "那个", "就是", "这个", "唉", "额"]
        for f in fillers { t = t.replacingOccurrences(of: f, with: "") }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 切分（安全版本，不用复杂的索引操作）

    private struct Segment {
        var text: String
        var date: Date?
    }

    private static func splitSegments(_ text: String) -> [Segment] {
        var pieces: [String] = [text]

        // 1. 按句号、问号、感叹号、分号切
        let strongPunct = CharacterSet(charactersIn: "。！？；.!?;")
        pieces = pieces.flatMap { splitByCharset($0, charset: strongPunct) }

        // 2. 按强连接词切（安全实现，避免索引越界）
        pieces = pieces.flatMap { splitByConnectors($0) }

        // 3. 按逗号切（只在逗号后明显是新动作时）
        pieces = pieces.flatMap { splitByComma($0) }

        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Segment(text: $0, date: nil) }
    }

    private static func splitByCharset(_ text: String, charset: CharacterSet) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            if let scalar = String(ch).unicodeScalars.first, charset.contains(scalar) {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { result.append(t) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { result.append(t) }
        return result
    }

    private static func splitByConnectors(_ text: String) -> [String] {
        // 简单安全的实现：替换连接词为分隔符|，然后按|切
        var working = text
        let sorted = strongConnectors.sorted { $0.count > $1.count }
        for conn in sorted {
            working = working.replacingOccurrences(of: conn, with: "|||")
        }
        return working.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitByComma(_ text: String) -> [String] {
        // 如果没有逗号，直接返回
        guard text.contains("，") || text.contains(",") else { return [text] }

        let actionPrefixes = ["买", "做", "写", "交", "打", "吃", "去", "见", "约", "回",
                              "送", "取", "拿", "发", "收", "订", "开", "关", "修", "洗",
                              "刷", "跑", "走", "带", "寄", "看", "听", "学", "读",
                              "准备", "整理", "收拾", "打扫", "叫", "通知", "提醒", "联系",
                              "找", "问", "报", "填", "提交", "上传", "下载", "打印",
                              "记得", "要", "得", "需要", "别忘", "帮我"]

        let parts = text.components(separatedBy: CharacterSet(charactersIn: "，,"))
        if parts.count <= 1 { return [text] }

        var result: [String] = []
        var buf = parts[0]
        for i in 1..<parts.count {
            let part = parts[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let startsAction = actionPrefixes.contains { part.hasPrefix($0) }
            if startsAction && buf.count > 2 {
                result.append(buf.trimmingCharacters(in: .whitespacesAndNewlines))
                buf = part
            } else {
                buf = buf + "，" + part
            }
        }
        let last = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { result.append(last) }
        return result.isEmpty ? [text] : result
    }

    // MARK: - 时间提取（只使用 NSDataDetector，安全可靠）

    private static func extractAndRemoveDate(from text: String) -> (String, Date?) {
        let nsText = text as NSString
        var rangesToRemove: [NSRange] = []
        var foundDate: Date?

        let types: NSTextCheckingResult.CheckingType = [.date]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let fullRange = NSRange(location: 0, length: nsText.length)
            let matches = detector.matches(in: text, range: fullRange)
            for m in matches {
                if let date = m.date, m.range.length >= 2 {
                    if foundDate == nil { foundDate = date }
                    rangesToRemove.append(m.range)
                }
            }
        }

        // 从后往前删除，避免range偏移
        var result = text
        for range in rangesToRemove.sorted(by: { $0.location > $1.location }) {
            if let r = Range(range, in: result) {
                result.removeSubrange(r)
            }
        }

        return (result, foundDate)
    }

    // MARK: - 标题清理

    private static func cleanTitle(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 去掉开头的逗号顿号
        while t.hasPrefix("，") || t.hasPrefix(",") || t.hasPrefix("、") {
            t = String(t.dropFirst())
        }

        // 去掉开头修饰语
        let prefixes = ["我要", "我得", "我需要", "记得", "别忘了", "帮我", "给我",
                        "要", "得", "需要", "待会", "等下", "一会", "请"]
        for p in prefixes.sorted(by: { $0.count > $1.count }) {
            if t.hasPrefix(p) {
                t = String(t.dropFirst(p.count))
            }
        }

        // 去掉结尾语气词
        let suffixes = ["啊", "哦", "呢", "吧", "呀", "哈", "哟"]
        for s in suffixes {
            if t.hasSuffix(s) { t = String(t.dropLast()) }
        }

        t = t.replacingOccurrences(of: "一下", with: "")

        while t.hasPrefix("，") || t.hasPrefix(",") {
            t = String(t.dropFirst())
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 日期传播

    private static func propagateDateContext(_ segs: [Segment]) -> [Segment] {
        return segs
    }

    private static func containsTimeComponent(_ d: Date) -> Bool {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (comps.hour ?? 0) != 0 || (comps.minute ?? 0) != 0
    }
}
